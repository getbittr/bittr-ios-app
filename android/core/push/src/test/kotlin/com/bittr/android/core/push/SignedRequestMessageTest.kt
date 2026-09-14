package com.bittr.android.core.push

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §2.3's signed message, and its sibling in `BuyViewController.swift:337-362`.
 *
 * These are the exact bytes a signature covers, so the expectations here are written out in
 * full rather than assembled from the same parts the implementation uses — a test that builds
 * the string the same way the code does proves only that the code is self-consistent.
 */
class SignedRequestMessageTest {

    private val PUBKEY = "02a1b2c3"
    private val DEPOSIT = "BITTR-1234"

    @Test
    fun `the device-token message is prefix pubkey deposit token timestamp`() {
        assertEquals(
            "device_token:02a1b2c3:BITTR-1234:fcm-token-value:1757808000",
            SignedRequestMessage.deviceToken(PUBKEY, DEPOSIT, "fcm-token-value", 1_757_808_000L),
        )
    }

    @Test
    fun `the payment-mode message uses the same layout`() {
        // §2.3 copied this shape so Android writes one signer for both endpoints. If these two
        // ever stop matching field-for-field, that reason is gone.
        assertEquals(
            "payment_mode:02a1b2c3:BITTR-1234:onchain:1757808000",
            SignedRequestMessage.paymentMode(PUBKEY, DEPOSIT, "onchain", 1_757_808_000L),
        )
    }

    /**
     * The odd one out, and it has to stay odd. `GET /boltz/webhook-token` predates BIT-9 and the
     * shipping client signs it with three parts (`SwapManager.swift:85-95`); §2.4 leaves that
     * endpoint alone. Making it match the two five-part siblings above would be a contract change
     * to an endpoint nobody agreed to change, and the symptom would be a 401 on every swap.
     *
     * It lives here anyway, because the value of this object is that *every* string this app
     * signs is written in one tested place. Two functions that visibly disagree do not drift;
     * two files do.
     */
    @Test
    fun `the boltz webhook message has no deposit code and no value`() {
        assertEquals(
            "boltz_webhook:02a1b2c3:1757808000",
            SignedRequestMessage.boltzWebhook(PUBKEY, 1_757_808_000L),
        )
    }

    @Test
    fun `the token is embedded verbatim`() {
        // FCM tokens are ~150+ characters, are not fixed length, and carry ':' in the
        // instance-id half. Any trimming, truncation or normalisation here shows up as a
        // permanent false "stale token" at SwapManager.swift:77-80 rather than as a signing
        // bug — §2.3's column-width note is the backend half of the same requirement.
        val realistic = "cXy9_Ab-1234:APA91bH" + "x".repeat(140)

        val message = SignedRequestMessage.deviceToken(PUBKEY, DEPOSIT, realistic, 1L)

        assertEquals("device_token:$PUBKEY:$DEPOSIT:$realistic:1", message)
        assertEquals(realistic, message.removePrefix("device_token:$PUBKEY:$DEPOSIT:").removeSuffix(":1"))
    }
}
