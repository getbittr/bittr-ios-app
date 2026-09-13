package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.BalanceSourceView
import com.bittr.android.core.wallet.ldk.lightning.LightningBalanceView
import com.bittr.android.core.wallet.ldk.lightning.PaymentDirectionView
import com.bittr.android.core.wallet.ldk.lightning.PaymentKindView
import com.bittr.android.core.wallet.ldk.lightning.PaymentStatusView
import com.bittr.android.core.wallet.ldk.lightning.PendingSweepView
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.lightningdevkit.ldknode.BalanceDetails
import org.lightningdevkit.ldknode.BalanceSource
import org.lightningdevkit.ldknode.ChannelDetails
import org.lightningdevkit.ldknode.ConfirmationStatus
import org.lightningdevkit.ldknode.LightningBalance
import org.lightningdevkit.ldknode.ChannelConfig
import org.lightningdevkit.ldknode.LspFeeLimits
import org.lightningdevkit.ldknode.MaxDustHtlcExposure
import org.lightningdevkit.ldknode.OutPoint
import org.lightningdevkit.ldknode.PaymentDetails
import org.lightningdevkit.ldknode.PaymentDirection
import org.lightningdevkit.ldknode.PaymentKind
import org.lightningdevkit.ldknode.PaymentStatus
import org.lightningdevkit.ldknode.PeerDetails
import org.lightningdevkit.ldknode.PendingSweepBalance

/**
 * The record-to-view mapping, on the JVM.
 *
 * Same argument as `LdkNodeConfigTest`, and the same reason it is worth making:
 * `ChannelDetails`, `PaymentDetails`, `BalanceDetails` and the two balance
 * hierarchies are UniFFI-generated Kotlin data classes, and **nothing crosses
 * into Rust until a `Node` exists**. So the mapping is checkable here, which
 * matters because it is not the field-copy it looks like — `PaymentKind` and
 * `LightningBalance` have six branches each, and a transposed one silently gives
 * a payment the wrong id or a balance the wrong sign in the home-screen total.
 *
 * What this does not prove is that `node.listBalances()` returns what ldk-node
 * says it does. That needs a running node and belongs to BIT-123.
 */
class LdkNodeSurfaceTest {

    private companion object {
        val NODE_ID = "02" + "cd".repeat(32)
        const val CHANNEL_ID = "channel-1"
    }

    // ---- Channels. ----

    @Test
    fun `a channel maps to the six fields the balance arithmetic reads`() {
        val view = LdkNodeMapping.toView(
            channelDetails(
                channelId = CHANNEL_ID,
                userChannelId = "user-1",
                fundingTxo = OutPoint(txid = "funding-tx", vout = 2u),
                channelValueSats = 200_000uL,
                outboundCapacityMsat = 90_000_000uL,
                inboundCapacityMsat = 100_000_000uL,
                unspendablePunishmentReserve = 1_000uL,
                counterpartyUnspendablePunishmentReserve = 2_000uL,
                isChannelReady = true,
                isUsable = false,
            ),
        )

        assertEquals(CHANNEL_ID, view.channelId)
        assertEquals(
            "The id closeChannel takes, kept apart from the id balances are keyed by.",
            "user-1",
            view.userChannelId,
        )
        assertEquals(TxOutpoint(txId = "funding-tx", vout = 2u), view.fundingTxo)
        assertEquals(200_000uL, view.channelValueSats)
        assertEquals(90_000_000uL, view.outboundCapacityMsat)
        assertEquals(100_000_000uL, view.inboundCapacityMsat)
        assertEquals(1_000uL, view.unspendablePunishmentReserveSats)
        assertEquals(2_000uL, view.counterpartyUnspendablePunishmentReserveSats)
        assertTrue(view.isChannelReady)
        assertEquals(
            "isUsable is not isChannelReady. A ready channel with a disconnected peer " +
                "is not usable, and iOS selects on readiness alone.",
            false,
            view.isUsable,
        )
    }

    @Test
    fun `a channel without a funding output maps to a null outpoint, not a placeholder`() {
        val view = LdkNodeMapping.toView(channelDetails(fundingTxo = null))

        assertNull(view.fundingTxo)
    }

    // ---- Peers. ----

    @Test
    fun `a peer maps whole`() {
        val view = LdkNodeMapping.toView(
            PeerDetails(
                nodeId = NODE_ID,
                address = "lsp.example:9735",
                isPersisted = true,
                isConnected = false,
            ),
        )

        assertEquals(NODE_ID, view.nodeId)
        assertEquals("lsp.example:9735", view.address)
        assertTrue(view.isPersisted)
        assertEquals(false, view.isConnected)
    }

    // ---- Payment kinds: six branches, and the ids they disagree about. ----

    @Test
    fun `on-chain carries the txid as both ids`() {
        val view = LdkNodeMapping.toView(
            PaymentKind.Onchain(txid = "the-txid", status = ConfirmationStatus.Unconfirmed),
        )

        assertEquals(PaymentKindView.Onchain(txId = "the-txid"), view)
        assertEquals("the-txid", view.stableId)
        assertEquals("the-txid", view.transactionId)
        assertTrue(view.isOnchain)
    }

    @Test
    fun `bolt11 carries the hash as the stable id and the preimage as the transaction id`() {
        val view = LdkNodeMapping.toView(
            PaymentKind.Bolt11(hash = "the-hash", preimage = "the-preimage", secret = "secret"),
        )

        assertEquals("the-hash", view.stableId)
        assertEquals("the-preimage", view.transactionId)
        assertEquals(
            "The secret is not carried across. Nothing above this layer reads it, and " +
                "a payment secret in a view type is a payment secret in a log line.",
            PaymentKindView.Bolt11(hash = "the-hash", preimage = "the-preimage"),
            view,
        )
    }

    /**
     * The LSPS2 receive. The skimmed fee is the one field that makes this
     * distinguishable from a plain BOLT11 payment after the fact.
     */
    @Test
    fun `a just-in-time channel payment keeps the fee the LSP took`() {
        val view = LdkNodeMapping.toView(
            PaymentKind.Bolt11Jit(
                hash = "the-hash",
                preimage = null,
                secret = "secret",
                counterpartySkimmedFeeMsat = 2_500_000uL,
                lspFeeLimits = LspFeeLimits(maxTotalOpeningFeeMsat = null, maxProportionalOpeningFeePpmMsat = null),
            ),
        )

        assertEquals(
            PaymentKindView.Bolt11Jit(
                hash = "the-hash",
                preimage = null,
                counterpartySkimmedFeeMsat = 2_500_000uL,
            ),
            view,
        )
    }

    @Test
    fun `bolt12 offers and refunds both map to bolt12, and keep which one they were`() {
        val offer = LdkNodeMapping.toView(
            PaymentKind.Bolt12Offer(
                hash = "hash",
                preimage = "preimage",
                secret = "secret",
                offerId = "offer",
                payerNote = null,
                quantity = null,
            ),
        )
        val refund = LdkNodeMapping.toView(
            PaymentKind.Bolt12Refund(
                hash = "hash",
                preimage = "preimage",
                secret = "secret",
                payerNote = null,
                quantity = null,
            ),
        )

        assertEquals(PaymentKindView.Bolt12("hash", "preimage", isRefund = false), offer)
        assertEquals(PaymentKindView.Bolt12("hash", "preimage", isRefund = true), refund)
        assertTrue(offer.isBolt12 && refund.isBolt12)
    }

    /**
     * A BOLT12 payment starts from an offer, so upstream declares its hash
     * optional. The fallback to the payment id is iOS's `stableID ?? self.id`.
     */
    @Test
    fun `a bolt12 payment with no hash yet falls back to the payment id`() {
        val view = LdkNodeMapping.toView(
            paymentDetails(
                id = "payment-id",
                kind = PaymentKind.Bolt12Offer(
                    hash = null,
                    preimage = null,
                    secret = null,
                    offerId = "offer",
                    payerNote = null,
                    quantity = null,
                ),
            ),
        )

        assertNull(view.kind.stableId)
        assertEquals("payment-id", view.cacheId)
    }

    @Test
    fun `spontaneous carries the hash and preimage`() {
        assertEquals(
            PaymentKindView.Spontaneous(hash = "hash", preimage = "preimage"),
            LdkNodeMapping.toView(PaymentKind.Spontaneous(hash = "hash", preimage = "preimage")),
        )
    }

    // ---- Payment status and direction. ----

    @Test
    fun `every status and direction maps`() {
        assertEquals(
            listOf(PaymentStatusView.Pending, PaymentStatusView.Succeeded, PaymentStatusView.Failed),
            PaymentStatus.entries.map { LdkNodeMapping.toView(paymentDetails(status = it)).status },
        )
        assertEquals(
            listOf(PaymentDirectionView.Inbound, PaymentDirectionView.Outbound),
            PaymentDirection.entries
                .map { LdkNodeMapping.toView(paymentDetails(direction = it)).direction },
        )
    }

    // ---- Balances. ----

    @Test
    fun `every balance source maps, so the coop-close exclusion has something to match on`() {
        val views = BalanceSource.entries.map { source ->
            LdkNodeMapping.toView(
                LightningBalance.ClaimableAwaitingConfirmations(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 1uL,
                    confirmationHeight = 0u,
                    source = source,
                ),
            ) as LightningBalanceView.ClaimableAwaitingConfirmations
        }

        assertEquals(
            listOf(
                BalanceSourceView.HolderForceClosed,
                BalanceSourceView.CounterpartyForceClosed,
                BalanceSourceView.CoopClose,
                BalanceSourceView.Htlc,
            ),
            views.map { it.source },
        )
    }

    @Test
    fun `every lightning balance variant maps to its own view`() {
        assertEquals(
            LightningBalanceView.ClaimableOnChannelClose(CHANNEL_ID, 100uL),
            LdkNodeMapping.toView(
                LightningBalance.ClaimableOnChannelClose(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 100uL,
                    transactionFeeSatoshis = 0uL,
                    outboundPaymentHtlcRoundedMsat = 0uL,
                    outboundForwardedHtlcRoundedMsat = 0uL,
                    inboundClaimingHtlcRoundedMsat = 0uL,
                    inboundHtlcRoundedMsat = 0uL,
                ),
            ),
        )

        assertEquals(
            LightningBalanceView.ContentiousClaimable(CHANNEL_ID, 200uL),
            LdkNodeMapping.toView(
                LightningBalance.ContentiousClaimable(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 200uL,
                    timeoutHeight = 0u,
                    paymentHash = "hash",
                    paymentPreimage = "preimage",
                ),
            ),
        )

        assertEquals(
            LightningBalanceView.MaybeTimeoutClaimableHtlc(CHANNEL_ID, 300uL),
            LdkNodeMapping.toView(
                LightningBalance.MaybeTimeoutClaimableHtlc(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 300uL,
                    claimableHeight = 0u,
                    paymentHash = "hash",
                    outboundPayment = true,
                ),
            ),
        )

        assertEquals(
            LightningBalanceView.MaybePreimageClaimableHtlc(CHANNEL_ID, 400uL),
            LdkNodeMapping.toView(
                LightningBalance.MaybePreimageClaimableHtlc(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 400uL,
                    expiryHeight = 0u,
                    paymentHash = "hash",
                ),
            ),
        )

        assertEquals(
            LightningBalanceView.CounterpartyRevokedOutputClaimable(CHANNEL_ID, 500uL),
            LdkNodeMapping.toView(
                LightningBalance.CounterpartyRevokedOutputClaimable(
                    channelId = CHANNEL_ID,
                    counterpartyNodeId = NODE_ID,
                    amountSatoshis = 500uL,
                ),
            ),
        )
    }

    /**
     * The two sweep variants that carry a spending txid, and the one that does
     * not. `ClosureBalances` reads exactly this distinction.
     */
    @Test
    fun `every pending sweep variant maps, and only the broadcast ones carry a txid`() {
        assertEquals(
            PendingSweepView.PendingBroadcast(amountSatoshis = 10uL),
            LdkNodeMapping.toView(
                PendingSweepBalance.PendingBroadcast(
                    channelId = CHANNEL_ID,
                    amountSatoshis = 10uL,
                ),
            ),
        )

        assertEquals(
            PendingSweepView.BroadcastAwaitingConfirmation(
                amountSatoshis = 20uL,
                latestSpendingTxId = "sweep-a",
            ),
            LdkNodeMapping.toView(
                PendingSweepBalance.BroadcastAwaitingConfirmation(
                    channelId = CHANNEL_ID,
                    latestBroadcastHeight = 0u,
                    latestSpendingTxid = "sweep-a",
                    amountSatoshis = 20uL,
                ),
            ),
        )

        assertEquals(
            PendingSweepView.AwaitingThresholdConfirmations(
                amountSatoshis = 30uL,
                latestSpendingTxId = "sweep-b",
            ),
            LdkNodeMapping.toView(
                PendingSweepBalance.AwaitingThresholdConfirmations(
                    channelId = CHANNEL_ID,
                    latestSpendingTxid = "sweep-b",
                    confirmationHash = "hash",
                    confirmationHeight = 0u,
                    amountSatoshis = 30uL,
                ),
            ),
        )
    }

    /**
     * The four totals, kept in the right order.
     *
     * They are four `ULong`s in a row, which is the shape a transposition hides
     * in perfectly: swapping total and spendable compiles, and the only symptom
     * is a drain clamp that lets the anchor reserve leave the wallet.
     */
    @Test
    fun `the balance totals are not transposed`() {
        val view = LdkNodeMapping.toView(
            BalanceDetails(
                totalOnchainBalanceSats = 1uL,
                spendableOnchainBalanceSats = 2uL,
                totalAnchorChannelsReserveSats = 3uL,
                totalLightningBalanceSats = 4uL,
                lightningBalances = emptyList(),
                pendingBalancesFromChannelClosures = emptyList(),
            ),
        )

        assertEquals(1uL, view.totalOnchainBalanceSats)
        assertEquals(2uL, view.spendableOnchainBalanceSats)
        assertEquals(3uL, view.totalAnchorChannelsReserveSats)
        assertEquals(4uL, view.totalLightningBalanceSats)
    }

    // ---- Fixtures. ----

    private fun channelDetails(
        channelId: String = CHANNEL_ID,
        userChannelId: String = "user-1",
        fundingTxo: OutPoint? = null,
        channelValueSats: ULong = 0uL,
        outboundCapacityMsat: ULong = 0uL,
        inboundCapacityMsat: ULong = 0uL,
        unspendablePunishmentReserve: ULong? = null,
        counterpartyUnspendablePunishmentReserve: ULong = 0uL,
        isChannelReady: Boolean = true,
        isUsable: Boolean = true,
    ) = ChannelDetails(
        channelId = channelId,
        counterpartyNodeId = NODE_ID,
        fundingTxo = fundingTxo,
        shortChannelId = null,
        outboundScidAlias = null,
        inboundScidAlias = null,
        channelValueSats = channelValueSats,
        unspendablePunishmentReserve = unspendablePunishmentReserve,
        userChannelId = userChannelId,
        feerateSatPer1000Weight = 0u,
        outboundCapacityMsat = outboundCapacityMsat,
        inboundCapacityMsat = inboundCapacityMsat,
        confirmationsRequired = null,
        confirmations = null,
        isOutbound = false,
        isChannelReady = isChannelReady,
        isUsable = isUsable,
        isAnnounced = false,
        cltvExpiryDelta = null,
        counterpartyUnspendablePunishmentReserve = counterpartyUnspendablePunishmentReserve,
        counterpartyOutboundHtlcMinimumMsat = null,
        counterpartyOutboundHtlcMaximumMsat = null,
        counterpartyForwardingInfoFeeBaseMsat = null,
        counterpartyForwardingInfoFeeProportionalMillionths = null,
        counterpartyForwardingInfoCltvExpiryDelta = null,
        nextOutboundHtlcLimitMsat = 0uL,
        nextOutboundHtlcMinimumMsat = 0uL,
        forceCloseSpendDelay = null,
        inboundHtlcMinimumMsat = 0uL,
        inboundHtlcMaximumMsat = null,
        config = channelConfig(),
    )

    /**
     * `ChannelDetails.config` is not optional upstream, so it has to be supplied
     * even though nothing in [ChannelView] reads it.
     *
     * That is the mapping's point restated: `ChannelDetails` has thirty-odd
     * fields and the view carries eleven. Which ones were left behind is a
     * decision, and this fixture is where it shows.
     */
    private fun channelConfig() = ChannelConfig(
        forwardingFeeProportionalMillionths = 0u,
        forwardingFeeBaseMsat = 0u,
        cltvExpiryDelta = 0u,
        maxDustHtlcExposure = MaxDustHtlcExposure.FixedLimit(limitMsat = 0uL),
        forceCloseAvoidanceMaxFeeSatoshis = 0uL,
        acceptUnderpayingHtlcs = false,
    )

    private fun paymentDetails(
        id: String = "payment-1",
        kind: PaymentKind = PaymentKind.Bolt11(hash = "hash", preimage = "preimage", secret = null),
        status: PaymentStatus = PaymentStatus.SUCCEEDED,
        direction: PaymentDirection = PaymentDirection.INBOUND,
    ) = PaymentDetails(
        id = id,
        kind = kind,
        amountMsat = 1_000uL,
        feePaidMsat = 0uL,
        direction = direction,
        status = status,
        latestUpdateTimestamp = 0uL,
    )
}
