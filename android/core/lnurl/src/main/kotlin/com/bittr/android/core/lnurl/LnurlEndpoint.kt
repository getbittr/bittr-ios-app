package com.bittr.android.core.lnurl

import java.net.URI
import java.net.URISyntaxException

/** The outcome of validating a decoded LNURL against [LnurlEndpoint]'s rules. */
sealed interface LnurlEndpointCheck {

    /**
     * @param url the URL as it should be requested. Not rebuilt from parts —
     *   the caller's string, so no normalisation can change what was validated
     *   into something else.
     * @param host lower-cased host, for showing the user which server is involved.
     */
    data class Usable(val url: String, val host: String) : LnurlEndpointCheck

    /** @param reason user-facing; shown when an LNURL points somewhere we will not go. */
    data class Rejected(val reason: String) : LnurlEndpointCheck
}

/**
 * Validates a decoded LNURL before anything on the network is touched (R-7).
 *
 * **Called before the first request, not around it.** The whole value of this
 * check is its position: an LNURL that decodes to `http://127.0.0.1:8080/…` or
 * `https://10.0.0.5/…` is an instruction to make a request from inside the user's
 * network, and by the time a response comes back the request has already
 * happened. `LnurlRequest` in this module is the only thing that should be issuing
 * these calls, and it will not do so without a [LnurlEndpointCheck.Usable].
 *
 * ### What this cannot do, stated rather than implied
 *
 * This validates the *literal* host. It does not resolve DNS, so a public
 * hostname whose A record points at `192.168.1.1` passes here. Closing that means
 * pinning the resolved address at connection time, which is a networking-layer
 * change and is not what R-7 asks for. It is also not the control that carries the
 * weight: what keeps a hostile party from getting an LNURL in front of the wallet
 * at all is that no web page can hand one over (see [LnurlSource]). Recorded here
 * so the next person reads the limit off the code instead of assuming it away.
 */
object LnurlEndpoint {

    private val PRIVATE_SUFFIXES = listOf(
        // mDNS and RFC 8375 / RFC 6762 names — a name that only resolves inside
        // the user's network.
        ".local",
        ".localhost",
        ".internal",
        ".home.arpa",
    )

    fun validate(url: String): LnurlEndpointCheck {
        val uri = try {
            URI(url)
        } catch (_: URISyntaxException) {
            return reject("that Lightning link is not a valid web address")
        }

        // Exact match, not equalsIgnoreCase against a set: the only acceptable
        // scheme is https. An LNURL that decodes to http:// is either a
        // misconfiguration or a downgrade, and both are refused rather than
        // upgraded — silently rewriting it to https would hide which one it was.
        if (uri.scheme?.lowercase() != "https") {
            return reject(
                "that Lightning link is not secure (it uses " +
                    "${uri.scheme ?: "no scheme"}, and only https is allowed)",
            )
        }

        // Credentials in the authority are how `https://getbittr.com@evil.example/`
        // gets read as first-party by a human and as `evil.example` by the client.
        // Nothing legitimate needs them.
        if (uri.userInfo != null) {
            return reject("that Lightning link contains embedded credentials")
        }

        val host = uri.host?.lowercase()
            ?: return reject("that Lightning link has no server name")
        if (host.isEmpty()) return reject("that Lightning link has no server name")

        if (host == "localhost" || PRIVATE_SUFFIXES.any { host.endsWith(it) }) {
            return reject("that Lightning link points inside your own network")
        }

        // URI keeps IPv6 literals in brackets; strip them before parsing.
        val literal = host.removeSurrounding("[", "]")
        hostRejectionReason(literal)?.let { return reject(it) }

        return LnurlEndpointCheck.Usable(url = url, host = host)
    }

    /**
     * Non-null when [literal] is a host we refuse to talk to.
     *
     * Structured as an allowlist — a clean public dotted-quad or a well-formed
     * multi-label DNS name, and nothing else — rather than as a list of bad
     * patterns. A denylist here is the wrong shape: the interesting inputs are
     * alternative *spellings* of loopback (`127.1`, `0177.0.0.1`, `0x7f.1`,
     * `2130706433`), and a check that pattern-matches has to think of each one,
     * while a check that insists on a canonical form rejects all of them
     * including the spellings nobody has thought of yet.
     */
    private fun hostRejectionReason(literal: String): String? {
        // Any colon means an IPv6 literal. Every one is refused, public ones
        // included: this is a wallet talking to LNURL servers on the open web,
        // all of which have names, so a bare IPv6 address has no legitimate
        // reason to appear — and enumerating the reserved v6 ranges correctly is
        // more code than the case is worth.
        if (literal.contains(':')) return RAW_IPV6

        // Per the URL spec, a host whose last label is entirely numeric is parsed
        // as an IP address rather than a name. So anything that *could* be read as
        // an address must survive the strict dotted-quad parse — otherwise the
        // client is free to read `0177.0.0.1` as octal loopback while a name-shaped
        // check waves it through.
        if (looksLikeAddress(literal)) {
            val octets = parseIpv4(literal) ?: return MALFORMED_ADDRESS
            return ipv4Reason(octets)
        }

        if (!HOSTNAME.matches(literal)) return MALFORMED_HOST

        return null
    }

    /**
     * True when the final label is numeric — decimal or `0x`-prefixed hex — which
     * is the condition under which a host is address-like. Covers `2130706433`,
     * `127.1`, `0x7f.0.0.1` and `192.168.0xff` as well as ordinary dotted-quads.
     */
    private fun looksLikeAddress(literal: String): Boolean {
        val last = literal.removeSuffix(".").substringAfterLast('.')
        if (last.isEmpty()) return false
        if (last.all { it in '0'..'9' }) return true
        val hexBody = last.removePrefix("0x").removePrefix("0X")
        return hexBody.length < last.length &&
            hexBody.isNotEmpty() &&
            hexBody.all { it in '0'..'9' || it in 'a'..'f' }
    }

    /**
     * Well-formed DNS name: two or more labels, each 1–63 characters of letters,
     * digits and inner hyphens, with an optional root dot.
     *
     * Two labels minimum is a rule, not a formality — `https://intranet/` and
     * `https://wiki/` are private names that resolve through the user's search
     * domain, and they are neither IP literals nor caught by the `.local` /
     * `.internal` suffix list.
     */
    private val HOSTNAME = Regex(
        "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.?$",
    )

    private fun ipv4Reason(o: IntArray): String? = when {
        // 0.0.0.0/8 — "this network". 0.0.0.0 itself routes to localhost on Linux.
        o[0] == 0 -> "that Lightning link points at an unroutable address"
        // 10/8, 172.16/12, 192.168/16 — RFC 1918.
        o[0] == 10 -> PRIVATE_NETWORK
        o[0] == 172 && o[1] in 16..31 -> PRIVATE_NETWORK
        o[0] == 192 && o[1] == 168 -> PRIVATE_NETWORK
        // 127/8 — loopback. The whole /8, not just 127.0.0.1: 127.1 and
        // 127.0.0.2 reach the same machine and are exactly how a check that
        // string-compares against "127.0.0.1" gets walked past.
        o[0] == 127 -> LOOPBACK
        // 169.254/16 — link-local, and the route to cloud metadata services.
        o[0] == 169 && o[1] == 254 -> LINK_LOCAL
        // 100.64/10 — RFC 6598 carrier-grade NAT, also Tailscale's range.
        o[0] == 100 && o[1] in 64..127 -> PRIVATE_NETWORK
        // 192.0.0/24, 192.0.2/24, 198.51.100/24, 203.0.113/24 — IETF protocol
        // assignments and documentation ranges. 198.18/15 — benchmarking.
        o[0] == 192 && o[1] == 0 && (o[2] == 0 || o[2] == 2) -> RESERVED
        o[0] == 198 && o[1] == 51 && o[2] == 100 -> RESERVED
        o[0] == 203 && o[1] == 0 && o[2] == 113 -> RESERVED
        o[0] == 198 && o[1] in 18..19 -> RESERVED
        // 224/4 multicast, 240/4 reserved, 255.255.255.255 broadcast.
        o[0] in 224..255 -> RESERVED
        else -> null
    }

    private const val PRIVATE_NETWORK = "that Lightning link points inside a private network"
    private const val LOOPBACK = "that Lightning link points at this device"
    private const val LINK_LOCAL = "that Lightning link points at a link-local address"
    private const val RESERVED = "that Lightning link points at a reserved address"
    private const val RAW_IPV6 = "that Lightning link points at a raw IPv6 address"
    private const val MALFORMED_ADDRESS = "that Lightning link points at a malformed address"
    private const val MALFORMED_HOST = "that Lightning link has an unusable server name"

    /**
     * Strict dotted-quad only: four parts, each 1–3 decimal digits, no leading
     * zeros, each 0–255.
     *
     * `InetAddress` is not used because it resolves — calling it here would make a
     * DNS request from the middle of a function whose entire purpose is to run
     * before any network traffic. It is also more permissive than this: it accepts
     * `0177.0.0.1` and `2130706433` as loopback, which are precisely the spellings
     * a bypass would use, and it is the caller's HTTP client rather than
     * `InetAddress` that decides how to read them. So: anything that is not a
     * clean dotted-quad is treated as a hostname and falls through to the suffix
     * and IPv6 checks above rather than being parsed as an address.
     */
    private fun parseIpv4(literal: String): IntArray? {
        val parts = literal.split('.')
        if (parts.size != 4) return null
        val octets = IntArray(4)
        for (i in 0..3) {
            val part = parts[i]
            if (part.isEmpty() || part.length > 3) return null
            if (part.any { it !in '0'..'9' }) return null
            if (part.length > 1 && part[0] == '0') return null
            val value = part.toInt()
            if (value > 255) return null
            octets[i] = value
        }
        return octets
    }

    private fun reject(reason: String) = LnurlEndpointCheck.Rejected(reason)
}
