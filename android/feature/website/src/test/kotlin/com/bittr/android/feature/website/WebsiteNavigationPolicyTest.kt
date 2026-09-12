package com.bittr.android.feature.website

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-2 and the scheme half of R-11.
 *
 * The property that matters: **no trust level intercepts a Lightning
 * navigation.** R-2 requires it of third-party origins; v1 applies it to
 * first-party too, because there is no bridge for a `lightning:` URL to be handed
 * to. Every case here is therefore run against both [WebsiteTrust] values, which
 * is what keeps "first-party is special" from creeping back in as a special case.
 */
class WebsiteNavigationPolicyTest {

    private companion object {
        /** A real `lnurl1…`, so the drop cannot be attributed to a parse failure. */
        const val LNURL =
            "lnurl1dp68gurn8ghj7em9w33xjar5wghxxmmd9uh8wetvdskkkmn0wahz7mrww4excup0w3hk67r0vgs"
    }

    /**
     * Runs [assertion] for both trust levels **and both frames**, so no
     * combination of the two can behave differently (BIT-58).
     *
     * The frame dimension is swept everywhere rather than tested once, because
     * the failure it guards against is not "the subframe case is wrong" — it is
     * "somebody added a case that reads `trust` and forgot that a subframe
     * carries the main frame's."
     */
    private fun onBothTrustLevels(assertion: (WebsiteTrust) -> Unit) {
        WebsiteTrust.entries.forEach(assertion)
    }

    /** Both values of `isForMainFrame`, labelled for assertion messages. */
    private fun onBothFrames(assertion: (Boolean) -> Unit) {
        listOf(true, false).forEach(assertion)
    }

    @Test
    fun `lightning and lnurl navigations are dropped on every origin`() {
        val lightningUrls = listOf(
            "lightning:$LNURL",
            "LIGHTNING:${LNURL.uppercase()}",
            "lnurl:$LNURL",
            "lnurlp://pay.example.com/lnurlp/abc",
            "lnurlw://pay.example.com/withdraw/abc",
            "lnurlc://pay.example.com/channel/abc",
            "keyauth://getbittr.com/auth?tag=login",
        )

        onBothTrustLevels { trust ->
            onBothFrames { isForMainFrame ->
                lightningUrls.forEach { url ->
                    val decision = WebsiteNavigationPolicy.decide(url, trust, isForMainFrame)
                    assertTrue(
                        "$url must be cancelled and dropped at trust=$trust, " +
                            "isForMainFrame=$isForMainFrame (R-2). Got $decision",
                        decision is NavigationDecision.Drop,
                    )
                }
            }
        }
    }

    @Test
    fun `a dropped navigation produces no handler, only a drop`() {
        // NavigationDecision has two cases and Drop carries nothing but a log
        // string. There is deliberately no `HandleLnurl` case for a caller to
        // switch on — which is what makes "no LNURL navigation interception"
        // checkable rather than a claim about the current implementation.
        val decision = WebsiteNavigationPolicy.decide(
            "lightning:$LNURL",
            WebsiteTrust.FirstParty,
            isForMainFrame = true,
        )

        val reached = when (decision) {
            is NavigationDecision.Drop -> "drop"
            NavigationDecision.Load -> "load"
        }

        assertEquals("drop", reached)
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
                        "'$url' must be dropped at trust=$trust, " +
                            "isForMainFrame=$isForMainFrame. Got $decision",
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
                        "'$url' must load at trust=$trust, " +
                            "isForMainFrame=$isForMainFrame.",
                        NavigationDecision.Load,
                        WebsiteNavigationPolicy.decide(url, trust, isForMainFrame),
                    )
                }
            }
        }
    }

    @Test
    fun `a URL that merely contains lnurl still loads as an ordinary page`() {
        // The mirror image of R-6. iOS's substring match would route this into the
        // LNURL handler; here it is simply a web page, because that is what it is.
        assertEquals(
            NavigationDecision.Load,
            WebsiteNavigationPolicy.decide(
                "https://evil.example/?utm=lnurl&tag=login",
                WebsiteTrust.ThirdParty,
                isForMainFrame = true,
            ),
        )
    }

    @Test
    fun `trust does not change any outcome in v1`() {
        // Stated as its own test so that if a bridge ever ships and this starts
        // failing, the diff that caused it is the one being reviewed.
        val urls = listOf(
            "https://getbittr.com/support",
            "lightning:$LNURL",
            "intent://x#Intent;end",
            "mailto:support@getbittr.com",
            "",
        )

        urls.forEach { url ->
            val first = WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, true)
            val third = WebsiteNavigationPolicy.decide(url, WebsiteTrust.ThirdParty, true)

            assertEquals(
                "'$url' must be treated identically on both trust levels in v1.",
                first::class,
                third::class,
            )
        }
    }

    // --- BIT-58: the frame is part of the decision -------------------------------

    @Test
    fun `a subframe never inherits the main frame's first-party trust`() {
        // The heart of BIT-58. `view.url` is the main frame's URL, so a
        // cross-origin <iframe> on a getbittr.com page reaches the policy with
        // trust=FirstParty. It must not be judged as first-party.
        //
        // The Drop reason is the observable: in v1 no *outcome* varies by trust,
        // so asserting on the decision alone would pass even if the demotion were
        // deleted. Reading the reason is what makes this test fail for the right
        // change rather than for no change at all.
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
        assertTrue(
            "The decision must record which frame it was for, so a log line from a " +
                "cross-origin iframe is distinguishable from a top-level navigation. " +
                "Reason was: $reason",
            "subframe" in reason,
        )
    }

    @Test
    fun `a main-frame navigation keeps the trust it was given`() {
        // The other half: the demotion applies to subframes only. Without this,
        // "demote everything" would pass the test above and quietly make the
        // trust argument meaningless.
        val decision = WebsiteNavigationPolicy.decide(
            "lightning:$LNURL",
            WebsiteTrust.FirstParty,
            isForMainFrame = true,
        )

        val reason = (decision as NavigationDecision.Drop).reason

        assertTrue(
            "A main-frame navigation on a first-party page must be evaluated as " +
                "FirstParty. Reason was: $reason",
            "trust=${WebsiteTrust.FirstParty}" in reason && "main frame" in reason,
        )
    }

    @Test
    fun `an iframe may still load ordinary http and https documents`() {
        // Demoting a subframe's trust must not break embedding. A browser that
        // refuses to render an iframe is a regression, not a hardening measure —
        // and it is the failure mode a blunter "drop everything in a subframe"
        // fix would have introduced.
        val embeddable = listOf(
            "https://embed.example/widget",
            "https://www.youtube.com/embed/abc",
            "http://merchant.example/menu",
        )

        embeddable.forEach { url ->
            assertEquals(
                "'$url' must still load in a subframe — scoping the bridge to the main " +
                    "frame is not a reason to stop rendering iframes.",
                NavigationDecision.Load,
                WebsiteNavigationPolicy.decide(url, WebsiteTrust.FirstParty, false),
            )
        }
    }
}
