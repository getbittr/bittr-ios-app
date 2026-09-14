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
 */
data class WalletActivity(
    val id: String,
    val receivedSats: Long,
    val sentSats: Long,
    val feeSats: Long,
    val timestampSecs: Long,
    val isLightning: Boolean,
    val confirmationHeight: Int?,
) {

    /** `received - sent - fee`, which is the figure the row shows and signs. */
    val netSats: Long get() = receivedSats - sentSats - feeSats
}

/** Where [WalletOverview] comes from. A build with no node answers a never-synced overview. */
interface WalletOverviewSource {
    val overview: StateFlow<WalletOverview>
}
