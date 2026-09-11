package com.bittr.android.feature.website

import java.net.URI
import java.net.URISyntaxException

/**
 * How much the in-app browser trusts the page it currently has loaded.
 *
 * Two values, and the difference between them is *only* whether a message bridge
 * may be attached. Both get the identical hardening baseline (R-11) and both
 * cancel `lightning:` and `lnurl` navigations.
 */
enum class WebsiteTrust {

    /** An origin on [FirstPartyOrigins.ALLOWED]. The only place a bridge could go. */
    FirstParty,

    /**
     * Anything else — a BTCMap `website`, the block explorer, and anything reached
     * by navigation from either. No bridge, ever (R-2).
     */
    ThirdParty,
}

/**
 * The first-party origin allowlist (R-3), and the only way trust is decided.
 *
 * ### The allowlist is `getbittr.com` and nothing else
 *
 * BIT-21's call-site table filed the block explorer under first-party. **It is
 * not.** `EnvironmentConfig.explorerURL` is `https://mempool.space` in Release and
 * `https://esplora-regtest.bittr.io` in Debug, and pinning the allowlist to "the
 * first-party hosts" as originally worded would have handed a wallet bridge to an
 * origin nobody here controls. The explorer gets the same treatment as the map's
 * arbitrary third-party URL, because that is what it is.
 *
 * `www.getbittr.com` is also absent, deliberately. The three first-party pages are
 * requested without it. If `getbittr.com` ever starts redirecting to `www`, the
 * redirect lands on a non-allowlisted origin and trust degrades to
 * [WebsiteTrust.ThirdParty] — which loses nothing in v1 (there is no bridge) and
 * fails in the safe direction. Adding a host here is a deliberate act, reviewed as
 * one; `WebViewBridgeOriginGuardTest` in `:app` fails the build if this set ever
 * grows a wildcard or an explorer host.
 *
 * ### Trust is derived, never passed in
 *
 * [trustOf] takes the URL the WebView actually has loaded. No call site declares
 * its own trust level, because the call site that matters —
 * `map.onePlace.websiteButton` — is handed its URL by BTCMap place data, and a
 * parameter a caller sets is a parameter a caller can get wrong. `WebsiteScreen`
 * re-derives on every committed navigation, so a first-party page that redirects
 * off-origin, or a link followed three hops out, is reclassified rather than
 * inheriting the trust of whatever opened the screen.
 */
object FirstPartyOrigins {

    /**
     * Hosts served by Bittr, exact matches only.
     *
     * Suffix matching is what this deliberately is not: `endsWith("getbittr.com")`
     * also accepts `evil-getbittr.com` and `getbittr.com.evil.example`.
     */
    private val ALLOWED = setOf("getbittr.com")

    /**
     * The value `allowedOriginRules` would take if a bridge were ever added
     * (R-3) — exact origins, never `"*"`.
     *
     * **No bridge ships in v1.** `androidx.webkit` is not a dependency of this
     * module, so `WebViewCompat.addWebMessageListener` is not merely unused, it is
     * not on the classpath. This constant exists so that the allowlist has one
     * definition shared by [trustOf] and by any future bridge, rather than the
     * bridge arriving with a second, looser copy of it.
     */
    val allowedOriginRules: Set<String> = ALLOWED.map { "https://$it" }.toSet()

    /**
     * Classifies [url].
     *
     * Fails closed: anything unparseable, non-https, credential-bearing or on a
     * non-default port is [WebsiteTrust.ThirdParty]. A URL we cannot read
     * confidently is not one to attach a wallet bridge to.
     */
    fun trustOf(url: String?): WebsiteTrust {
        if (url.isNullOrBlank()) return WebsiteTrust.ThirdParty

        val uri = try {
            URI(url)
        } catch (_: URISyntaxException) {
            return WebsiteTrust.ThirdParty
        }

        if (uri.scheme?.lowercase() != "https") return WebsiteTrust.ThirdParty

        // `https://getbittr.com@evil.example/` reads first-party to a person and
        // resolves to evil.example. URI puts `getbittr.com` in userInfo and
        // `evil.example` in host, so the host check below is already right — but
        // a URL with credentials in it is refused outright rather than relying on
        // that, because the next person to touch this may compare the authority.
        if (uri.userInfo != null) return WebsiteTrust.ThirdParty

        // Port 443 or unstated. A first-party page is not served off :8443, and
        // an origin is scheme + host + port — treating the port as cosmetic is how
        // an origin check stops being one.
        if (uri.port != -1 && uri.port != 443) return WebsiteTrust.ThirdParty

        val host = uri.host?.lowercase()?.removeSuffix(".") ?: return WebsiteTrust.ThirdParty

        return if (host in ALLOWED) WebsiteTrust.FirstParty else WebsiteTrust.ThirdParty
    }
}
