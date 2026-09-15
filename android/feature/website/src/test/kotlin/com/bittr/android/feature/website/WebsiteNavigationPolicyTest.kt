package com.bittr.android.feature.website

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-2, the scheme half of R-11, and the port of `decidePolicyFor`'s LNURL gate.
 *
 * The property that matters: **only the main frame of a first-party page can hand a
 * Lightning link to the wallet.** Every other trust level and every subframe gets the
 * navigation cancelled and nothing else.
 */
class WebsiteNavigationPolicyTest {

    private companion object {
        /** A real `lnurl1…`, so a decision cannot be attributed to a parse failure. */
        const val LNURL =
            "lnurl1dp68gurn8ghj7em9w33xjar5wghxxmmd9uh8wetvdskkkmn0wahz7mrww4excup0w3hk67r0vgs"

        const val LOGIN_CALLBACK = "https://getbittr.com/lnurl/auth?tag=login&k1=AbCdEf0123&action=Login"

        val LNURL_NAVIGATIONS = listOf(
            "lightning:$LNURL",
            "LIGHTNING:${LNURL.uppercase()}",
            "lnurl:$LNURL",
            LNURL,
            LOGIN_CALLBACK,
        )
    }

    /** Runs [assertion] for both trust levels. */
    private fun onBothTrustLevels(assertion: (WebsiteTrust) -> Unit) {
        WebsiteTrust.entries.forEach(assertion)
    }

    /** Both values of `isForMainFrame`. */
    private fun onBothFrames(assertion: (Boolean) -> Unit) {
        listOf(true, false).forEach(assertion)
    }

    @Test
    fun `a first-party page's main frame hands Lightning links to the wallet`() {
        LNURL_NAVIGATIONS.forEach { url ->
            val decision = WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, isForMainFrame = true)
            assertTrue("$url must be handed to the wallet. Got $decision", decision is NavigationDecision.HandleLnurl)
        }
    }

    @Test
    fun `third-party pages and subframes never start a Lightning flow`() {
        LNURL_NAVIGATIONS.forEach { url ->
            listOf(
                WebsiteTrust.ThirdParty to true,
                WebsiteTrust.ThirdParty to false,
                WebsiteTrust.FirstParty to false,
            ).forEach { (trust, isForMainFrame) ->
                val decision = WebsiteNavigationPolicy.decide(url, trust, isForMainFrame)
                assertTrue(
                    "$url must be cancelled and dropped at trust=$trust, isForMainFrame=$isForMainFrame. Got $decision",
                    decision is NavigationDecision.Drop,
                )
            }
        }
    }

    @Test
    fun `the code handed on is iOS's lnurlCode`() {
        fun code(url: String) =
            (WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, isForMainFrame = true) as NavigationDecision.HandleLnurl).code

        assertEquals(LNURL, code("lightning:$LNURL"))
        // Bech32 must be uniform, so an all-uppercase LNURL is lowercased.
        assertEquals(LNURL, code("LIGHTNING:${LNURL.uppercase()}"))
        assertEquals(LNURL, code(LNURL.uppercase()))
        // An https login callback is case-sensitive: passed through untouched.
        assertEquals(LOGIN_CALLBACK, code(LOGIN_CALLBACK))
        assertEquals(LOGIN_CALLBACK, code("lightning:$LOGIN_CALLBACK"))
        // Only `lightning:` is stripped, as on iOS.
        assertEquals("lnurl:$LNURL", code("lnurl:$LNURL"))
    }

    @Test
    fun `other Lightning schemes are dropped on every origin`() {
        val dropped = listOf(
            "lnurlp://pay.example.com/lnurlp/abc",
            "lnurlw://pay.example.com/withdraw/abc",
            "lnurlc://pay.example.com/channel/abc",
            "keyauth://getbittr.com/auth?tag=login",
        )

        onBothTrustLevels { trust ->
            onBothFrames { isForMainFrame ->
                dropped.forEach { url ->
                    val decision = WebsiteNavigationPolicy.decide(url, trust, isForMainFrame)
                    assertTrue(
                        "$url must be dropped at trust=$trust, isForMainFrame=$isForMainFrame. Got $decision",
                        decision is NavigationDecision.Drop,
                    )
                }
            }
        }
    }

    @Test
    fun `intent, file, content and unknown schemes are dropped on every origin`() {
        val blocked = listOf(
            // R-11 names these three. intent:// in particular is a general
            // "start any Activity with these extras" encoding.
            "intent://scan/#Intent;scheme=zxing;package=com.google.zxing;end",
            "intent:#Intent;action=android.intent.action.CALL;end",
            "file:///android_asset/index.html",
            "file:///data/data/com.bittr.android/databases/wallet.db",
            "content://com.android.contacts/contacts/1",
            // The long tail an allowlist covers and a denylist does not.
            "market://details?id=com.example",
            "whatsapp://send?text=hi",
            "javascript:alert(document.cookie)",
            "data:text/html;base64,PHNjcmlwdD4=",
            "about:blank",
            "blob:https://evil.example/uuid",
            "tel:+31612345678",
            "mailto:support@getbittr.com",
            "sms:+31612345678",
            // Not a scheme at all.
            "",
            "   ",
            "//evil.example/x",
            "1http://evil.example/x",
        )

        onBothTrustLevels { trust ->
            onBothFrames { isForMainFrame ->
                blocked.forEach { url ->
                    val decision = WebsiteNavigationPolicy.decide(url, trust, isForMainFrame)
                    assertTrue(
                        "'$url' must be dropped at trust=$trust, isForMainFrame=$isForMainFrame. Got $decision",
                        decision is NavigationDecision.Drop,
                    )
                }
            }
        }
    }

    @Test
    fun `http and https navigations load on every origin`() {
        // A browser that refuses to browse is not a hardened browser. The explorer
        // and the map's merchant sites are third-party and are still meant to work.
        val loadable = listOf(
            "https://getbittr.com/support",
            "https://mempool.space/tx/abc123",
            "https://merchant.example/menu",
            "http://merchant.example/menu",
            "https://merchant.example/menu?utm=lnurl",
        )

        onBothTrustLevels { trust ->
            onBothFrames { isForMainFrame ->
                loadable.forEach { url ->
                    assertEquals(
                        "'$url' must load at trust=$trust, isForMainFrame=$isForMainFrame.",
                        NavigationDecision.Load,
                        WebsiteNavigationPolicy.decide(url, trust, isForMainFrame),
                    )
                }
            }
        }
    }

    @Test
    fun `a URL that merely contains lnurl or tag=login text still loads as an ordinary page`() {
        // The mirror image of R-6: only a parsed `tag=login` query item makes a login attempt.
        listOf(
            "https://evil.example/?utm=lnurl",
            "https://evil.example/tag=login",
            "https://evil.example/?utm=tag%3Dlogin",
        ).forEach { url ->
            assertEquals(url, NavigationDecision.Load, WebsiteNavigationPolicy.decide(url, WebsiteTrust.ThirdParty, isForMainFrame = true))
        }
    }

    @Test
    fun `a tag=login link on a third-party page is cancelled, as iOS cancels it`() {
        val decision = WebsiteNavigationPolicy.decide(
            "https://evil.example/?utm=x&TAG=Login&k1=abc",
            WebsiteTrust.ThirdParty,
            isForMainFrame = true,
        )
        assertTrue("Got $decision", decision is NavigationDecision.Drop)
    }

    @Test
    fun `trust changes the outcome of Lightning navigations and nothing else`() {
        val unaffected = listOf(
            "https://getbittr.com/support",
            "intent://x#Intent;end",
            "mailto:support@getbittr.com",
            "lnurlp://pay.example.com/lnurlp/abc",
            "",
        )

        unaffected.forEach { url ->
            val first = WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, true)
            val third = WebsiteNavigationPolicy.decide(url, WebsiteTrust.ThirdParty, true)
            assertEquals("'$url' must be treated identically on both trust levels.", first::class, third::class)
        }
    }

    // --- BIT-58: the frame is part of the decision -------------------------------

    @Test
    fun `a subframe never inherits the main frame's first-party trust`() {
        // `view.url` is the main frame's URL, so a cross-origin <iframe> on a
        // getbittr.com page reaches the policy with trust=FirstParty. It must not be
        // judged as first-party — or it could navigate itself to `lightning:` and be
        // handed to the wallet.
        val decision = WebsiteNavigationPolicy.decide(
            "lightning:$LNURL",
            WebsiteTrust.FirstParty,
            isForMainFrame = false,
        )

        val reason = (decision as NavigationDecision.Drop).reason

        assertTrue(
            "A subframe navigation must be evaluated as ThirdParty even when the main " +
                "frame is first-party (BIT-58). The reason recorded was: $reason",
            "trust=${WebsiteTrust.ThirdParty}" in reason,
        )
        assertTrue("The decision must record which frame it was for. Reason was: $reason", "subframe" in reason)
    }

    @Test
    fun `a main-frame navigation keeps the trust it was given`() {
        // The other half: the demotion applies to subframes only. Without this,
        // "demote everything" would pass the test above and quietly make first-party
        // Lightning links unreachable.
        assertTrue(
            WebsiteNavigationPolicy.decide("lightning:$LNURL", WebsiteTrust.FirstParty, isForMainFrame = true)
                is NavigationDecision.HandleLnurl,
        )
        val reason = (
            WebsiteNavigationPolicy.decide("lightning:$LNURL", WebsiteTrust.ThirdParty, isForMainFrame = true)
                as NavigationDecision.Drop
            ).reason
        assertTrue("Reason was: $reason", "trust=${WebsiteTrust.ThirdParty}" in reason && "main frame" in reason)
    }

    @Test
    fun `an iframe may still load ordinary http and https documents`() {
        // Demoting a subframe's trust must not break embedding.
        val embeddable = listOf(
            "https://embed.example/widget",
            "https://www.youtube.com/embed/abc",
            "http://merchant.example/menu",
        )

        embeddable.forEach { url ->
            assertEquals(
                "'$url' must still load in a subframe.",
                NavigationDecision.Load,
                WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, false),
            )
        }
    }
}
