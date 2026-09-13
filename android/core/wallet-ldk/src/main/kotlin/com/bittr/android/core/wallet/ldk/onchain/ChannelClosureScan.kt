package com.bittr.android.core.wallet.ldk.onchain

/**
 * A transaction outpoint, as plain data.
 *
 * Stands in for iOS's `ChannelOutpoint` (`CacheStore.swift:145`) and for BDK's
 * `OutPoint` at the same time. Both carry a txid string and a vout; neither type
 * may appear here — BDK's because it drags a native library behind it, iOS's
 * because it does not exist on this platform.
 */
data class TxOutpoint(
    val txId: String,
    val vout: UInt,
)

/**
 * Finding the transaction that closed a channel.
 *
 * Port of `storeChannelClosureTxIDIfFound` (`BDKManager.swift:490–516`). When a
 * channel closes, the funding output gets spent by the closing transaction, and
 * the app needs that txid: it is what the user is shown as the closure, and on
 * iOS it is also the force-close sweep material the BIT-20 quarantine is careful
 * to preserve.
 *
 * iOS's shape is three steps, and all three are decisions rather than plumbing:
 *
 * 1. **Do nothing while the channel is still open.** `openFundingTxIDs` comes from
 *    `listChannels()`, and the scan is skipped if the cached funding outpoint's
 *    txid is still among them (`BDKManager.swift:493–495`). Without this the scan
 *    runs after every sync for the life of the channel.
 * 2. **Match on the full outpoint, txid *and* vout.** A funding transaction can
 *    have several outputs and only one of them funds this channel.
 * 3. **Stop at the first match** (`return` inside the loop), and clear the cached
 *    funding outpoint so step 1 short-circuits from then on.
 *
 * ## Why step 2 is the one worth a test
 *
 * Matching on txid alone looks equivalent and almost always is — then it is not,
 * in the case that matters. A channel funded by output 1 of a transaction whose
 * output 0 is an ordinary change payment back to this same wallet would report
 * the *change-spending* transaction as the channel closure the first time that
 * change is spent. The user is shown a closure that has not happened, and the
 * cached funding outpoint is cleared, so the real closure is never recorded.
 * `ChannelClosureScanTest` carries that exact case.
 *
 * Pure and JVM-provable because it takes the inputs as [TxOutpoint] lists: the
 * adapter's only job is to map BDK's `transactions()` into them.
 */
object ChannelClosureScan {

    /**
     * Whether the scan should run at all.
     *
     * iOS: `guard let fundingOutpoint = CacheManager.getChannelFundingOutpoint(),
     * !openFundingTxIDs.contains(fundingOutpoint.txID) else { return }`.
     *
     * @param fundingOutpoint the cached funding outpoint, or null if no channel
     *   has been funded — nothing to look for.
     * @param openChannelFundingTxIds txids of the funding outputs of channels
     *   that are currently open, from `listChannels()`.
     */
    fun shouldScan(
        fundingOutpoint: TxOutpoint?,
        openChannelFundingTxIds: Collection<String>,
    ): Boolean {
        if (fundingOutpoint == null) return false
        // Still open — iOS compares txid only here, and that is correct at this
        // step: it is asking "is this funding transaction still backing a live
        // channel", not "which output".
        return fundingOutpoint.txId !in openChannelFundingTxIds
    }

    /**
     * The txid of the transaction that spends [fundingOutpoint], or null.
     *
     * @param candidates each wallet transaction as (its own txid, the outpoints
     *   its inputs spend). Order is the order BDK returns, and the first match
     *   wins — iOS's `return` inside the loop.
     */
    fun findClosingTxId(
        fundingOutpoint: TxOutpoint,
        candidates: List<Pair<String, List<TxOutpoint>>>,
    ): String? = candidates
        .firstOrNull { (_, spentOutpoints) -> fundingOutpoint in spentOutpoints }
        ?.first
}
