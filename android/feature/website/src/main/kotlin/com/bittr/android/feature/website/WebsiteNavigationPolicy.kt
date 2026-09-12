package com.bittr.android.feature.website

import java.net.URI
import java.net.URISyntaxException

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
}

/**
 * Decides every navigation the in-app browser is asked to perform (R-2, R-11).
 *
 * ### `lightning:` and `lnurl` are dropped everywhere, on both trust levels
 *
 * R-2 requires it for third-party origins. In v1 it applies to first-party too,
 * for the plain reason that **there is no LNURL bridge and no navigation
 * interception to hand them to** — see [FirstPartyOrigins]. A `lightning:` URL
 * that is cancelled and dropped is the whole of the behaviour, and it is one
 * function so that "which origins intercept Lightning links" has a single
 * answer rather than a per-trust one.
 *
 * This is the counterpart of `WebsiteViewController.decidePolicyFor`, which
 * instead does:
 *
 * ```swift
 * if absolute.hasPrefix("lightning:") || absolute.hasPrefix("lnurl")
 *     || absolute.contains("tag=login") {
 *     self.handleLNURL(code: …)
 * ```
 *
 * — on every page it has loaded, including the BTCMap URL and the explorer.
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

    /**
     * Lightning containers. Matched on the scheme, never as a substring — the
     * detection R-6 replaces is exactly this decision made with `contains`.
     *
     * `lnurlc` is here even though the wallet has no channel-request flow: the
     * behaviour is to drop it, and it should be dropped by name rather than by
     * falling off the end of the allowlist as an unknown scheme.
     */
    private val LIGHTNING_SCHEMES = setOf(
        "lightning", "lnurl", "lnurlp", "lnurlw", "lnurlc", "keyauth",
    )

    /**
     * @param url the navigation target, as the WebView reported it.
     * @param trust the trust of the page requesting it — derived from the **main
     *   frame's** committed URL, because `WebView.getUrl()` is the main frame's.
     *   Taken so the decision is auditable per trust level and so the signature
     *   does not have to change if a first-party bridge ever ships; it does not
     *   vary the outcome in v1, and the unit tests assert that for both values.
     * @param isForMainFrame `WebResourceRequest.isForMainFrame`, passed straight
     *   through. **Required, with no default** (BIT-58): a default is how a
     *   caller silently opts out of the check, and a caller that forgets this
     *   argument is exactly the bug this parameter exists to prevent.
     *
     * ### Why a subframe cannot inherit [trust]
     *
     * An origin gate reasons about *the page*; a bridge is exposed per *frame*.
     * `shouldOverrideUrlLoading` fires for subframe navigations too, and [trust]
     * describes the main frame — so a cross-origin `<iframe>` on a
     * `getbittr.com` page arrives here carrying `FirstParty`, which it is not.
     * That is the residual gap in the iOS fix (`decidePolicyFor` gating on
     * `webView.url`); demoting a subframe to [WebsiteTrust.ThirdParty] here is
     * what keeps the Android port from inheriting it.
     *
     * In v1 this changes no outcome, because nothing varies by trust. It is
     * written now anyway: the moment a bridge ships is the moment the
     * frame/page distinction becomes load-bearing, and it is far cheaper to
     * have the argument already threaded through than to remember it then.
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

        val scheme = schemeOf(url)?.lowercase()
            ?: return NavigationDecision.Drop("no scheme in '$url'")

        if (scheme in LIGHTNING_SCHEMES) {
            return NavigationDecision.Drop(
                "Lightning navigation dropped: no LNURL bridge exists on any origin " +
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
