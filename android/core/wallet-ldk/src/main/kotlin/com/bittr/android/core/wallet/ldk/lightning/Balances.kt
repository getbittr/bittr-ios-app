package com.bittr.android.core.wallet.ldk.lightning

/**
 * Why a channel's funds are no longer in the channel — `BalanceSource`.
 *
 * The four cases are ldk-node's and the app cares about exactly one distinction:
 * [CoopClose] money is already counted in the on-chain balance, and the other
 * three are not. See [ClosureBalances.forceClosedSatoshis].
 */
enum class BalanceSourceView {
    HolderForceClosed,
    CounterpartyForceClosed,
    CoopClose,
    Htlc,
}

/**
 * `LightningBalance`, reduced to channel id, amount and — where it exists — the
 * reason.
 *
 * Heights, payment hashes and preimages are dropped: nothing in this app reads
 * them, and the arithmetic below is the only consumer.
 */
sealed interface LightningBalanceView {

    val channelId: String
    val amountSatoshis: ULong

    /** Funds in a channel that has not closed yet. */
    data class ClaimableOnChannelClose(
        override val channelId: String,
        override val amountSatoshis: ULong,
    ) : LightningBalanceView

    /** Closed and waiting for confirmations. [source] is what decides whether it counts. */
    data class ClaimableAwaitingConfirmations(
        override val channelId: String,
        override val amountSatoshis: ULong,
        val source: BalanceSourceView,
    ) : LightningBalanceView

    data class ContentiousClaimable(
        override val channelId: String,
        override val amountSatoshis: ULong,
    ) : LightningBalanceView

    data class MaybeTimeoutClaimableHtlc(
        override val channelId: String,
        override val amountSatoshis: ULong,
    ) : LightningBalanceView

    data class MaybePreimageClaimableHtlc(
        override val channelId: String,
        override val amountSatoshis: ULong,
    ) : LightningBalanceView

    data class CounterpartyRevokedOutputClaimable(
        override val channelId: String,
        override val amountSatoshis: ULong,
    ) : LightningBalanceView
}

/**
 * `PendingSweepBalance` — a closed channel's output on its way back on-chain.
 *
 * Three states, and the two questions asked of them pick *different* subsets:
 * [ClosureBalances.unbroadcastSatoshis] counts only the first, and
 * [ClosureBalances.spendingTxIds] collects only from the other two. That is not
 * an inconsistency; it is the same fact seen twice. Until the sweep is broadcast
 * there is no transaction to point the user at, and once it is broadcast the
 * money is visible to the on-chain wallet and counting it again would double it.
 */
sealed interface PendingSweepView {

    val amountSatoshis: ULong

    data class PendingBroadcast(
        override val amountSatoshis: ULong,
    ) : PendingSweepView

    data class BroadcastAwaitingConfirmation(
        override val amountSatoshis: ULong,
        val latestSpendingTxId: String,
    ) : PendingSweepView

    data class AwaitingThresholdConfirmations(
        override val amountSatoshis: ULong,
        val latestSpendingTxId: String,
    ) : PendingSweepView
}

/**
 * `BalanceDetails`.
 *
 * This is the record the whole of BIT-124's scope note turns on: **every
 * on-chain figure the user sees comes from here, never from BDK.** BDK does not
 * know about [totalAnchorChannelsReserveSats], so its idea of the balance is
 * high by that much and its idea of the maximum sendable is high enough to break
 * a channel's ability to fee-bump its own force-close. `OnchainDrainClamp`
 * exists to reconcile the two and this record is what finally supplies its
 * authority argument — see [WalletBalanceSnapshot.ldkSpendableSats].
 */
data class BalanceView(
    val totalOnchainBalanceSats: ULong,
    val spendableOnchainBalanceSats: ULong,
    val totalAnchorChannelsReserveSats: ULong,
    val totalLightningBalanceSats: ULong,
    val lightningBalances: List<LightningBalanceView>,
    val pendingBalancesFromChannelClosures: List<PendingSweepView>,
)

/**
 * Money that left a channel and has not arrived on-chain yet.
 *
 * Port of the three `BalanceDetails` extensions in
 * `LoadWalletData.swift:584–649`. All of it is addition, which is exactly why it
 * is here rather than in the adapter: addition is what gets ported wrong
 * silently, and every term that is wrongly included or excluded moves a number
 * on the user's home screen.
 *
 * ## The two exclusions are the content
 *
 * 1. **Cooperative closes do not count.** Their output is a plain payment to the
 *    wallet's own on-chain address, so it is already inside
 *    `totalOnchainBalanceSats`. Counting it here shows the user their money
 *    twice. iOS matches `.coopClose` explicitly rather than with a default, and
 *    says why: it keeps the switch exhaustive over `BalanceSource`, so a future
 *    LDK case is a compile error to classify rather than a silent exclusion. The
 *    `when` below is exhaustive over the sealed hierarchy for the same reason and
 *    has no `else`.
 *
 * 2. **Balances belonging to a channel that is still open do not count.**
 *    `claimableOnChannelClose` is the running balance of a live channel — it is
 *    already in `satoshisLightning`. But iOS goes further and filters *every*
 *    force-close-shaped balance by `!openChannelIds.contains(channelId)`, and
 *    that second guard is not redundant: ldk-node can report an HTLC balance
 *    against a channel that is still in `listChannels()`, and adding it to the
 *    pending-closure total tells the user a channel they can still spend from is
 *    closing.
 *
 * Proved by `ClosureBalancesTest`.
 */
object ClosureBalances {

    /**
     * `BalanceDetails.pendingClosureSatoshis(openChannelIds:)`
     * (`LoadWalletData.swift:585–588`).
     *
     * @param openChannelIds `listChannels().map { it.channelId }` — the
     *   **channel** id, not the user channel id. [ChannelView] keeps them apart;
     *   passing the wrong one makes the filter match nothing and every open
     *   channel's HTLC balance reads as pending closure.
     */
    fun pendingClosureSatoshis(
        balances: BalanceView,
        openChannelIds: Collection<String>,
    ): Long = forceClosedSatoshis(balances.lightningBalances, openChannelIds) +
        unbroadcastSatoshis(balances.pendingBalancesFromChannelClosures)

    /**
     * `[LightningBalance].forceClosedSatoshis(excludingChannels:)`
     * (`LoadWalletData.swift:624–648`).
     */
    fun forceClosedSatoshis(
        balances: List<LightningBalanceView>,
        excludingChannels: Collection<String>,
    ): Long = balances.sumOf { balance ->
        val counts = when (balance) {
            is LightningBalanceView.ClaimableAwaitingConfirmations ->
                // The one case where the reason decides. Coop-close funds are
                // already on-chain; see the class comment, point 1.
                balance.source != BalanceSourceView.CoopClose

            is LightningBalanceView.ContentiousClaimable,
            is LightningBalanceView.MaybeTimeoutClaimableHtlc,
            is LightningBalanceView.MaybePreimageClaimableHtlc,
            is LightningBalanceView.CounterpartyRevokedOutputClaimable,
            -> true

            // A live channel's balance. Already counted as spendable Lightning.
            is LightningBalanceView.ClaimableOnChannelClose -> false
        }

        if (counts && balance.channelId !in excludingChannels) balance.amountSatoshis.toLong() else 0L
    }

    /**
     * `[PendingSweepBalance].unbroadcastSatoshis()` (`LoadWalletData.swift:593–603`).
     *
     * Only [PendingSweepView.PendingBroadcast]. Once the sweep is broadcast the
     * output is a wallet UTXO and the on-chain balance has it.
     */
    fun unbroadcastSatoshis(sweeps: List<PendingSweepView>): Long = sweeps.sumOf { sweep ->
        when (sweep) {
            is PendingSweepView.PendingBroadcast -> sweep.amountSatoshis.toLong()
            is PendingSweepView.BroadcastAwaitingConfirmation,
            is PendingSweepView.AwaitingThresholdConfirmations,
            -> 0L
        }
    }

    /**
     * `[PendingSweepBalance].spendingTxIDs()` (`LoadWalletData.swift:607–619`).
     *
     * The transactions carrying the swept funds, for the closure list the user
     * sees. A sweep that has not been broadcast has no transaction to name, which
     * is the mirror image of [unbroadcastSatoshis] and the reason the two do not
     * share a filter.
     */
    fun spendingTxIds(sweeps: List<PendingSweepView>): List<String> = sweeps.mapNotNull { sweep ->
        when (sweep) {
            is PendingSweepView.BroadcastAwaitingConfirmation -> sweep.latestSpendingTxId
            is PendingSweepView.AwaitingThresholdConfirmations -> sweep.latestSpendingTxId
            is PendingSweepView.PendingBroadcast -> null
        }
    }
}
