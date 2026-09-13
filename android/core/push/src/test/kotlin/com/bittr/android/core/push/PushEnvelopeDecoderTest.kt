package com.bittr.android.core.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-41 item 4 — the FCM envelope, against BIT-9 `api-contract` §3 and the BIT-30
 * sign-off's §2 decode rules.
 *
 * Payloads here are written the way the backend will emit them: one `data` key, whose value
 * is a JSON *string*. That is the whole point of §3.2 and the thing that cannot be tested by
 * reading the contract.
 */
class PushEnvelopeDecoderTest {

    // --- The payout path: BIT-9 DoD item 7, and the only type that moves money. ---

    @Test
    fun `a lightning payout decodes its id and converts its amount to msats`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "bittr_specific_data" to
                    """{"notification_id":"n-1","bitcoin_amount":"0.00012345"}""",
            ),
        )

        assertEquals(
            PushEnvelope.LightningPayout(notificationId = "n-1", amountMsats = 12_345_000L),
            envelope,
        )
    }

    @Test
    fun `a payout amount past Int MAX_VALUE survives`() {
        // 0.03 BTC is 3,000,000,000 msats. Decoded into an Int this is -1,294,967,296.
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("bittr_specific_data" to """{"bitcoin_amount":"0.03"}"""),
        ) as PushEnvelope.LightningPayout

        assertEquals(3_000_000_000L, envelope.amountMsats)
        assertTrue(envelope.amountMsats > Int.MAX_VALUE.toLong())
    }

    @Test
    fun `a payout with no amount is zero rather than a dropped message`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("bittr_specific_data" to """{"notification_id":"n-2"}"""),
        )

        assertEquals(
            PushEnvelope.LightningPayout(notificationId = "n-2", amountMsats = 0L),
            envelope,
        )
    }

    // --- The other four discriminators. ---

    @Test
    fun `an information notification decodes both texts`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("bittr_notification" to """{"header_text":"Hi","body_text":"There"}"""),
        )

        assertEquals(PushEnvelope.Information("Hi", "There"), envelope)
    }

    @Test
    fun `information copy is left null for the presentation layer to substitute`() {
        // iOS substitutes "oops" and a localised string at the decode site. Android keeps
        // copy in the string catalogue the BIT-12 guard polices, so the decoder reports
        // absence and does not invent words.
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("bittr_notification" to """{}"""),
        )

        assertEquals(PushEnvelope.Information(null, null), envelope)
    }

    @Test
    fun `a swap notification decodes id and status`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("swap_notification" to """{"swap_id":"s-9","status":"transaction.claimed"}"""),
        )

        assertEquals(PushEnvelope.Swap("s-9", "transaction.claimed"), envelope)
    }

    @Test
    fun `an expired htlc decodes its three fields`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "htlc_notification" to
                    """{"expired":true,"header_text":"Gone","body_text":"Too late","time_sent":"2026-09-13T00:00:00Z"}""",
            ),
        )

        assertEquals(
            PushEnvelope.HtlcExpired("Gone", "Too late", "2026-09-13T00:00:00Z"),
            envelope,
        )
    }

    @Test
    fun `expired defaults to false, so an unmarked htlc is incoming`() {
        // BIT-30 §2(c). All four of these are `as? Bool == true` false on iOS.
        val unmarked = """{"header_text":"Incoming"}"""
        val explicitlyFalse = """{"expired":false}"""
        val quoted = """{"expired":"true"}"""
        val wrongType = """{"expired":1}"""

        for (body in listOf(unmarked, explicitlyFalse, quoted, wrongType)) {
            assertEquals(
                "expired in $body should not have meant expired",
                PushEnvelope.HtlcIncoming,
                PushEnvelopeDecoder.decode(mapOf("htlc_notification" to body)),
            )
        }
    }

    @Test
    fun `a lightning address request decodes amount_msats as a Long`() {
        // BIT-30 §2(a): the field table says Int, which is 64-bit in Swift and 32-bit here.
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "lightning_address_notification" to
                    """{"amount_msats":5000000000,"metadata":"[[\"text/plain\",\"hi\"]]","time_sent":"2026-09-13T00:00:00Z","username":"ruben","endpoint":"https://bittr.nl/.well-known/lnurlp/ruben"}""",
            ),
        )

        assertEquals(
            PushEnvelope.LightningAddress(
                amountMsats = 5_000_000_000L,
                metadata = """[["text/plain","hi"]]""",
                timeSent = "2026-09-13T00:00:00Z",
                username = "ruben",
                endpoint = "https://bittr.nl/.well-known/lnurlp/ruben",
            ),
            envelope,
        )
    }

    @Test
    fun `the whole msat domain decodes`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("lightning_address_notification" to """{"amount_msats":2100000000000000000}"""),
        ) as PushEnvelope.LightningAddress

        assertEquals(2_100_000_000_000_000_000L, envelope.amountMsats)
    }

    // --- The tolerance BIT-30 §2(c) promised the backend. ---

    @Test
    fun `unknown fields are ignored, so the backend can add fields without a release`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "bittr_specific_data" to
                    """{"notification_id":"n-3","bitcoin_amount":"0.001","settled_at":"2026-09-13","fee_msats":120}""",
            ),
        )

        assertEquals(
            PushEnvelope.LightningPayout(notificationId = "n-3", amountMsats = 100_000_000L),
            envelope,
        )
    }

    @Test
    fun `a re-typed field reads as absent instead of failing the whole envelope`() {
        // The case @Serializable classes could not express: one field of the wrong type
        // would throw and drop the push. iOS's `as? String` / `as? Int` yield nil and carry
        // on, and Android has to behave the same or the two clients diverge the first time
        // the backend changes a type.
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "lightning_address_notification" to
                    """{"amount_msats":"5000","username":42,"metadata":{"nested":true},"endpoint":"https://bittr.nl"}""",
            ),
        )

        assertEquals(
            PushEnvelope.LightningAddress(
                amountMsats = null,
                metadata = null,
                timeSent = null,
                username = null,
                endpoint = "https://bittr.nl",
            ),
            envelope,
        )
    }

    @Test
    fun `a JSON null reads as absent`() {
        val envelope = PushEnvelopeDecoder.decode(
            mapOf("swap_notification" to """{"swap_id":null,"status":"pending"}"""),
        ) as PushEnvelope.Swap

        assertNull(envelope.swapId)
        assertEquals("pending", envelope.status)
    }

    // --- Ordering, reserved keys, and the three ways a payload is not actionable. ---

    @Test
    fun `the first discriminator in iOS's order wins`() {
        // A payload carrying two discriminators must resolve identically on both platforms.
        // iOS tests bittr_specific_data first (NotificationManager.swift:301).
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "swap_notification" to """{"swap_id":"s-1"}""",
                "bittr_specific_data" to """{"notification_id":"n-4","bitcoin_amount":"0.001"}""",
            ),
        )

        assertEquals(
            PushEnvelope.LightningPayout(notificationId = "n-4", amountMsats = 100_000_000L),
            envelope,
        )
    }

    @Test
    fun `FCM's own data keys do not look like a discriminator`() {
        // The reserved set BIT-30 §2 checked the five discriminators against.
        val envelope = PushEnvelopeDecoder.decode(
            mapOf(
                "from" to "597951034849",
                "message_type" to "data",
                "collapse_key" to "com.bittr.android.regtest",
                "google.delivered_priority" to "high",
            ),
        )

        assertEquals(PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NO_DISCRIMINATOR), envelope)
    }

    @Test
    fun `an empty data map is unknown, not an exception`() {
        assertEquals(
            PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NO_DISCRIMINATOR),
            PushEnvelopeDecoder.decode(emptyMap()),
        )
    }

    @Test
    fun `malformed JSON is dropped and named as malformed`() {
        val truncated = PushEnvelopeDecoder.decode(
            mapOf("htlc_notification" to """{"expired":tru"""),
        )
        assertEquals(PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.MALFORMED_JSON), truncated)

        val empty = PushEnvelopeDecoder.decode(mapOf("htlc_notification" to ""))
        assertEquals(PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.MALFORMED_JSON), empty)
    }

    @Test
    fun `a non-object payload is dropped and named separately`() {
        // The dispatcher-bug shape: an array, a bare scalar, or a double-encoded object.
        // Distinct from malformed JSON in the log because it points at a different fault.
        for (body in listOf("""["a","b"]""", "42", """"{\"expired\":true}"""")) {
            assertEquals(
                "$body should not have decoded",
                PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NOT_AN_OBJECT),
                PushEnvelopeDecoder.decode(mapOf("htlc_notification" to body)),
            )
        }
    }

    @Test
    fun `the discriminator list is the contract's five, in iOS's order`() {
        assertEquals(
            listOf(
                "bittr_specific_data",
                "bittr_notification",
                "swap_notification",
                "htlc_notification",
                "lightning_address_notification",
            ),
            PushEnvelopeDecoder.DISCRIMINATORS,
        )
    }
}
