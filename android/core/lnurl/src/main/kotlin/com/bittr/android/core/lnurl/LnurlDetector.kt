package com.bittr.android.core.lnurl

/**
 * What a candidate string turned out to be.
 *
 * There is no "probably an LNURL" case on purpose: either it parsed, or it is
 * [NotAnLnurl] and the caller must not start a Lightning flow.
 */
sealed interface LnurlDetection {

    /**
     * A real LNURL.
     *
     * @param decodedUrl the URL the LNURL resolves to, **not yet validated** —
     *   pass it through [LnurlEndpoint.validate] before any network call. Kept
     *   separate so the two failures ("this was not an LNURL" and "this LNURL
     *   points somewhere we will not talk to") stay distinguishable.
     */
    data class Lnurl(val decodedUrl: String, val encoding: LnurlEncoding) : LnurlDetection

    /** @param reason for logs and tests, not for the user. */
    data class NotAnLnurl(val reason: String) : LnurlDetection
}

/** How the LNURL was written, kept for diagnostics and for the auth dialog's copy. */
enum class LnurlEncoding {
    /** A bech32 `lnurl1…` string, checksum verified. */
    Bech32,

    /** An LUD-17 `lnurlp:` / `lnurlw:` / `keyauth:` style scheme URI. */
    SchemeUri,

    /** A Lightning Address (`user@domain`), expanded to its well-known endpoint. */
    LightningAddress,
}

/**
 * Decides whether a string is an LNURL (R-6).
 *
 * **Detection is scheme-based or a real bech32 parse. Never substring matching.**
 * That sentence is the requirement, and these are the three iOS checks it
 * replaces:
 *
 * | iOS | Matches |
 * |---|---|
 * | `h.lowercased().contains("lnurl")` (injected observer) | `https://evil.example/?utm=lnurl` |
 * | `absolute.hasPrefix("lnurl")` (`decidePolicyFor`) | `lnurlsomethingelse://…` |
 * | `absolute.contains("tag=login")` (`decidePolicyFor`) | `https://evil.example/x?tag=login` |
 *
 * The third is the worst of the three: it routes *any* URL with `tag=login` in it
 * into the LNURL-auth path, where the wallet's key signs a challenge. All three
 * are covered by unit tests in `LnurlDetectorTest` (BIT-33 §Acceptance 5).
 */
object LnurlDetector {

    /** The only bech32 human-readable part we accept. Checked, not assumed. */
    private const val LNURL_HRP = "lnurl"

    /**
     * LUD-17 schemes. `lnurlc` (channel request) is absent because the wallet has
     * no channel-request flow; an unhandled scheme is better rejected here than
     * accepted and dropped somewhere further in.
     */
    private val SUPPORTED_SCHEMES = mapOf(
        "lnurlp" to LnurlAction.Pay,
        "lnurlw" to LnurlAction.Withdraw,
        "keyauth" to LnurlAction.Auth,
    )

    /**
     * Conservative Lightning Address shape. Not RFC 5322 — deliberately narrower
     * than "an email address", because the output is a hostname we will make an
     * HTTPS request to.
     */
    private val LIGHTNING_ADDRESS = Regex(
        "^[a-z0-9][a-z0-9._+-]{0,63}@([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$",
    )

    /**
     * @param candidate raw user or deeplink input. A leading `lightning:` prefix is
     *   stripped; nothing else about the string is normalised beyond trimming and
     *   lower-casing, both of which are checksum-safe for bech32.
     */
    fun detect(candidate: String): LnurlDetection {
        val trimmed = candidate.trim()
        if (trimmed.isEmpty()) return LnurlDetection.NotAnLnurl("empty input")

        // `lightning:` is a container, not a scheme with meaning of its own — iOS
        // strips it the same way. Whatever is inside still has to parse.
        val body = trimmed.removeSchemePrefix("lightning:").trim()
        if (body.isEmpty()) return LnurlDetection.NotAnLnurl("lightning: with no payload")

        SUPPORTED_SCHEMES.keys.forEach { scheme ->
            if (body.startsWithSchemeIgnoringCase(scheme)) {
                return detectSchemeUri(body, scheme)
            }
        }

        val lowered = body.lowercase()
        if (LIGHTNING_ADDRESS.matches(lowered)) {
            val (user, domain) = lowered.split("@", limit = 2)
            return LnurlDetection.Lnurl(
                decodedUrl = "https://$domain/.well-known/lnurlp/$user",
                encoding = LnurlEncoding.LightningAddress,
            )
        }

        return detectBech32(body)
    }

    private fun detectSchemeUri(body: String, scheme: String): LnurlDetection {
        // LUD-17 replaces the scheme with https and keeps the rest verbatim. The
        // remainder is not inspected here — LnurlEndpoint.validate is what decides
        // whether the result is somewhere we are willing to talk to.
        val remainder = body.substring(scheme.length + 1)
        if (remainder.isBlank()) {
            return LnurlDetection.NotAnLnurl("$scheme: with no address")
        }
        return LnurlDetection.Lnurl(
            decodedUrl = "https:$remainder",
            encoding = LnurlEncoding.SchemeUri,
        )
    }

    private fun detectBech32(body: String): LnurlDetection {
        val decoded = Bech32.decode(body)
            ?: return LnurlDetection.NotAnLnurl(
                "not a valid bech32 string (bad charset, separator or checksum)",
            )

        // The HRP is checked rather than trusted. A valid bech32 string with HRP
        // `bc` is a Bitcoin address, and treating one as an LNURL would send its
        // bytes to LnurlEndpoint as if they were a URL.
        if (decoded.hrp != LNURL_HRP) {
            return LnurlDetection.NotAnLnurl(
                "bech32 human-readable part is '${decoded.hrp}', expected '$LNURL_HRP'",
            )
        }

        val url = decoded.data.decodeToString()
        // decodeToString replaces malformed UTF-8 with U+FFFD rather than failing,
        // so a payload of arbitrary bytes would otherwise arrive as a plausible
        // string full of replacement characters.
        if (url.isEmpty() || url.any { it == '�' || it.isISOControl() }) {
            return LnurlDetection.NotAnLnurl("lnurl payload is not printable text")
        }

        return LnurlDetection.Lnurl(decodedUrl = url, encoding = LnurlEncoding.Bech32)
    }

    private fun String.removeSchemePrefix(prefix: String): String =
        if (startsWith(prefix, ignoreCase = true)) substring(prefix.length) else this

    /**
     * True only for `scheme:` exactly. `startsWith("lnurl")` is what lets
     * `lnurlsomethingelse://` through on iOS; requiring the colon is the fix.
     */
    private fun String.startsWithSchemeIgnoringCase(scheme: String): Boolean =
        length > scheme.length &&
            regionMatches(0, scheme, 0, scheme.length, ignoreCase = true) &&
            this[scheme.length] == ':'
}
