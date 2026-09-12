package com.bittr.android.core.lnurl

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-9 and the `tag=login` half of §Acceptance 5.
 *
 * `WebsiteViewController.decidePolicyFor` enters the LNURL-auth path on
 * `absolute.contains("tag=login")` — on every page the in-app browser has loaded.
 * The wallet's identity key signs the challenge that path produces, so the bar
 * for entering it is a full parse and nothing less.
 */
class LnurlAuthTest {

    private companion object {
        const val K1 = "abababababababababababababababababababababababababababababababab"
        const val VALID = "https://getbittr.com/auth?tag=login&k1=$K1"
    }

    @Test
    fun `a URL that merely contains tag=login is not an auth request`() {
        assertNull(
            "iOS's contains(\"tag=login\") check accepts this and signs a challenge for it.",
            LnurlAuth.parse("https://evil.example/x?tag=login"),
        )
    }

    @Test
    fun `auth requires a well-formed 32-byte k1`() {
        val notAuth = listOf(
            // No k1 at all.
            "https://getbittr.com/auth?tag=login",
            // Too short, too long, not hex.
            "https://getbittr.com/auth?tag=login&k1=abcd",
            "https://getbittr.com/auth?tag=login&k1=${K1}ab",
            "https://getbittr.com/auth?tag=login&k1=${K1.dropLast(2)}zz",
            // tag= something else.
            "https://getbittr.com/auth?tag=payRequest&k1=$K1",
            // In the path or the fragment rather than the query.
            "https://getbittr.com/tag=login/k1=$K1",
            "https://getbittr.com/auth#tag=login&k1=$K1",
            // R-7 still applies: an auth callback on a private address is refused
            // before it is even recognised as auth.
            "https://127.0.0.1/auth?tag=login&k1=$K1",
            "http://getbittr.com/auth?tag=login&k1=$K1",
        )

        val wronglyParsed = notAuth.filter { LnurlAuth.parse(it) != null }

        assertTrue("Wrongly parsed as auth requests: $wronglyParsed", wronglyParsed.isEmpty())
    }

    @Test
    fun `a well-formed auth request parses`() {
        val request = LnurlAuth.parse("$VALID&action=login")

        assertNotNull(request)
        assertEquals(K1, request?.k1Hex)
        assertEquals("login", request?.action)
    }

    @Test
    fun `the prompt shows the full callback origin and names the requesting page`() {
        // R-9, both halves. The origin is shown so the user can see who receives
        // the signature; the page is named so "the app is asking" and "a page in
        // the app is asking" are distinguishable.
        val request = requireNotNull(LnurlAuth.parse(VALID))

        val prompt = LnurlAuth.prompt(
            request,
            LnurlSource.FirstPartyWeb(origin = "https://getbittr.com", pageTitle = "Support"),
        ) as LnurlAuthPrompt.Confirm

        assertEquals("https://getbittr.com", prompt.callbackOrigin)
        assertEquals(
            RequestingPage(origin = "https://getbittr.com", title = "Support"),
            prompt.requestingPage,
        )
    }

    @Test
    fun `the origin shown is the callback's, not the requesting page's`() {
        // The page asking and the server receiving the signature need not be the
        // same, and the one that matters is the recipient. A dialog that showed the
        // page's own origin would read as first-party for a cross-origin callback.
        val request = requireNotNull(
            LnurlAuth.parse("https://auth.elsewhere.example/a?tag=login&k1=$K1"),
        )

        val prompt = LnurlAuth.prompt(
            request,
            LnurlSource.FirstPartyWeb(origin = "https://getbittr.com", pageTitle = "Support"),
        ) as LnurlAuthPrompt.Confirm

        assertEquals("https://auth.elsewhere.example", prompt.callbackOrigin)
        assertEquals("https://getbittr.com", prompt.requestingPage?.origin)
    }

    @Test
    fun `a scanned auth request has no requesting page`() {
        val request = requireNotNull(LnurlAuth.parse(VALID))

        val prompt = LnurlAuth.prompt(request, LnurlSource.QrScan) as LnurlAuthPrompt.Confirm

        assertNull(
            "There is no page to name for a QR scan, and inventing one would make the " +
                "dialog's most load-bearing field untrustworthy.",
            prompt.requestingPage,
        )
    }

    @Test
    fun `there is no path to signing that skips the prompt`() {
        // LnurlAuthPrompt has exactly two cases and neither is "proceed". Asserted
        // as an exhaustive `when` so that adding a third case fails to compile
        // here rather than quietly becoming reachable.
        val request = requireNotNull(LnurlAuth.parse(VALID))

        val reached = when (LnurlAuth.prompt(request, LnurlSource.Deeplink)) {
            is LnurlAuthPrompt.Confirm -> "confirm"
            is LnurlAuthPrompt.Blocked -> "blocked"
        }

        assertEquals("confirm", reached)
    }
}
