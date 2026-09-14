package com.bittr.android.core.wallet.ldk.lightning

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The three classifications the transaction history filters on
 * (`Extensions/PaymentDetails.swift:13–35`), and the two ids a payment has.
 *
 * All five read as obvious. Three of them are not.
 */
class PaymentViewTest {

    @Test
    fun `only a succeeded payment has succeeded`() {
        assertTrue(payment(status = PaymentStatusView.Succeeded).hasSucceeded)
        assertFalse(payment(status = PaymentStatusView.Pending).hasSucceeded)
        assertFalse(payment(status = PaymentStatusView.Failed).hasSucceeded)
    }

    @Test
    fun `a pending outbound payment with an amount is pending outbound`() {
        assertTrue(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Outbound,
                amountMsat = 1_000uL,
            ).isPendingOutbound,
        )
    }

    /**
     * The clause that has nothing to do with direction and is easy to drop.
     *
     * ldk-node records an outbound payment before it prices it. Without the
     * amount test, the user's history gains a row reading "0 sats" for every
     * payment in flight.
     */
    @Test
    fun `a pending outbound payment with no amount and no fee is not listed`() {
        assertFalse(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Outbound,
                amountMsat = null,
                feePaidMsat = null,
            ).isPendingOutbound,
        )
    }

    /**
     * iOS divides to satoshis before comparing — `Int(amountMsat/1000) > 0` — so
     * sub-satoshi dust does not qualify. Porting it as `amountMsat > 0` would
     * resurrect exactly the rows the clause exists to hide.
     */
    @Test
    fun `sub-satoshi amounts do not make a payment listable`() {
        assertFalse(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Outbound,
                amountMsat = 999uL,
                feePaidMsat = 0uL,
            ).isPendingOutbound,
        )
        assertTrue(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Outbound,
                amountMsat = 1_000uL,
                feePaidMsat = 0uL,
            ).isPendingOutbound,
        )
    }

    @Test
    fun `a fee alone is enough to list a pending outbound payment`() {
        assertTrue(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Outbound,
                amountMsat = 0uL,
                feePaidMsat = 2_000uL,
            ).isPendingOutbound,
        )
    }

    @Test
    fun `an inbound pending payment is not pending outbound`() {
        assertFalse(
            payment(
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Inbound,
                amountMsat = 100_000uL,
            ).isPendingOutbound,
        )
    }

    @Test
    fun `an unconfirmed on-chain receive is all three of pending, on-chain and inbound`() {
        val unconfirmed = payment(
            kind = PaymentKindView.Onchain(txId = "tx"),
            status = PaymentStatusView.Pending,
            direction = PaymentDirectionView.Inbound,
        )
        assertTrue(unconfirmed.isUnconfirmedOnchainInbound)

        assertFalse(
            "A Lightning receive is not an on-chain one.",
            payment(
                kind = PaymentKindView.Bolt11("hash", "preimage"),
                status = PaymentStatusView.Pending,
                direction = PaymentDirectionView.Inbound,
            ).isUnconfirmedOnchainInbound,
        )
        assertFalse(
            "A confirmed receive is not unconfirmed.",
            unconfirmed.copy(status = PaymentStatusView.Succeeded).isUnconfirmedOnchainInbound,
        )
    }

    // ---- The two ids. ----

    /**
     * iOS's `transactionID` and `stableID` disagree on every kind except
     * on-chain, and the disagreement is the point: the preimage is null until a
     * payment settles, so a cache keyed on it misses on the one read that
     * mattered.
     */
    @Test
    fun `the stable id is the hash and the transaction id is the preimage`() {
        val bolt11 = PaymentKindView.Bolt11(hash = "the-hash", preimage = "the-preimage")

        assertEquals("the-hash", bolt11.stableId)
        assertEquals("the-preimage", bolt11.transactionId)
    }

    @Test
    fun `on-chain is the one kind where both ids are the txid`() {
        val onchain = PaymentKindView.Onchain(txId = "the-txid")

        assertEquals("the-txid", onchain.stableId)
        assertEquals("the-txid", onchain.transactionId)
        assertTrue(onchain.isOnchain)
        assertFalse(onchain.isBolt12)
    }

    @Test
    fun `an unsettled payment has a stable id but no transaction id`() {
        val unsettled = PaymentKindView.Bolt11(hash = "the-hash", preimage = null)

        assertEquals("the-hash", unsettled.stableId)
        assertNull(unsettled.transactionId)
        assertEquals(
            "So the cache key survives settlement.",
            "the-hash",
            payment(kind = unsettled).cacheId,
        )
    }

    /**
     * BOLT12 has no payment hash until the recipient returns an invoice —
     * ldk-node declares `PaymentKind.Bolt12Offer.hash` optional where
     * `Bolt11.hash` is not. So the cache key falls back to the payment id, which
     * is what iOS's `stableID ?? self.id` is for.
     */
    @Test
    fun `a bolt12 payment in flight falls back to the payment id`() {
        val inFlight = payment(
            id = "payment-id",
            kind = PaymentKindView.Bolt12(hash = null, preimage = null, isRefund = false),
        )

        assertNull(inFlight.kind.stableId)
        assertEquals("payment-id", inFlight.cacheId)
        assertTrue(inFlight.kind.isBolt12)
    }

    @Test
    fun `both bolt12 variants report as bolt12`() {
        assertTrue(PaymentKindView.Bolt12("h", "p", isRefund = false).isBolt12)
        assertTrue(PaymentKindView.Bolt12("h", "p", isRefund = true).isBolt12)
        assertFalse(PaymentKindView.Spontaneous("h", "p").isBolt12)
    }

    /**
     * The LSPS2 receive arrives as this kind, with the LSP's cut already taken
     * out of `amountMsat`. Keeping it distinct from [PaymentKindView.Bolt11] is
     * what lets a screen tell "invoiced N, received N" from "invoiced N, received
     * N minus the fee".
     */
    @Test
    fun `a just-in-time channel receive keeps the fee the LSP skimmed`() {
        val jit = PaymentKindView.Bolt11Jit(
            hash = "the-hash",
            preimage = "the-preimage",
            counterpartySkimmedFeeMsat = 2_500_000uL,
        )

        assertEquals(2_500_000uL, jit.counterpartySkimmedFeeMsat)
        assertEquals("the-hash", jit.stableId)
        assertEquals("the-preimage", jit.transactionId)
        assertFalse(jit.isOnchain)
    }
}
