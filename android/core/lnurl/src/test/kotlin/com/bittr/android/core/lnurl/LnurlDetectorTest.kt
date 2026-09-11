package com.bittr.android.core.lnurl

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 §Acceptance 5, detection half: the three iOS matches that are not
 * LNURLs, plus a bech32 string with a broken checksum.
 *
 * The vectors here were generated with a reference bech32 encoder rather than
 * copied from this implementation, so a bug in [Bech32] cannot make its own
 * fixtures agree with it. The generator is in the BIT-33 notes; regenerate with
 * any BIP-173 implementation.
 */
class LnurlDetectorTest {

    private companion object {
        /** `https://getbittr.com/.well-known/lnurlp/tom` */
        const val VALID_GETBITTR =
            "lnurl1dp68gurn8ghj7em9w33xjar5wghxxmmd9uh8wetvdskkkmn0wahz7mrww4excup0w3hk67r0vgs"

        /** `https://pay.example.com/lnurlp/abc` */
        const val VALID_PAY_EXAMPLE =
            "lnurl1dp68gurn8ghj7urp0yhx27rpd4cxcefwvdhk6tmvde6hymrs9askyccdpnsxy"

        /** `https://evil.example/x`, encoded with HRP `bc` rather than `lnurl`. */
        const val WRONG_HRP = "bc1dp68gurn8ghj7etkd9kzuetcv9khqmr99auqegxdsk"
    }

    // --- The three iOS substring matches (§Acceptance 5) -------------------------

    @Test
    fun `rejects a plain URL that merely contains the letters lnurl`() {
        // iOS's injected observer: h.lowercased().contains("lnurl"). Any page with
        // this link in it posts to the native handler, on every origin the browser
        // loads — including a BTCMap merchant page.
        val detection = LnurlDetector.detect("https://evil.example/?utm=lnurl")

        assertTrue(
            "A URL containing 'lnurl' as a substring is not an LNURL. Got $detection",
            detection is LnurlDetection.NotAnLnurl,
        )
    }

    @Test
    fun `rejects a plain URL containing tag=login`() {
        // WebsiteViewController.decidePolicyFor: absolute.contains("tag=login")
        // routes straight into handleLNURL, where the wallet's identity key signs
        // a challenge. This is the worst of the three iOS matches.
        val detection = LnurlDetector.detect("https://evil.example/x?tag=login")

        assertTrue(
            "A URL containing 'tag=login' is not an LNURL. Got $detection",
            detection is LnurlDetection.NotAnLnurl,
        )
    }

    @Test
    fun `rejects a scheme that merely starts with the letters lnurl`() {
        // absolute.hasPrefix("lnurl") matches this. Requiring the colon is the fix.
        val detection = LnurlDetector.detect("lnurlsomethingelse://evil.example/x")

        assertTrue(
            "'lnurlsomethingelse://' is not an LNURL scheme. Got $detection",
            detection is LnurlDetection.NotAnLnurl,
        )
    }

    // --- Checksum and encoding (§Acceptance 5) ----------------------------------

    @Test
    fun `rejects a bech32 lnurl with a bad checksum`() {
        // Last data character altered, so the payload still decodes to a plausible
        // URL and only the checksum disagrees. This is the case a length or prefix
        // check cannot see.
        val corrupted = VALID_GETBITTR.dropLast(1) + if (VALID_GETBITTR.last() == 's') 'q' else 's'

        val detection = LnurlDetector.detect(corrupted)

        assertTrue(
            "An lnurl1 string with a bad checksum must be rejected. Got $detection",
            detection is LnurlDetection.NotAnLnurl,
        )
    }

    @Test
    fun `rejects a valid bech32 string whose human-readable part is not lnurl`() {
        // A Bitcoin address is a valid bech32 string. Trusting the checksum without
        // checking the HRP would hand its bytes to the endpoint validator as a URL.
        val detection = LnurlDetector.detect(WRONG_HRP)

        assertTrue(
            "A bech32 string with HRP 'bc' is not an LNURL. Got $detection",
            detection is LnurlDetection.NotAnLnurl,
        )
    }

    @Test
    fun `rejects a mixed-case bech32 string`() {
        val mixed = VALID_GETBITTR.substring(0, 10).uppercase() + VALID_GETBITTR.substring(10)

        assertTrue(
            "Mixed case is invalid bech32 — it is how one logical string gets two " +
                "checksums.",
            LnurlDetector.detect(mixed) is LnurlDetection.NotAnLnurl,
        )
    }

    @Test
    fun `rejects assorted near-misses`() {
        val notLnurls = listOf(
            "",
            "   ",
            "lightning:",
            "lnurl1",
            "lnurl",
            "1",
            "lnurl1qqqqqq",
            // Bech32 charset excludes b, i, o and 1 in the data part.
            "lnurl1bbbbbbbbbb",
            "https://getbittr.com/support",
            "bitcoin:bc1qexample",
            // A payment request, not an LNURL. Valid bech32 with HRP lnbc.
            "lnbc1invalidbutlooksright",
        )

        val wronglyAccepted = notLnurls.filter {
            LnurlDetector.detect(it) is LnurlDetection.Lnurl
        }

        assertTrue("Wrongly detected as LNURLs: $wronglyAccepted", wronglyAccepted.isEmpty())
    }

    // --- What must still work ---------------------------------------------------

    @Test
    fun `accepts a valid bech32 lnurl and returns its decoded URL`() {
        val detection = LnurlDetector.detect(VALID_GETBITTR)

        assertEquals(
            LnurlDetection.Lnurl(
                decodedUrl = "https://getbittr.com/.well-known/lnurlp/tom",
                encoding = LnurlEncoding.Bech32,
            ),
            detection,
        )
    }

    @Test
    fun `accepts an uppercase lnurl, as printed on QR codes`() {
        // QR encoders use the uppercase alphanumeric mode because it is denser, so
        // scanned LNURLs routinely arrive uppercase.
        val detection = LnurlDetector.detect(VALID_PAY_EXAMPLE.uppercase())

        assertEquals(
            LnurlDetection.Lnurl(
                decodedUrl = "https://pay.example.com/lnurlp/abc",
                encoding = LnurlEncoding.Bech32,
            ),
            detection,
        )
    }

    @Test
    fun `strips a lightning prefix before parsing`() {
        assertEquals(
            LnurlDetection.Lnurl(
                decodedUrl = "https://getbittr.com/.well-known/lnurlp/tom",
                encoding = LnurlEncoding.Bech32,
            ),
            LnurlDetector.detect("lightning:$VALID_GETBITTR"),
        )
        assertEquals(
            "The scheme is matched case-insensitively — QR codes carry LIGHTNING:.",
            LnurlDetection.Lnurl(
                decodedUrl = "https://getbittr.com/.well-known/lnurlp/tom",
                encoding = LnurlEncoding.Bech32,
            ),
            LnurlDetector.detect("LIGHTNING:${VALID_GETBITTR.uppercase()}"),
        )
    }

    @Test
    fun `expands a lightning address to its well-known endpoint`() {
        assertEquals(
            LnurlDetection.Lnurl(
                decodedUrl = "https://getbittr.com/.well-known/lnurlp/tom",
                encoding = LnurlEncoding.LightningAddress,
            ),
            LnurlDetector.detect("tom@getbittr.com"),
        )
    }

    @Test
    fun `rejects address-shaped strings that are not lightning addresses`() {
        val notAddresses = listOf(
            "tom@",
            "@getbittr.com",
            "tom@getbittr",
            "tom@@getbittr.com",
            // A path or query after the domain would end up in the constructed
            // URL's host position.
            "tom@getbittr.com/evil",
            "tom@getbittr.com?x=1",
            "tom@127.0.0.1",
        )

        val wronglyAccepted = notAddresses.filter {
            LnurlDetector.detect(it) is LnurlDetection.Lnurl
        }

        assertTrue(
            "Wrongly expanded to well-known endpoints: $wronglyAccepted",
            wronglyAccepted.isEmpty(),
        )
    }

    @Test
    fun `accepts LUD-17 scheme URIs and rewrites them to https`() {
        assertEquals(
            LnurlDetection.Lnurl(
                decodedUrl = "https://pay.example.com/lnurlp/abc",
                encoding = LnurlEncoding.SchemeUri,
            ),
            LnurlDetector.detect("lnurlp://pay.example.com/lnurlp/abc"),
        )
    }
}
