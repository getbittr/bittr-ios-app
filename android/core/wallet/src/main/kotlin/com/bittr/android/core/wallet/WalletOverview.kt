package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.StateFlow

/**
 * What Home shows about the wallet: whether the first sync has finished, the balance,
 * and the transaction history.
 *
 * The UI-facing half of iOS's `loadWalletData()` → `updateTransactionHistory()` →
 * `finalizeSync()` chain (`LoadWalletData.swift`). The node types stay in
 * `:core:wallet-ldk`; this is what crosses into `:feature:home`, which depends on
 * this module and nothing wallet-specific below it.
 *
 * @property hasSynced iOS's `CoreViewController.walletHasSynced`. False until the first
 *   balance reading after the on-chain scan, and false for ever in a build with no node.
 *   Home gates Send, Receive and the balance card on it.
 * @property hasNode this build runs a node, so there is a sync to wait for. Home shows
 *   `home.headerSpinner` only while `hasNode && !hasSynced` — a build with no node has
 *   nothing to spin for, and a spinner that never stops would hold every flow that waits
 *   for it to disappear.
 */
data class WalletOverview(
    val hasNode: Boolean = false,
    val hasSynced: Boolean = false,
    val satoshisOnchain: Long = 0L,
    val satoshisLightning: Long = 0L,
    val pendingClosureSatoshis: Long = 0L,
    val transactions: List<WalletActivity> = emptyList(),
    /** The chain tip the node last saw — `bittrWallet.currentHeight`. Null before a reading. */
    val currentHeight: Int? = null,
    /**
     * `satoshisOnchainSpendable` — what ldk-node will let leave on-chain, which excludes the
     * anchor-channel reserve. Send checks amounts and clamps drains against it.
     */
    val satoshisOnchainSpendable: Long = 0L,
    /** The active channel's outbound capacity, in sats — what Send can pay over Lightning. */
    val lightningSendableSats: Long = 0L,
    /** `lightningChannels.count` — Move explains channels differently when there is none. */
    val channelCount: Int = 0,
    /** The channel `getActiveChannel()` returns — the first ready one — for the channel chart. */
    val activeChannel: ChannelSummary? = null,
    /**
     * Txids of the transactions that paid out a closed channel — `CacheManager.channelClosureTxIDs`,
     * which marks a history row `isChannelClosure` so its description reads
     * `channelclosuretransaction`.
     */
    val channelClosureTxIds: Set<String> = emptySet(),
) {

    /**
     * `setTotalSats()`: on-chain + Lightning + what is still sweeping back from a
     * channel closure.
     */
    val totalSatoshis: Long get() = satoshisOnchain + satoshisLightning + pendingClosureSatoshis
}

/**
 * One row of Home's history — the fields `HistoryTable.swift` reads off a `Transaction`.
 *
 * @property confirmationHeight null for an unconfirmed on-chain transaction, which iOS
 *   colours `unconfirmed`, and null for every Lightning payment, which has no height.
 * @property paymentHash the Lightning payment hash, which Receive and swaps key their
 *   descriptions by. Null on-chain.
 * @property description iOS `lnDescription`: the invoice or swap description stored for this
 *   transaction (`CacheManager.getInvoiceDescription`). A swap's legs carry its `dateID`.
 * @property swap set on a matched swap row, a swap with one leg so far, and a Swap & Pay leg —
 *   see [SwapHistory].
 */
data class WalletActivity(
    val id: String,
    val receivedSats: Long,
    val sentSats: Long,
    val feeSats: Long,
    val timestampSecs: Long,
    val isLightning: Boolean,
    val confirmationHeight: Int?,
    val paymentHash: String? = null,
    val description: String? = null,
    val swap: SwapActivity? = null,
) {

    /** `received - sent - fee`, which is the figure the row shows and signs. */
    val netSats: Long get() = receivedSats - sentSats - feeSats
}

/** Where [WalletOverview] comes from. A build with no node answers a never-synced overview. */
/**
 * The figures `QuestionViewController.setChannelChart(forChannel:)` draws.
 *
 * @property valueSats `channelValueSats`.
 * @property outboundSats `outboundCapacityMsat / 1000`.
 * @property reserveSats `unspendablePunishmentReserve ?? 0`.
 */
data class ChannelSummary(
    val valueSats: Long,
    val outboundSats: Long,
    val reserveSats: Long,
) {
    /** "Your balance": what can be sent plus the reserve that has to stay in. */
    val balanceSats: Long get() = outboundSats + reserveSats

    /** "Receive limit": the rest of the channel. */
    val receiveLimitSats: Long get() = valueSats - outboundSats - reserveSats

    /** The yellow bar's share of the grey one, clamped so a bad reading cannot overflow it. */
    val balanceFraction: Float
        get() = if (valueSats <= 0) 0f else (balanceSats.toFloat() / valueSats).coerceIn(0f, 1f)
}

interface WalletOverviewSource {
    val overview: StateFlow<WalletOverview>
}
