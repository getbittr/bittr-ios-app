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

/**
 * A [LightningNodePort] that answers [readWalletState] and refuses everything
 * else a snapshot could be assembled from.
 *
 * The refusal is the fixture's point rather than a convenience. [WalletNodeReading]
 * exists so the three lists describe one node at one moment, and the way that
 * guarantee is lost is a caller quietly going back to `listChannels()` +
 * `listBalances()` + `listPayments()` — which compiles, passes a value-equality
 * test, and reintroduces the half-read the type was added to prevent. Here those
 * three throw, so a test cannot pass that way.
 *
 * The writes are no-ops: nothing that reads a balance also opens a channel, and
 * a throwing write would only obscure which call a failing test made.
 */
internal class ReadingOnlyPort(private val reading: WalletNodeReading?) : LightningNodePort {

    /** How many times [readWalletState] was called. */
    var reads = 0
        private set

    override fun readWalletState(): WalletNodeReading? {
        reads += 1
        return reading
    }

    private fun forbidden(name: String): Nothing = throw AssertionError(
        "$name was called. The wallet must be taken through one readWalletState() so " +
            "the three lists describe one node at one moment — see WalletBalanceSnapshot.",
    )

    override fun listChannels(): List<ChannelView> = forbidden("listChannels")
    override fun listBalances(): BalanceView = forbidden("listBalances")
    override fun listPayments(): List<PaymentView> = forbidden("listPayments")
    override fun listPeers(): List<PeerView> = forbidden("listPeers")
    override fun payment(paymentId: String): PaymentView = forbidden("payment")

    override fun connect(nodeId: String, address: String, persist: Boolean) = Unit
    override fun disconnect(nodeId: String) = Unit

    override fun openChannel(
        nodeId: String,
        address: String,
        channelAmountSats: ULong,
        pushToCounterpartyMsat: ULong?,
    ): String = "user-channel-1"

    override fun closeChannel(userChannelId: String, counterpartyNodeId: String) = Unit

    override fun forceCloseChannel(
        userChannelId: String,
        counterpartyNodeId: String,
        reason: String,
    ) = Unit

    override fun updateChannelConfig(
        userChannelId: String,
        counterpartyNodeId: String,
        channelConfig: Any,
    ) = Unit

    override fun receiveBolt11(
        amountMsat: ULong,
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String = "invoice"

    override fun receiveBolt11VariableAmount(
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String = "variable-invoice"

    override fun syncWallets() = Unit

    override fun nodeId(): String? = null

    override fun signMessage(message: String): String = "signature"

    override fun sendBolt11(invoice: String, routeLimits: RouteLimitsView?): String = "hash"

    override fun sendBolt11UsingAmount(
        invoice: String,
        amountMsat: ULong,
        routeLimits: RouteLimitsView?,
    ): String = "hash"

    override fun sendBolt12UsingAmount(
        offer: String,
        amountMsat: ULong,
        routeLimits: RouteLimitsView,
    ): String = "payment-id"
}

/** One node reading, with each list defaulting to an empty wallet. */
internal fun reading(
    channels: List<ChannelView> = emptyList(),
    balances: BalanceView = balances(),
    payments: List<PaymentView> = emptyList(),
) = WalletNodeReading(channels = channels, balances = balances, payments = payments)

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
