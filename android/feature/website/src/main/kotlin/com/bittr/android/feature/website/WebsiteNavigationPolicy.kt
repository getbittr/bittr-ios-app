package com.bittr.android.feature.website

import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder

/** What the in-app browser does with a navigation it is asked to perform. */
sealed interface NavigationDecision {

    /** Load it in the WebView. Only ever `http` or `https`. */
    data object Load : NavigationDecision

    /**
     * Cancel it and do nothing else — no dialog, no toast, no handler, no
     * network call.
     *
     * @param reason for the debug log and the unit tests. Never shown: a page
     *   that tries something it may not gets silence, because an error message
     *   is a signal it can probe with.
     */
    data class Drop(val reason: String) : NavigationDecision

    /**
     * Cancel the navigation and hand [code] to the wallet's LNURL handling — iOS's
     * `handleLNURL(code:)` from `decidePolicyFor`. Only ever produced for a
     * main-frame navigation on a first-party page.
     *
     * @param code the LNURL as `handleLNURL` receives it (`URL.lnurlCode`): a
     *   leading `lightning:` removed, a bech32 LNURL lowercased, anything else
     *   untouched. For withdraw and auth this string is a bearer credential —
     *   never log it.
     */
    data class HandleLnurl(val code: String) : NavigationDecision
}

/**
 * Decides every navigation the in-app browser is asked to perform (R-2, R-11).
 *
 * ### Lightning links: handed to the wallet from bittr's own pages, dropped everywhere else
 *
 * The port of `WebsiteViewController.decidePolicyFor`. A navigation is a Lightning
 * link when its scheme is `lightning` or `lnurl`, when it is a bare bech32
 * `lnurl1…`, or when it is an `https` URL carrying a `tag=login` query item (an
 * LNURL-auth callback). Matched on the parsed scheme and query item, never as a
 * substring — the detection R-6 replaced was exactly this decision made with
 * `contains`.
 *
 * Such a link is handed to the wallet only from the **main frame** of a
 * **first-party** page ([FirstPartyOrigins]); from a third-party page (a BTCMap
 * `website`, the block explorer, anything reached from either) or from any
 * subframe it is cancelled and dropped, as iOS cancels it. What the wallet then
 * lets a web page do is `LnurlSourcePolicy`'s call: LNURL-auth only, never pay or
 * withdraw.
 *
 * `lnurlp`, `lnurlw`, `lnurlc` and `keyauth` are dropped on every origin. iOS does
 * not intercept them either; they are dropped by name rather than falling off the
 * end of the scheme allowlist as unknown.
 *
 * **Not ported:** iOS also injects a script into first-party pages that posts the
 * first Lightning anchor on the page to a `WKScriptMessageHandler`. That is a
 * JavaScript bridge, which R-1 keeps out of this app (`JavascriptInterfaceGuardTest`,
 * `WebViewBridgeOriginGuardTest`). A first-party page's links still work, because
 * tapping one is a navigation this function sees.
 *
 * ### Scheme handling is an allowlist
 *
 * `http` and `https` load; everything else is dropped. R-11 names `intent://`,
 * `file://` and `content://` explicitly, and they are the reason the rule is an
 * allowlist rather than a list of those three:
 *
 * - `intent://` is a general-purpose "start any Activity with these extras"
 *   encoding. A page that can drive it can reach any exported component in the
 *   app or on the device.
 * - `file://` and `content://` are how a page tries to read local storage, the
 *   app's private directory included, and are also why
 *   `allowFileAccessFromFileURLs` and `allowUniversalAccessFromFileURLs` are off.
 * - `market://`, `tel:`, `sms:`, `mailto:`, `whatsapp://`, and every scheme
 *   registered by any other app on the device are the long tail — a denylist has
 *   to enumerate them and cannot, so it is the wrong shape.
 *
 * `mailto:` and `tel:` being dropped is a real, small functional loss on the
 * support page. It is recorded in `shared/docs/parity.md` rather than fixed by
 * relaxing the rule: the open-externally button hands the whole page to the
 * system browser, which handles both.
 *
 * ### Every decision names the frame it is for
 *
 * [decide] requires `isForMainFrame`. A page's origin and a frame's origin are
 * different boundaries, and this callback fires for both — see [decide] for why
 * a subframe is never allowed to inherit the main frame's trust (BIT-58).
 */
object WebsiteNavigationPolicy {

    private val LOADABLE_SCHEMES = setOf("http", "https")

    /** The schemes iOS hands to `handleLNURL`. */
    private val HANDLED_LIGHTNING_SCHEMES = setOf("lightning", "lnurl")

    /** Lightning containers iOS does not intercept: dropped on every origin, by name. */
    private val DROPPED_LIGHTNING_SCHEMES = setOf("lnurlp", "lnurlw", "lnurlc", "keyauth")

    /** Bech32 is case-insensitive but must be uniform; this is the lowercase form. */
    private val BECH32_LNURL = Regex("^lnurl1[02-9ac-hj-np-z]{6,}$")

    /**
     * @param url the navigation target, as the WebView reported it.
     * @param trust the trust of the page requesting it — derived from the **main
     *   frame's** committed URL, because `WebView.getUrl()` is the main frame's.
     * @param isForMainFrame `WebResourceRequest.isForMainFrame`, passed straight
     *   through. **Required, with no default** (BIT-58): a default is how a
     *   caller silently opts out of the check, and a caller that forgets this
     *   argument is exactly the bug this parameter exists to prevent.
     *
     * ### Why a subframe cannot inherit [trust]
     *
     * An origin gate reasons about *the page*; a navigation can come from *a
     * frame*. `shouldOverrideUrlLoading` fires for subframe navigations too, and
     * [trust] describes the main frame — so a cross-origin `<iframe>` on a
     * `getbittr.com` page arrives here carrying `FirstParty`, which it is not.
     * Demoting a subframe to [WebsiteTrust.ThirdParty] is what stops that iframe
     * from navigating itself to `lightning:…` and being handed to the wallet — the
     * frame check iOS makes with `targetFrame?.isMainFrame`.
     */
    fun decide(
        url: String?,
        trust: WebsiteTrust,
        isForMainFrame: Boolean,
    ): NavigationDecision {
        // The demotion happens before any decision reads it, so there is no path
        // through this function that sees a subframe's inherited main-frame trust.
        val effectiveTrust = if (isForMainFrame) trust else WebsiteTrust.ThirdParty
        val frame = if (isForMainFrame) "main frame" else "subframe"

        if (url.isNullOrBlank()) return NavigationDecision.Drop("empty navigation target")

        if (isLnurlNavigation(url)) {
            return if (effectiveTrust == WebsiteTrust.FirstParty) {
                NavigationDecision.HandleLnurl(lnurlCode(url))
            } else {
                NavigationDecision.Drop(
                    "Lightning navigation dropped: only a first-party page's main frame may " +
                        "start one (trust=$effectiveTrust, $frame)",
                )
            }
        }

        val scheme = schemeOf(url)?.lowercase()
            ?: return NavigationDecision.Drop("no scheme in the navigation target ($frame)")

        if (scheme in DROPPED_LIGHTNING_SCHEMES) {
            return NavigationDecision.Drop(
                "Lightning navigation dropped: '$scheme' is not handled on any origin " +
                    "(trust=$effectiveTrust, $frame)",
            )
        }

        if (scheme !in LOADABLE_SCHEMES) {
            return NavigationDecision.Drop(
                "scheme '$scheme' is not loadable in the app browser ($frame)",
            )
        }

        // http(s) in a subframe is an ordinary iframe load and must still work —
        // demoting a subframe's trust must not turn the browser into one that
        // cannot render an embedded map, video or payment widget.
        return NavigationDecision.Load
    }

    /**
     * `decidePolicyFor`'s `isLnurlNavigation`: the `lightning` or `lnurl` scheme, a
     * bare bech32 LNURL, or an `https` URL with a `tag=login` query item.
     */
    internal fun isLnurlNavigation(url: String): Boolean {
        val trimmed = url.trim()
        val scheme = schemeOf(trimmed)?.lowercase()
        if (scheme in HANDLED_LIGHTNING_SCHEMES) return true
        if (trimmed.lowercase().startsWith("lnurl1")) return true
        return scheme == "https" && hasLoginTag(trimmed)
    }

    /**
     * iOS's `URL.lnurlCode`: a leading `lightning:` removed, then lowercased only if
     * what is left is a bech32 LNURL. An https `tag=login` callback is passed through
     * untouched — lowercasing it corrupts its path and its k1.
     */
    internal fun lnurlCode(url: String): String {
        val trimmed = url.trim()
        val stripped = if (trimmed.startsWith("lightning:", ignoreCase = true)) {
            trimmed.substring("lightning:".length)
        } else {
            trimmed
        }
        val lowered = stripped.lowercase()
        return if (BECH32_LNURL.matches(lowered)) lowered else stripped
    }

    /** A `tag` query item whose value is `login`, both compared case-insensitively. */
    private fun hasLoginTag(url: String): Boolean {
        val query = try {
            URI(url).rawQuery
        } catch (_: URISyntaxException) {
            url.substringAfter('?', "").substringBefore('#')
        } ?: return false
        return query.split('&').any { item ->
            val name = decode(item.substringBefore('='))
            val value = if ('=' in item) decode(item.substringAfter('=')) else null
            name.equals("tag", ignoreCase = true) && value.equals("login", ignoreCase = true)
        }
    }

    private fun decode(part: String): String =
        runCatching { URLDecoder.decode(part, Charsets.UTF_8.name()) }.getOrDefault(part)

    /**
     * The scheme, or `null` if [url] has none.
     *
     * `URI` first because it is the strict reader, with a manual fallback for the
     * strings it refuses to parse at all — `intent://x#Intent;…` among them. A URL
     * this cannot read has no scheme as far as the policy is concerned, which
     * means it is dropped.
     */
    private fun schemeOf(url: String): String? {
        try {
            URI(url).scheme?.let { return it }
        } catch (_: URISyntaxException) {
            // Fall through to the manual read below.
        }

        val colon = url.indexOf(':')
        if (colon <= 0) return null
        val candidate = url.substring(0, colon)
        // RFC 3986 scheme grammar. Anything else is not a scheme, so: no scheme.
        if (!candidate[0].isLetter()) return null
        if (!candidate.all { it.isLetterOrDigit() || it == '+' || it == '-' || it == '.' }) {
            return null
        }
        return candidate
    }
}
