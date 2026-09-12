package com.bittr.android.core.common.destination

/**
 * LNURL, in the three shapes bittr accepts: a bech32 `lnurl1…`, a lightning address
 * (`user@domain`), and a bare LNURL-auth URL.
 *
 * This is the port of `handleLNURL` (`SendLNURL.swift:118-162`) split in two: the
 * pure half — decide *what this string is and where it points* — lives here, and
 * the half that makes network calls stays with Send and the engine.
 *
 * ## The case-sensitivity bug that is deliberately not ported
 *
 * BIT-84 and BIT-85 record it and BIT-100 says to fix it in the port. On iOS,
 * detection and routing disagree about case:
 *
 * - *Detection* lower-cases first — `code.lowercased().extractLNURL()`
 *   (`AddressParsing.swift:21`), matching `hasPrefix("lnurl")`. So an upper-case
 *   `LNURL1…` is recognised.
 * - *Routing* then does a case-**sensitive** substring test:
 *   `} else if code.contains("tag=login&k1") {` (`SendLNURL.swift:130`).
 *
 * An LNURL-auth URL whose query is upper-cased — `?TAG=LOGIN&K1=…`, which is legal,
 * query parameter names are not required to be lower-case — is therefore detected as
 * an LNURL but misses the auth branch. It falls through to `LNURLDecoder.decode`,
 * which cannot decode a plain URL, and the user gets "couldn't decode LNURL" for a
 * login request that was perfectly well-formed.
 *
 * Everything below matches case-insensitively: the `lnurl` prefix, the scheme, the
 * `tag`/`k1`/`action` parameter names, and the `login` tag value. The one thing that
 * stays case-sensitive is the **k1 value itself**, because it is hex and is compared
 * by its decoded bytes, so case is already irrelevant there.
 * `DestinationParserTest` pins the upper-case case.
 */
internal object Lnurl {

    data class Parsed(
        /** The LNURL as scanned, minus control characters. */
        val raw: String,
        val target: LnurlTarget,
    )

    private val EMAIL = Regex("[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")

    /** Does this component look like an LNURL at all? The port of `extractLNURL`. */
    fun looksLikeLnurl(component: String): Boolean =
        isLightningAddress(component) || component.startsWith("lnurl", ignoreCase = true)

    fun isLightningAddress(component: String): Boolean = EMAIL.matches(component)

    /**
     * Resolves [candidate] to a [Parsed], or returns `null` if it is not an LNURL.
     *
     * The order of the three branches is iOS's (`SendLNURL.swift:125-145`), and it
     * matters: a lightning address is checked before the auth-URL test because
     * `user@domain` can contain neither a `tag` nor a bech32 payload, and the bech32
     * decode is last because it is the only one that can fail expensively.
     */
    fun parse(candidate: String): Parsed? {
        val raw = sanitize(candidate)

        // `normalised` is what the caller sees as [Parsed.raw], and it is only
        // lower-cased where lower-casing provably loses nothing.
        //
        // For a bech32 `LNURL1…` it loses nothing by construction — bech32 forbids
        // mixed case precisely so that case can be discarded — and discarding it is
        // what makes a scan of an upper-case QR equal to a paste of its lower-case
        // twin. For a bare URL it would lose plenty: a path segment, or a query
        // value that is not the k1, can be case-sensitive. iOS lower-cases the whole
        // code before it ever gets here (`AddressParsing.swift:21`) and so mangles
        // those; this does not.
        val normalised: String
        val url: String

        when {
            // A lightning address is an alias for an lnurlp endpoint. The domain is
            // lower-cased because a hostname is case-insensitive; the local part is
            // left alone, because in general it is not.
            isLightningAddress(raw) -> {
                val at = raw.lastIndexOf('@')
                val user = raw.substring(0, at)
                val domain = raw.substring(at + 1).lowercase()
                normalised = "$user@$domain"
                url = "https://$domain/.well-known/lnurlp/$user"
            }

            // Already a URL carrying an auth challenge. iOS's test here is the
            // case-sensitive `contains("tag=login&k1")`; this one is not, and it does
            // not require the two parameters to be adjacent or in that order either,
            // which `contains` silently did.
            carriesAuthChallenge(raw) -> {
                normalised = raw
                url = raw
            }

            raw.startsWith("lnurl", ignoreCase = true) -> {
                normalised = raw.lowercase()
                url = decodeBech32(raw) ?: return null
            }

            else -> return null
        }

        return Parsed(raw = normalised, target = classify(url))
    }

    /**
     * Strips NUL and control characters, as `sanitizeLNURLString`
     * (`SendLNURL.swift`) does. A QR decoder can emit a trailing newline, and a URL
     * with one on the end is a URL that will not resolve.
     */
    private fun sanitize(value: String): String =
        value.filter { it.code != 0 && !it.isISOControl() }.trim()

    private fun carriesAuthChallenge(value: String): Boolean {
        val query = queryOf(value) ?: return false
        val params = parseQuery(query)
        return params["tag"].equals("login", ignoreCase = true) && params["k1"] != null
    }

    /** Bech32 `lnurl1…` → the UTF-8 URL it encodes. The port of `LNURLDecoder.decode`. */
    private fun decodeBech32(value: String): String? {
        // Not capped at 90 characters: an LNURL routinely exceeds it. BIP-173's limit
        // is a property of addresses, not of the encoding.
        val decoded = Bech32.decode(value, maxLength = Int.MAX_VALUE) ?: return null
        if (decoded.hrp != "lnurl") return null
        if (decoded.encoding != Bech32.Encoding.BECH32) return null

        val bytes = Bech32.convertBits(decoded.data, fromBits = 5, toBits = 8, pad = false)
            ?: return null
        return bytes.toString(Charsets.UTF_8)
    }

    /**
     * The port of the auth test at `SendLNURL.swift:150`: tag is `login` and k1 is
     * 32 bytes of hex. Both conditions are iOS's; only the case-sensitivity is not.
     *
     * A URL that claims `tag=login` but carries a k1 of the wrong length is *not*
     * treated as auth — it falls through to [Target.Service], exactly as iOS's
     * `k1Data.count == 32` guard makes it. Signing a short challenge is worse than
     * failing to.
     */
    private fun classify(url: String): LnurlTarget {
        val query = queryOf(url) ?: return LnurlTarget.Service(url)
        val params = parseQuery(query)

        val tag = params["tag"]
        val k1 = params["k1"]
        if (tag.equals("login", ignoreCase = true) && k1 != null && isHex32(k1)) {
            return LnurlTarget.Auth(callbackUrl = url, k1Hex = k1, action = params["action"])
        }

        return LnurlTarget.Service(url)
    }

    private fun queryOf(url: String): String? {
        val start = url.indexOf('?')
        if (start < 0 || start == url.length - 1) return null
        val fragment = url.indexOf('#', start)
        return if (fragment < 0) url.substring(start + 1) else url.substring(start + 1, fragment)
    }

    /** Parameter names are lower-cased; values are left exactly as they arrived. */
    private fun parseQuery(query: String): Map<String, String> =
        query.split('&')
            .mapNotNull { pair ->
                val equals = pair.indexOf('=')
                if (equals <= 0) null else {
                    pair.substring(0, equals).lowercase() to pair.substring(equals + 1)
                }
            }
            .toMap()

    private fun isHex32(value: String): Boolean =
        value.length == 64 && value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
}
