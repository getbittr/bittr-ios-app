package com.bittr.android.core.lnurl

/** An LNURL-auth (LUD-04) challenge, after parsing and before the user has seen it. */
data class LnurlAuthRequest(
    val callbackUrl: String,
    /** `k1`, hex, exactly 32 bytes' worth. Checked at construction by [LnurlAuth.parse]. */
    val k1Hex: String,
    /** LUD-04 `action`: `register`, `login`, `link`, `auth`, or absent. */
    val action: String?,
)

/** Everything the auth dialog must put on screen. */
sealed interface LnurlAuthPrompt {

    /**
     * @param callbackOrigin the full `https://host` of the callback, shown verbatim
     *   (R-9). Not a shortened or prettified form: the point is that the user can
     *   see which site is about to receive a signature from their wallet key, and
     *   truncation is how `login.getbittr.com.evil.example` reads as
     *   `login.getbittr.com…`.
     * @param requestingPage what asked. `null` for a QR scan or deeplink, where
     *   there is no page; a page's own title for [LnurlSource.FirstPartyWeb], which
     *   R-9 requires be named.
     * @param action LUD-04 action, so "log in" and "register an account" are not
     *   the same prompt.
     */
    data class Confirm(
        val callbackOrigin: String,
        val requestingPage: RequestingPage?,
        val action: String?,
        val request: LnurlAuthRequest,
        val source: LnurlSource,
    ) : LnurlAuthPrompt

    data class Blocked(val reason: String) : LnurlAuthPrompt
}

/**
 * The page that asked for an auth signature.
 *
 * @param origin what the WebView reported the message came from. Trustworthy.
 * @param title the page's own `document.title`. **Attacker-controlled** even on a
 *   first-party origin, if any part of that origin renders user content. Kept in
 *   its own field so the UI cannot accidentally interpolate it where the origin
 *   belongs.
 */
data class RequestingPage(val origin: String, val title: String?)

/**
 * Parses and gates LNURL-auth (R-9).
 *
 * ### Why `tag=login` is not a detection rule
 *
 * iOS reaches this flow from two places. `SendLNURL.swift` requires the full
 * shape — `tag=login`, a `k1` of exactly 32 bytes, a parseable callback — which is
 * correct. But `WebsiteViewController.decidePolicyFor` routes on
 * `absolute.contains("tag=login")` alone, so **any** URL in the page containing
 * that substring anywhere enters the auth path. The wallet's identity key signs
 * challenges; the bar for entering that path is the full parse below, from every
 * source, and nothing else.
 */
object LnurlAuth {

    private const val K1_BYTES = 32

    /**
     * Parses [url] as an LNURL-auth request, or returns `null` if it is not one.
     *
     * `null` means "not auth" — the caller should carry on treating it as an
     * ordinary LNURL — and is deliberately different from a [LnurlAuthPrompt.Blocked],
     * which means "this is auth and it may not proceed".
     */
    fun parse(url: String): LnurlAuthRequest? {
        val endpoint = LnurlEndpoint.validate(url)
        if (endpoint !is LnurlEndpointCheck.Usable) return null

        val query = url.substringAfter('?', "")
        if (query.isEmpty()) return null

        val params = query.split('&').mapNotNull { pair ->
            val name = pair.substringBefore('=', pair)
            val value = pair.substringAfter('=', "")
            if (name.isEmpty()) null else name to value
        }.toMap()

        if (params["tag"] != "login") return null

        val k1 = params["k1"] ?: return null
        if (!isHex(k1) || k1.length != K1_BYTES * 2) return null

        return LnurlAuthRequest(
            callbackUrl = endpoint.url,
            k1Hex = k1.lowercase(),
            action = params["action"]?.takeIf { it.isNotBlank() },
        )
    }

    /**
     * Builds the prompt for [request], or blocks it.
     *
     * There is no unprompted path: [LnurlAuthPrompt.Confirm] is the only success
     * value, so signing cannot be reached without having rendered a dialog.
     */
    fun prompt(request: LnurlAuthRequest, source: LnurlSource): LnurlAuthPrompt {
        when (val permission = LnurlSourcePolicy.permit(LnurlAction.Auth, source)) {
            is LnurlPermission.Denied -> return LnurlAuthPrompt.Blocked(permission.reason)
            LnurlPermission.Allowed -> Unit
        }

        val origin = originOf(request.callbackUrl)
            ?: return LnurlAuthPrompt.Blocked("that login request has no readable address")

        return LnurlAuthPrompt.Confirm(
            callbackOrigin = origin,
            requestingPage = when (source) {
                is LnurlSource.FirstPartyWeb -> RequestingPage(source.origin, source.pageTitle)
                LnurlSource.QrScan, LnurlSource.Deeplink -> null
            },
            action = request.action,
            request = request,
            source = source,
        )
    }

    /** `https://host` from a validated URL. Scheme and host only — no path, no query. */
    private fun originOf(url: String): String? {
        val check = LnurlEndpoint.validate(url)
        return if (check is LnurlEndpointCheck.Usable) "https://${check.host}" else null
    }

    private fun isHex(value: String): Boolean =
        value.isNotEmpty() && value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
}
