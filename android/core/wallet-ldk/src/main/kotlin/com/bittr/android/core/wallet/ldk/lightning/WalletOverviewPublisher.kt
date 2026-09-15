package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ChannelSummary
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Home's [WalletOverview], published from each node reading — the UI half of
 * `updateTransactionHistory()` and `finalizeSync()` (`LoadWalletData.swift:82–149`, `:520`).
 *
 * [WalletBalanceReader] calls [publish] after every successful reading. The first one is
 * `finalizeSync()`: it flips [WalletOverview.hasSynced], which is what opens Send, Receive
 * and the balance card on Home and stops `home.headerSpinner`. A build with no node never
 * reads, so it never syncs — which is the truth about it.
 *
 * ## What is not here yet, said plainly
 *
 * iOS also merges bittr purchases (from the bittr API), cached Lightning payments and swap
 * pairs into the history, and dates a Lightning payment by the timestamp it cached when the
 * invoice was made. None of those caches exist on Android yet, so a Lightning row is dated
 * by `latestUpdateTimestamp` and there are no bittr or swap rows. The balances are complete.
 */
class WalletOverviewPublisher(
    private val hasNode: Boolean,
    /** `CacheManager.channelClosureTxIDs` as of this reading — see [WalletOverview.channelClosureTxIds]. */
    private val closureTxIds: () -> Collection<String> = { emptyList() },
) : WalletOverviewSource {

    private val _overview = MutableStateFlow(WalletOverview(hasNode = hasNode))
    override val overview: StateFlow<WalletOverview> = _overview.asStateFlow()

    fun publish(reading: WalletNodeReading, snapshot: WalletBalanceSnapshot) {
        _overview.value = WalletOverview(
            hasNode = hasNode,
            hasSynced = true,
            satoshisOnchain = snapshot.satoshisOnchain,
            satoshisLightning = snapshot.satoshisLightning,
            pendingClosureSatoshis = snapshot.pendingClosureSatoshis,
            transactions = activity(reading.payments),
            currentHeight = reading.bestBlockHeight,
            satoshisOnchainSpendable = snapshot.satoshisOnchainSpendable,
            lightningSendableSats = ((reading.channels.activeChannel()?.outboundCapacityMsat ?: 0uL) / 1000uL).toLong(),
            channelCount = reading.channels.size,
            activeChannel = reading.channels.activeChannel()?.let { channel ->
                ChannelSummary(
                    valueSats = channel.channelValueSats.toLong(),
                    outboundSats = (channel.outboundCapacityMsat / 1000uL).toLong(),
                    reserveSats = (channel.unspendablePunishmentReserveSats ?: 0uL).toLong(),
                )
            },
            channelClosureTxIds = runCatching { closureTxIds().toSet() }.getOrDefault(emptySet()),
        )
    }

    companion object {

        /**
         * The rows iOS shows: succeeded payments, outbound ones still pending, and
         * unconfirmed on-chain receives — newest first.
         */
        fun activity(payments: List<PaymentView>): List<WalletActivity> = payments
            .filter { it.hasSucceeded || it.isPendingOutbound || it.isUnconfirmedOnchainInbound }
            .map(::row)
            .sortedByDescending { it.timestampSecs }

        /** `PaymentDetails.createTransaction(bittrTransactions:)`, minus the bittr half. */
        private fun row(payment: PaymentView): WalletActivity {
            val kind = payment.kind
            val confirmed = (kind as? PaymentKindView.Onchain)?.confirmation as? OnchainConfirmationView.Confirmed
            val amountSats = ((payment.amountMsat ?: 0uL) / 1000uL).toLong()
            val inbound = payment.direction == PaymentDirectionView.Inbound
            return WalletActivity(
                id = kind.transactionId ?: payment.id,
                receivedSats = if (inbound) amountSats else 0L,
                sentSats = if (inbound) 0L else amountSats,
                feeSats = if (inbound) 0L else ((payment.feePaidMsat ?: 0uL) / 1000uL).toLong(),
                timestampSecs = confirmed?.timestampSecs ?: payment.latestUpdateTimestampSecs,
                isLightning = !kind.isOnchain,
                confirmationHeight = confirmed?.height,
                // What Receive and swaps key descriptions by: the id is the preimage once known.
                paymentHash = when (kind) {
                    is PaymentKindView.Bolt11Like -> kind.hash
                    is PaymentKindView.Bolt12 -> kind.hash
                    is PaymentKindView.Spontaneous -> kind.hash
                    is PaymentKindView.Onchain -> null
                },
            )
        }
    }
}
