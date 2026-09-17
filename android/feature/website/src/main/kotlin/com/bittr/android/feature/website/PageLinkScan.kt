package com.bittr.android.feature.website

/**
 * iOS's injected script (`WebsiteViewController.loadView`): a first-party page's Lightning link is
 * picked up without the user tapping it, as getbittr.com's login page expects.
 *
 * iOS installs a `WKUserScript` with a `MutationObserver` that posts the first link to a
 * `messageHandlers.lnurl` bridge. Android has no bridge on purpose (`JavascriptInterfaceGuardTest`,
 * BIT-33 R-1), so [HardenedWebView] runs [SCRIPT] with `evaluateJavascript` instead — which only ever
 * runs in the main frame, iOS's `forMainFrameOnly` — every [POLL_MILLIS] while a first-party page is
 * loaded, and reads the answer from the callback. The page can't call the app; the app asks the page.
 */
object PageLinkScan {

    const val POLL_MILLIS = 1_000L

    /** The same matching as iOS's `lnurlFrom`: a `lightning:` / `lnurl:` href, or a bech32 LNURL in the raw attribute. */
    val SCRIPT = """
        (function () {
            const BECH32_LNURL = /^lnurl1[02-9ac-hj-np-z]{6,}${'$'}/;
            const anchors = Array.from(document.querySelectorAll('a'));
            for (const anchor of anchors) {
                const resolved = anchor.href || '';
                const lowered = resolved.toLowerCase();
                if (lowered.startsWith('lightning:') || lowered.startsWith('lnurl:')) return resolved;
                const raw = (anchor.getAttribute('href') || '').trim().toLowerCase();
                if (BECH32_LNURL.test(raw)) return raw;
            }
            return null;
        })();
    """

    /** `evaluateJavascript`'s result is the value as JSON: a quoted string, or `null`. */
    fun parse(result: String?): String? {
        val value = result?.trim() ?: return null
        if (value.length < 2 || value.first() != '"' || value.last() != '"') return null
        val body = value.substring(1, value.length - 1)
        val out = StringBuilder()
        var i = 0
        while (i < body.length) {
            val c = body[i]
            if (c != '\\' || i + 1 >= body.length) {
                out.append(c)
                i++
                continue
            }
            when (val next = body[i + 1]) {
                'u' -> {
                    val hex = body.substring(i + 2, minOf(i + 6, body.length))
                    hex.toIntOrNull(16)?.let { out.append(it.toChar()) }
                    i += 6
                    continue
                }
                'n' -> out.append('\n')
                't' -> out.append('\t')
                else -> out.append(next)
            }
            i += 2
        }
        return out.toString().takeIf { it.isNotBlank() && WebsiteNavigationPolicy.isLnurlNavigation(it) }
    }
}
