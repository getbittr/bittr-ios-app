package com.bittr.android.core.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §4.2's reason table turned into behaviour, and §4.3's invariant held to the letter.
 *
 * The assertion that matters most in this file is a negative one: the set of responses on
 * which the app may offer the `onchain` downgrade is exactly `{missing, platform_mismatch}`
 * and nothing else. Every other `push_channel: "none"` is a token that *was* sent, and rev 4
 * rewrote the invariant around that word.
 */
class PushChannelPolicyTest {

    private fun decide(channel: String?, reason: String? = null) =
        PushChannelPolicy.decide(PushChannelStatus.from(channel, reason))

    @Test
    fun `fcm is a live route and shows nothing`() {
        val action = decide("fcm")

        assertEquals(PushChannelAction.Registered(PushChannel.FCM), action)
        assertEquals(PushChannelAction.Retry.NONE, action.retry)
        assertFalse(action.mayOfferOnchainDowngrade)
        assertFalse(PushChannelPolicy.showsRegistrationFailureCopy(action))
    }

    @Test
    fun `apns on an android registration is a dispatch bug, not a success`() {
        // §5 routes by `category`, and this client always sends "android". An APNS route means
        // every push goes to a device this customer does not have — silently. A caller that
        // only checks `channel != none` would call this registered.
        val action = decide("apns")

        assertEquals(PushChannelAction.RoutedToOtherPlatform, action)
        assertFalse(action.mayOfferOnchainDowngrade)
        assertTrue(PushChannelPolicy.showsRegistrationFailureCopy(action))
    }

    @Test
    fun `unavailable retries the same token and never offers the downgrade`() {
        // The whole reason §4.2 split this slug out. FCM 5xx says nothing about the token.
        val action = decide("none", "unavailable")

        assertEquals(PushChannelAction.Unavailable, action)
        assertEquals(PushChannelAction.Retry.SAME_TOKEN, action.retry)
        assertFalse(action.mayOfferOnchainDowngrade)
    }

    @Test
    fun `a dead token is replaced, not re-posted`() {
        // invalid / unregistered / unregistered_at_send all have a verdict, and the verdict is
        // that this token is dead. Re-posting it would spend the §2.3 budget on a call that
        // cannot succeed.
        for (slug in listOf("invalid", "unregistered", "unregistered_at_send")) {
            val action = decide("none", slug)

            assertTrue(slug, action is PushChannelAction.TokenRejected)
            assertEquals(slug, PushChannelAction.Retry.FRESH_TOKEN, action.retry)
            assertFalse(slug, action.mayOfferOnchainDowngrade)
        }
    }

    @Test
    fun `missing is the one ordinary path that may downgrade`() {
        // §2.1: a `category: "android"` signup with no token at all is accepted and normal,
        // because FCM retrieval is async and can miss the call. No token was sent, so §4.3
        // applies.
        val action = decide("none", "missing")

        assertEquals(PushChannelAction.NoTokenSent(PushChannelReason.MISSING), action)
        assertTrue(action.mayOfferOnchainDowngrade)
        assertEquals(PushChannelAction.Retry.FRESH_TOKEN, action.retry)
    }

    @Test
    fun `platform_mismatch downgrades and is our own defect`() {
        val action = decide("none", "platform_mismatch")

        assertEquals(PushChannelAction.NoTokenSent(PushChannelReason.PLATFORM_MISMATCH), action)
        assertTrue(action.mayOfferOnchainDowngrade)
    }

    @Test
    fun `the downgrade set is exactly missing and platform_mismatch`() {
        // The invariant, stated as a closed set rather than as six separate assertions — so
        // that a seventh slug added to PushChannelReason without a policy decision fails here
        // rather than silently inheriting a branch.
        val downgradable = PushChannelReason.entries
            .filter { decide("none", it.name.lowercase()).mayOfferOnchainDowngrade }
            .toSet()

        assertEquals(
            setOf(PushChannelReason.MISSING, PushChannelReason.PLATFORM_MISMATCH),
            downgradable,
        )
    }

    @Test
    fun `an unrecognised reason never downgrades and keeps the raw slug`() {
        // Forward compatibility failing safe: we cannot prove no token was sent, so we do not
        // act as though none was.
        val action = decide("none", "teapot")

        assertEquals(PushChannelAction.UnrecognisedReason("teapot"), action)
        assertFalse(action.mayOfferOnchainDowngrade)
        assertTrue(PushChannelPolicy.showsRegistrationFailureCopy(action))
    }

    @Test
    fun `none with no reason at all is handled rather than thrown`() {
        // The contract says this cannot happen. It is on the signup response path, so it is
        // still not allowed to take down registration.
        val action = decide("none", null)

        assertEquals(PushChannelAction.UnrecognisedReason(null), action)
        assertFalse(action.mayOfferOnchainDowngrade)
    }

    @Test
    fun `an unknown channel is a route we have, not a route we lack`() {
        // Collapsing this into `none` would downgrade a customer who has a working route.
        val action = decide("webpush")

        assertEquals(PushChannelAction.UnrecognisedChannel("webpush"), action)
        assertFalse(action.mayOfferOnchainDowngrade)
        assertEquals(PushChannelAction.Retry.NONE, action.retry)
    }

    @Test
    fun `an absent push_channel field does not downgrade`() {
        // The shipping-iOS-shaped response: a backend that predates §2.1's two new fields.
        val action = decide(null, null)

        assertEquals(PushChannelAction.UnrecognisedChannel(null), action)
        assertFalse(action.mayOfferOnchainDowngrade)
    }

    @Test
    fun `wire values are parsed case and whitespace tolerantly`() {
        assertEquals(PushChannel.FCM, PushChannel.parse(" FCM "))
        assertEquals(PushChannelReason.UNAVAILABLE, PushChannelReason.parse("Unavailable"))
        assertEquals(null, PushChannel.parse(""))
        assertEquals(null, PushChannelReason.parse(null))
    }

    @Test
    fun `failure copy is shown for every outcome except a live route`() {
        // §4.3's note that Android wires `tokenregistrationfail` at two points, the
        // response-time one being the one with no iOS equivalent.
        val live = decide("fcm")
        val everythingElse = listOf(
            decide("apns"),
            decide("none", "unavailable"),
            decide("none", "unregistered"),
            decide("none", "missing"),
            decide("none", "teapot"),
            decide("webpush"),
        )

        assertFalse(PushChannelPolicy.showsRegistrationFailureCopy(live))
        everythingElse.forEach { assertTrue(it.toString(), PushChannelPolicy.showsRegistrationFailureCopy(it)) }
    }
}
