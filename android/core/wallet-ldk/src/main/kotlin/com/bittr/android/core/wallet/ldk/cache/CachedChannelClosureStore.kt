package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureCache
import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureStore
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint

/**
 * [ChannelClosureStore] over a [WalletCache] — the three `CacheManager` entries
 * `storeChannelClosureTxIDIfFound` reads and writes (`BDKManager.swift:493`,
 * `:510–511`).
 *
 * ## The writer the recorder's seam does not have
 *
 * `ChannelClosureStore` is only what `ChannelClosureRecorder` needs, which is
 * two reads and a clear. Somebody has to put the funding outpoint *in* —
 * `CacheManager.storeChannelFundingOutpoint(txID:vout:)` — and until BIT-144
 * that somebody did not exist in `main`, so [channelFundingOutpoint] answered
 * null for ever and the closure scan short-circuited on every sync.
 *
 * [store] is that writer. It is on [ChannelClosureCache] rather than on
 * `ChannelClosureStore` so the recorder's seam stays as narrow as it was — the
 * thing that runs inside a sync cannot start watching a channel — and
 * `WalletBalanceReader` takes the wider one. That reader is iOS's
 * `loadWalletData()`: it writes the outpoint of whichever channel is active on
 * every on-chain sync tick, which is the trigger Android has instead of a home
 * screen.
 *
 * On a wallet that has never opened a channel there is still nothing to write,
 * because `listChannels()` is empty. The channel-open path is BIT-122's
 * remaining half, and when it lands it writes through this same method.
 *
 * [closureTxIds] is the matching reader for `CacheManager.getChannelClosureTxIDs`.
 * Without it this class only ever writes that key, and a store nothing reads is
 * indistinguishable from a store that is broken.
 *
 * ## Failures propagate, because the recorder already swallows them
 *
 * Nothing here catches. `ChannelClosureRecorder.record` wraps the whole sequence
 * in one try/catch with an `onFailure` hook and explains why the swallow lives
 * there: a closure txid that was not recorded is a missing label, and a sync
 * reported as failed because of it would leave `hasBeenScanned` false, which is
 * what decides whether the user may open the send screen at all. Catching here
 * as well would mean the recorder's `onFailure` never fires and the missing
 * label has no trace anywhere.
 *
 * Proved by `CachedChannelClosureStoreTest`.
 */
class CachedChannelClosureStore(
    private val cache: WalletCache,
) : ChannelClosureCache {

    override fun channelFundingOutpoint(): TxOutpoint? =
        cache.strings(KEY_FUNDING_OUTPOINT).firstOrNull()?.let(::decodeOutpoint)

    /**
     * `CacheManager.storeChannelFundingOutpoint(txID:vout:)` — one channel at a
     * time, replacing whatever was being watched.
     */
    override fun store(outpoint: TxOutpoint) {
        cache.put(KEY_FUNDING_OUTPOINT, listOf("${outpoint.txId}$OUTPOINT_SEPARATOR${outpoint.vout}"))
    }

    override fun removeChannelFundingOutpoint() = cache.remove(KEY_FUNDING_OUTPOINT)

    /**
     * `CacheManager.storeChannelClosureTxIDs(txIDs:)`, which **appends the ones
     * it does not already have** rather than replacing the list:
     *
     * ```swift
     * let cachedTxIDs = getChannelClosureTxIDs()
     * let newTxIDs = txIDs.filter { !cachedTxIDs.contains($0) }
     * guard !newTxIDs.isEmpty else { return }
     * CacheStore.set(cachedTxIDs + newTxIDs, for: CacheKeys.channelClosureTxIDs)
     * ```
     *
     * `CacheManager.swift:635–640`, and it is the behaviour that makes the key's
     * *second* writer safe: `LoadWalletData.swift:49` writes the pending-sweep
     * txids to the same key on every home-screen load. Under replace semantics
     * those two writers would erase each other's closure — the sweep list would
     * drop the cooperative closure found by the scan, or the reverse, depending
     * on which ran last. Under union semantics neither can, which is why this is
     * ported exactly and not simplified.
     */
    override fun storeChannelClosureTxIds(txIds: List<String>) {
        cache.update(KEY_CLOSURE_TX_IDS) { stored -> stored + txIds.filterNot(stored::contains) }
    }

    /** `CacheManager.getChannelClosureTxIDs()`. */
    fun closureTxIds(): List<String> = cache.strings(KEY_CLOSURE_TX_IDS)

    /**
     * Null for anything that is not `<txid>:<vout>`.
     *
     * Fail-safe in the direction that matters. A funding outpoint that cannot be
     * parsed makes `ChannelClosureScan.shouldScan` answer false, so the scan does
     * not run and no closure is recorded — a label the user does not see. Reading
     * a damaged entry *optimistically* would mean scanning for the wrong outpoint
     * and recording some unrelated transaction as the channel's closure, which is
     * a label that is wrong rather than absent.
     */
    private fun decodeOutpoint(encoded: String): TxOutpoint? {
        val txId = encoded.substringBeforeLast(OUTPOINT_SEPARATOR, missingDelimiterValue = "")
        val vout = encoded.substringAfterLast(OUTPOINT_SEPARATOR).toUIntOrNull()
        return if (txId.isEmpty() || vout == null) null else TxOutpoint(txId = txId, vout = vout)
    }

    companion object {

        /** `CacheKeys.channelFundingOutpoint`. */
        const val KEY_FUNDING_OUTPOINT = "channel_funding_outpoint"

        /** `CacheKeys.channelClosureTxIDs`. */
        const val KEY_CLOSURE_TX_IDS = "channel_closure_tx_ids"

        /**
         * `:` — not in a txid's alphabet, and not in a decimal vout, so
         * `substringAfterLast` cannot be confused by the value it is splitting.
         */
        private const val OUTPOINT_SEPARATOR = ':'
    }
}
