package com.bittr.android.feature.website

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-3: the origin allowlist is exact, and the block explorer is not on it.
 *
 * ### The correction under test
 *
 * BIT-21's call-site table listed the block explorer as first-party. It is not:
 * `EnvironmentConfig.explorerURL` is `https://mempool.space` in Release and
 * `https://esplora-regtest.bittr.io` in Debug. That mistake reads as correct in
 * review — "the explorer" sounds like ours — so it is written down as a test
 * instead of as a comment.
 */
class FirstPartyOriginsTest {

    @Test
    fun `the block explorer is third-party`() {
        listOf(
            "https://mempool.space",
            "https://mempool.space/tx/abc123",
            "https://esplora-regtest.bittr.io/tx/abc123",
        ).forEach { url ->
            assertEquals(
                "$url is the block explorer. BIT-21 filed it as first-party; it is not, " +
                    "and a bridge attached to it would be a bridge attached to an origin " +
                    "we do not control.",
                WebsiteTrust.ThirdParty,
                FirstPartyOrigins.trustOf(url),
            )
        }
    }

    @Test
    fun `a getbittr_com page is first-party`() {
        listOf(
            "https://getbittr.com",
            "https://getbittr.com/",
            "https://getbittr.com/support",
            "https://getbittr.com/privacy-policy",
            "https://getbittr.com/terms-and-conditions",
            // The three URLs Settings actually loads, hardcoded at
            // ios/bittr/Settings/SettingsViewController.swift:75–82.
            "https://getbittr.com/support?lang=nl",
            "https://GetBittr.com/support",
            "https://getbittr.com:443/support",
        ).forEach { url ->
            assertEquals(url, WebsiteTrust.FirstParty, FirstPartyOrigins.trustOf(url))
        }
    }

    @Test
    fun `hosts that merely look like getbittr_com are third-party`() {
        listOf(
            // What endsWith("getbittr.com") would accept.
            "https://evil-getbittr.com/x",
            "https://notgetbittr.com/x",
            // What a naive contains() would accept.
            "https://getbittr.com.evil.example/x",
            "https://evil.example/getbittr.com",
            "https://evil.example/?ref=getbittr.com",
            // Credentials: reads first-party to a person, resolves to evil.example.
            "https://getbittr.com@evil.example/x",
            "https://getbittr.com:pass@evil.example/x",
            // A subdomain is not on the allowlist unless it is named there.
            "https://www.getbittr.com/x",
            "https://blog.getbittr.com/x",
            // An origin is scheme + host + port.
            "http://getbittr.com/support",
            "https://getbittr.com:8443/support",
            // Not a URL at all.
            "getbittr.com",
            "",
            "   ",
            "javascript:alert(1)",
            "file:///android_asset/x.html",
            "about:blank",
        ).forEach { url ->
            assertEquals(
                "'$url' must not be treated as first-party.",
                WebsiteTrust.ThirdParty,
                FirstPartyOrigins.trustOf(url),
            )
        }
    }

    @Test
    fun `a null url is third-party`() {
        // WebView.getUrl() is null before the first commit, so this is the state the
        // screen is genuinely in for a moment on every load. It must not be the
        // trusted one.
        assertEquals(WebsiteTrust.ThirdParty, FirstPartyOrigins.trustOf(null))
    }

    @Test
    fun `the origin rules a future bridge would use contain no wildcard`() {
        // R-3: never "*". Enforced again as a source-level check in :app's
        // WebViewBridgeOriginGuardTest, which also fails the build if an explorer
        // host appears in this file.
        assertEquals(setOf("https://getbittr.com"), FirstPartyOrigins.allowedOriginRules)

        assertTrue(
            "allowedOriginRules must be exact https origins — a wildcard makes the " +
                "origin argument decoration.",
            FirstPartyOrigins.allowedOriginRules.all {
                it.startsWith("https://") && '*' !in it
            },
        )
    }
}
