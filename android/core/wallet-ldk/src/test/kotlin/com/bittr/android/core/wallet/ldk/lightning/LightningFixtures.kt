package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint

/**
 * Builders for the node views, so each test states only the fields it is about.
 *
 * [ChannelView] has eleven fields and every balance test cares about three or
 * four of them. Spelling out the other seven at each call site is how a test
 * stops saying what it is testing — and worse, how a default that *matters*
 * (`isChannelReady`) gets set to whatever made the last test pass.
 *
 * So the defaults here are deliberately boring and deliberately documented: a
 * ready, usable channel with no money in it. A test that cares about readiness
 * says so.
 */
internal fun channel(
    channelId: String = "channel-1",
    userChannelId: String = "user-channel-1",
    counterpartyNodeId: String = "02".padEnd(66, 'a'),
    fundingTxo: TxOutpoint? = null,
    channelValueSats: ULong = 0uL,
    outboundCapacityMsat: ULong = 0uL,
    inboundCapacityMsat: ULong = 0uL,
    unspendablePunishmentReserveSats: ULong? = null,
    counterpartyUnspendablePunishmentReserveSats: ULong = 0uL,
    isChannelReady: Boolean = true,
    isUsable: Boolean = true,
) = ChannelView(
    channelId = channelId,
    userChannelId = userChannelId,
    counterpartyNodeId = counterpartyNodeId,
    fundingTxo = fundingTxo,
    channelValueSats = channelValueSats,
    outboundCapacityMsat = outboundCapacityMsat,
    inboundCapacityMsat = inboundCapacityMsat,
    unspendablePunishmentReserveSats = unspendablePunishmentReserveSats,
    counterpartyUnspendablePunishmentReserveSats = counterpartyUnspendablePunishmentReserveSats,
    isChannelReady = isChannelReady,
    isUsable = isUsable,
)

/** An empty wallet: no channels closing, nothing on-chain. */
internal fun balances(
    totalOnchainBalanceSats: ULong = 0uL,
    spendableOnchainBalanceSats: ULong = 0uL,
    totalAnchorChannelsReserveSats: ULong = 0uL,
    totalLightningBalanceSats: ULong = 0uL,
    lightningBalances: List<LightningBalanceView> = emptyList(),
    pendingBalancesFromChannelClosures: List<PendingSweepView> = emptyList(),
) = BalanceView(
    totalOnchainBalanceSats = totalOnchainBalanceSats,
    spendableOnchainBalanceSats = spendableOnchainBalanceSats,
    totalAnchorChannelsReserveSats = totalAnchorChannelsReserveSats,
    totalLightningBalanceSats = totalLightningBalanceSats,
    lightningBalances = lightningBalances,
    pendingBalancesFromChannelClosures = pendingBalancesFromChannelClosures,
)

internal fun payment(
    id: String = "payment-1",
    kind: PaymentKindView = PaymentKindView.Bolt11(hash = "hash-1", preimage = "preimage-1"),
    amountMsat: ULong? = 1_000_000uL,
    feePaidMsat: ULong? = 0uL,
    direction: PaymentDirectionView = PaymentDirectionView.Inbound,
    status: PaymentStatusView = PaymentStatusView.Succeeded,
) = PaymentView(
    id = id,
    kind = kind,
    amountMsat = amountMsat,
    feePaidMsat = feePaidMsat,
    direction = direction,
    status = status,
)
