package com.bittr.android.core.lnurl

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 §Acceptance 5, endpoint half: `http://` after decode and
 * `https://127.0.0.1/…` are rejected, plus the rest of R-7's ranges.
 *
 * These run through [LnurlDetector] first where the case is about a *decoded*
 * LNURL, because that is the sequence in production — decode, then validate,
 * then and only then make the request. Testing the validator alone would prove
 * the check works without proving it is reached.
 */
class LnurlEndpointTest {

    private companion object {
        /** A valid `lnurl1…` that decodes to `http://evil.example/x`. */
        const val DECODES_TO_HTTP = "lnurl1dp68gup69uhk2anfdshx27rpd4cxcef00qw8wey7"

        /** A valid `lnurl1…` that decodes to `https://127.0.0.1/lnurlp/abc`. */
        const val DECODES_TO_LOOPBACK =
            "lnurl1dp68gurn8ghj7vfjxuhrqt3s9ccj7mrww4excup0v93xx5vnq97"
    }

    /** Decodes [lnurl] (asserting that it does) and validates the result. */
    private fun validateDecoded(lnurl: String): LnurlEndpointCheck {
        val detection = LnurlDetector.detect(lnurl)
        assertTrue(
            "Fixture problem: $lnurl should decode cleanly so that the endpoint check " +
                "is what rejects it. Got $detection",
            detection is LnurlDetection.Lnurl,
        )
        return LnurlEndpoint.validate((detection as LnurlDetection.Lnurl).decodedUrl)
    }

    // --- §Acceptance 5 ----------------------------------------------------------

    @Test
    fun `rejects an lnurl that decodes to http`() {
        // The checksum is valid and the HRP is right — this IS an LNURL. It just
        // points somewhere we will not talk to, which is a different rejection and
        // has to happen before the request rather than after the response.
        val check = validateDecoded(DECODES_TO_HTTP)

        assertTrue("http:// after decode must be rejected. Got $check", check.isRejected)
    }

    @Test
    fun `rejects an lnurl that decodes to loopback`() {
        val check = validateDecoded(DECODES_TO_LOOPBACK)

        assertTrue("https://127.0.0.1/… must be rejected. Got $check", check.isRejected)
    }

    // --- R-7's ranges, and the spellings a check on 127_0_0_1 would miss --------

    @Test
    fun `rejects every private, loopback, link-local and reserved address`() {
        val rejected = listOf(
            // Loopback, spelled six ways. A string comparison against
            // "127.0.0.1" catches exactly one of them.
            "https://127.0.0.1/x",
            "https://127.0.0.2/x",
            "https://127.1.2.3/x",
            "https://localhost/x",
            "https://foo.localhost/x",
            "https://0.0.0.0/x",
            // Non-canonical spellings of loopback. These do not parse as clean
            // dotted-quads, so they are refused as malformed rather than being
            // handed to a client that might read them as octal, hex or a single
            // 32-bit integer.
            "https://127.1/x",
            "https://0177.0.0.1/x",
            "https://0x7f.0.0.1/x",
            "https://2130706433/x",
            // RFC 1918.
            "https://10.0.0.5/x",
            "https://10.255.255.255/x",
            "https://172.16.0.1/x",
            "https://172.31.255.254/x",
            "https://192.168.1.1/x",
            // Link-local — and the route to cloud metadata services.
            "https://169.254.169.254/x",
            // RFC 6598 carrier-grade NAT.
            "https://100.64.0.1/x",
            "https://100.127.255.255/x",
            // Documentation, protocol-assignment and benchmarking ranges.
            "https://192.0.2.1/x",
            "https://198.51.100.7/x",
            "https://203.0.113.9/x",
            "https://198.18.0.1/x",
            // Multicast, reserved, broadcast.
            "https://224.0.0.1/x",
            "https://240.0.0.1/x",
            "https://255.255.255.255/x",
            // IPv6, including public — a bare v6 literal has no legitimate reason
            // to appear and every reserved-range mistake in v6 is subtle.
            "https://[::1]/x",
            "https://[fe80::1]/x",
            "https://[fc00::1]/x",
            "https://[::ffff:127.0.0.1]/x",
            "https://[2606:4700:4700::1111]/x",
            // Names that only resolve inside the user's network.
            "https://printer.local/x",
            "https://api.internal/x",
            "https://thing.home.arpa/x",
            // Single-label host: resolves through the user's search domain.
            "https://intranet/x",
            "https://wiki/x",
            // Not https.
            "http://pay.example.com/x",
            "ftp://pay.example.com/x",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "//pay.example.com/x",
            // Credentials in the authority: reads first-party to a person,
            // resolves to evil.example.
            "https://getbittr.com@evil.example/x",
            "https://user:pass@evil.example/x",
            // No host at all.
            "https:///x",
            "https://",
            "not a url at all",
            "",
        )

        val wronglyAccepted = rejected.filterNot { LnurlEndpoint.validate(it).isRejected }

        assertTrue(
            "These must all be rejected before any network call is made (BIT-33 R-7):\n  " +
                wronglyAccepted.joinToString("\n  "),
            wronglyAccepted.isEmpty(),
        )
    }

    @Test
    fun `accepts ordinary public https endpoints`() {
        val accepted = listOf(
            "https://getbittr.com/.well-known/lnurlp/tom",
            "https://pay.example.com/lnurlp/abc?amount=1000",
            "https://sub.domain.example.co.uk/x",
            // A public IPv4 literal is allowed: unusual, but not private, and the
            // rule is about reachability rather than about taste.
            "https://93.184.216.34/x",
            // Trailing root dot is a legitimate absolute name.
            "https://pay.example.com./x",
            // Punycode host.
            "https://xn--bcher-kva.example/x",
        )

        val wronglyRejected = accepted.filter { LnurlEndpoint.validate(it).isRejected }

        assertTrue(
            "These are ordinary public endpoints and must be accepted — a validator that " +
                "rejects everything is not a control, it is an outage:\n  " +
                wronglyRejected.joinToString("\n  "),
            wronglyRejected.isEmpty(),
        )
    }

    @Test
    fun `returns the url unchanged and the host lower-cased`() {
        val check = LnurlEndpoint.validate("https://Pay.Example.COM/lnurlp/abc?amount=1000")

        // The URL is handed back verbatim rather than rebuilt from parts, so that
        // what was validated is exactly what will be requested. Normalising it
        // here would mean the request could differ from the string that passed.
        assertEquals(
            LnurlEndpointCheck.Usable(
                url = "https://Pay.Example.COM/lnurlp/abc?amount=1000",
                host = "pay.example.com",
            ),
            check,
        )
    }

    private val LnurlEndpointCheck.isRejected: Boolean
        get() = this is LnurlEndpointCheck.Rejected
}
