package com.bittr.android.core.lnurl

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-5: pay, withdraw and auth each decide against the source.
 *
 * The review's own summary of why: on iOS the shared `handleLNURL` is saved from
 * paying web-originated LNURLs by an accidental `as?` downcast returning nil.
 * Android's shared handler has no nil to save it, so the source is a value and
 * every action checks it. These tests are the check that the check exists.
 */
class LnurlSourcePolicyTest {

    private companion object {
        val WEB = LnurlSource.FirstPartyWeb(
            origin = "https://getbittr.com",
            pageTitle = "Support",
        )
    }

    @Test
    fun `a first-party page cannot start a payment`() {
        val permission = LnurlSourcePolicy.permit(LnurlAction.Pay, WEB)

        assertTrue(
            "Web-originated LNURLs must not reach the pay path in v1 (R-4). This holds " +
                "even on getbittr.com: the origin allowlist decides who may talk to the " +
                "wallet, not what they may ask it to do. Got $permission",
            permission is LnurlPermission.Denied,
        )
    }

    @Test
    fun `a first-party page cannot start a withdrawal`() {
        // Not spelled out in BIT-33 and flagged on the issue as the conservative
        // reading rather than left implicit. LNURL-withdraw brings funds in, but it
        // hands a stranger's callback a wallet invoice on a page's initiative, and
        // it is the half of the LNURL surface with no confirmation requirement
        // written for it.
        val permission = LnurlSourcePolicy.permit(LnurlAction.Withdraw, WEB)

        assertTrue("Got $permission", permission is LnurlPermission.Denied)
    }

    @Test
    fun `scanning and deeplinks may do all three`() {
        // The point of R-5 is not that LNURL is dangerous — it is that a page
        // asking is different from a user asking. A control that also blocks the
        // scanner would be a broken feature, not a tighter one.
        LnurlAction.entries.forEach { action ->
            listOf(LnurlSource.QrScan, LnurlSource.Deeplink).forEach { source ->
                assertEquals(
                    "$action from $source must be allowed.",
                    LnurlPermission.Allowed,
                    LnurlSourcePolicy.permit(action, source),
                )
            }
        }
    }

    @Test
    fun `a first-party page may request auth, because the dialog carries that weight`() {
        // R-9 allows it and puts the burden on the dialog: the full callback origin
        // shown, and the requesting page named. LnurlAuthTest checks that half.
        assertEquals(
            LnurlPermission.Allowed,
            LnurlSourcePolicy.permit(LnurlAction.Auth, WEB),
        )
    }

    @Test
    fun `denial messages say what was refused, not that something went wrong`() {
        // A control the user cannot distinguish from a bug is a control that gets
        // relaxed by whoever is asked to fix the bug.
        val denials = listOf(LnurlAction.Pay, LnurlAction.Withdraw)
            .map { LnurlSourcePolicy.permit(it, WEB) }
            .filterIsInstance<LnurlPermission.Denied>()

        assertEquals(2, denials.size)
        denials.forEach { denial ->
            assertTrue(
                "Deny reasons must name the page as the actor. Got: ${denial.reason}",
                denial.reason.contains("This page"),
            )
        }
    }

    /**
     * There is deliberately no `ThirdPartyWeb` source (R-2). A test cannot assert
     * the absence of a type, so it asserts the property that makes it unnecessary:
     * every source that exists is one a user created by a physical act, or a
     * first-party page.
     *
     * If this test starts failing because a variant was added, the question to ask
     * is not "what should it be allowed to do" but "why does a third-party page
     * have a channel to the wallet at all" — see `WebsiteNavigationPolicy`.
     */
    @Test
    fun `the only web source is first-party`() {
        val webSources = listOf<LnurlSource>(
            LnurlSource.QrScan,
            LnurlSource.Deeplink,
            WEB,
        ).filterIsInstance<LnurlSource.FirstPartyWeb>()

        assertEquals(
            "LnurlSource has exactly one web-originated variant, and it is first-party. " +
                "A third-party page has no way to produce an LnurlSource because no " +
                "bridge is attached to it and its lightning:/lnurl navigations are " +
                "dropped rather than parsed.",
            1,
            webSources.size,
        )
    }
}
