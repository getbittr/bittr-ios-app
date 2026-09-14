package com.bittr.android.core.wallet.ldk.adapter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.lightningdevkit.ldknode.ClosureReason
import org.lightningdevkit.ldknode.Event
import org.lightningdevkit.ldknode.PaymentFailureReason

/**
 * The ledger key, and the ldk-node rendering that would have quietly broken it.
 *
 * These run on the JVM with no device, for the reason `LdkNodeSurfaceTest` gives:
 * UniFFI generates plain Kotlin data classes for records and sealed hierarchies
 * for enums, so an `Event` can be constructed here. Only the *calls* cross into
 * Rust, and there are none in [LdkEventKey].
 */
class LdkEventKeyTest {

    /**
     * The bug this class exists for.
     *
     * `ClosureReason.CommitmentTxConfirmed` and nine of its siblings are
     * generated as Kotlin `object`s with no `toString` override, so
     * `Object.toString` renders them as `…ClosureReason$CommitmentTxConfirmed@1b6d3586`
     * — an identity hash, freshly assigned in every process. A ledger keyed on
     * that can never suppress a replayed channel closure, which is the event most
     * likely to be replayed: it arrives while the app is not running and sits in
     * ldk-node's queue until it is.
     */
    @Test
    fun `a channel closure renders without a per-process identity hash`() {
        val closed = Event.ChannelClosed(
            channelId = "channel-id",
            userChannelId = "user-channel-id",
            counterpartyNodeId = "counterparty",
            reason = ClosureReason.CommitmentTxConfirmed,
        )

        val key = LdkEventKey.of(closed)

        assertFalse(
            "The raw rendering contains an identity hash and this one must not: '$key'. " +
                "Two processes would key the same closure differently and the ledger " +
                "would suppress nothing.",
            key.contains('@'),
        )
        assertTrue("The reason must still be in the key: '$key'", key.contains("CommitmentTxConfirmed"))
    }

    @Test
    fun `two closures that differ only in their reason keep different keys`() {
        fun closed(reason: ClosureReason) = LdkEventKey.of(
            Event.ChannelClosed(
                channelId = "channel-id",
                userChannelId = "user-channel-id",
                counterpartyNodeId = "counterparty",
                reason = reason,
            ),
        )

        assertNotEquals(
            "Flattening the reason to a name must not flatten two reasons to the same " +
                "name, or one closure would suppress the notification for another.",
            closed(ClosureReason.CommitmentTxConfirmed),
            closed(ClosureReason.DisconnectedPeer),
        )
    }

    /**
     * The normalisation must leave the structural renderings alone: those are
     * already stable, and rewriting them would be a second thing to get wrong.
     */
    @Test
    fun `a structurally-rendered event keys as its own description`() {
        val failed = Event.PaymentFailed(
            paymentId = "payment-id",
            paymentHash = "payment-hash",
            reason = PaymentFailureReason.RETRIES_EXHAUSTED,
        )

        assertEquals(failed.toString(), LdkEventKey.of(failed))
    }

    @Test
    fun `the same event renders the same key twice`() {
        fun received() = Event.PaymentReceived(
            paymentId = "payment-id",
            paymentHash = "payment-hash",
            amountMsat = 1_000uL,
            customRecords = emptyList(),
        )

        assertEquals(
            "Two deliveries of one payment are two objects. If they keyed differently " +
                "the ledger would never match anything.",
            LdkEventKey.of(received()),
            LdkEventKey.of(received()),
        )
    }

    @Test
    fun `only a payment failure is exempt from deduplication`() {
        assertTrue(
            LdkEventKey.isPaymentFailed(
                Event.PaymentFailed(
                    paymentId = "payment-id",
                    paymentHash = "payment-hash",
                    reason = PaymentFailureReason.RETRIES_EXHAUSTED,
                ),
            ),
        )
        assertFalse(
            LdkEventKey.isPaymentFailed(
                Event.PaymentSuccessful(
                    paymentId = "payment-id",
                    paymentHash = "payment-hash",
                    paymentPreimage = "preimage",
                    feePaidMsat = 1uL,
                ),
            ),
        )
    }

    /**
     * What leaves the module is the variant name, because the full rendering of
     * a successful payment contains the preimage — the one field in an event
     * that is a secret rather than an identifier, and the proof of payment.
     */
    @Test
    fun `the summary names the event and carries none of its contents`() {
        val successful = Event.PaymentSuccessful(
            paymentId = "payment-id",
            paymentHash = "payment-hash",
            paymentPreimage = "the-preimage",
            feePaidMsat = 1uL,
        )

        val summary = LdkEventKey.summary(successful)

        assertEquals("PaymentSuccessful", summary)
        assertFalse(
            "A preimage in a log line is a proof of payment in a log line.",
            summary.contains("the-preimage"),
        )
        assertTrue(
            "The ledger, which is a file under no_backup, is where the full rendering " +
                "is allowed to go.",
            LdkEventKey.of(successful).contains("the-preimage"),
        )
    }
}
