package com.bittr.android.core.wallet.ldk.onchain

/**
 * The cache entries `storeChannelClosureTxIDIfFound` reads and writes.
 *
 * `CacheManager.getChannelFundingOutpoint` / `storeChannelClosureTxIDs` /
 * `removeChannelFundingOutpoint` (`BDKManager.swift:493`, `:510–511`).
 */
interface ChannelClosureStore {

    /** The funding outpoint of the channel being watched, or null if none is. */
    fun channelFundingOutpoint(): TxOutpoint?

    /**
     * `CacheManager.storeChannelClosureTxIDs(txIDs: [txid])`.
     *
     * A list of one, and iOS's call **appends the txids it does not already
     * have** rather than replacing the list (`CacheManager.swift:635–640`). That
     * matters because `LoadWalletData.swift:49` writes the pending-sweep txids to
     * the same key on every home-screen load: under replace semantics the two
     * writers would erase each other's closure depending on which ran last, and
     * under union semantics neither can.
     *
     * BIT-125 described this as a replace, on the strength of the call site
     * rather than the implementation. It is corrected here rather than in a
     * comment on the binding, because it is the contract an implementer reads —
     * see `CachedChannelClosureStore`, which is the first one.
     */
    fun storeChannelClosureTxIds(txIds: List<String>)

    /** `CacheManager.removeChannelFundingOutpoint()`. */
    fun removeChannelFundingOutpoint()
}

/** The wallet's transactions, as the pairs [ChannelClosureScan] compares. */
fun interface WalletTransactions {

    /**
     * `bdkWallet.transactions()`, mapped.
     *
     * @return for each wallet transaction, its own txid and the outpoints its
     *   inputs spend — `eachInput.previousOutput` on iOS. Mapping BDK's
     *   `CanonicalTx` into this is the adapter's only job here, which is the
     *   point: [ChannelClosureScan] is then pure.
     */
    fun transactions(): List<Pair<String, List<TxOutpoint>>>
}

/**
 * `storeChannelClosureTxIDIfFound()` (`BDKManager.swift:490–516`) — the sequence
 * around [ChannelClosureScan], which until now had a decision and no caller.
 *
 * `3371cb99` left this gap on purpose and said so: the scan's first step needs
 * the txids of channels that are still open, and `OnchainSync` had no channel
 * list to get them from. BIT-125 supplies it —
 * `WalletBalanceSnapshot.openChannelFundingTxIds` is exactly iOS's
 * `listChannels().compactMap { $0.fundingTxo?.txid }` — and this class is where
 * the two meet.
 *
 * ## Why the channel list arrives as a function
 *
 * [openChannelFundingTxIds] is a lambda, not a list. A sync is a network round
 * trip with a 180-second watchdog; a channel can close during one, and reading
 * the list before the scan rather than before the sync is what makes the
 * short-circuit in [ChannelClosureScan.shouldScan] answer about *now*. It also
 * keeps `onchain/` free of any Lightning type — the caller passes a lambda over
 * whatever it has.
 *
 * ## Failures are swallowed, and iOS is the reason
 *
 * iOS runs this on a background queue detached from the sync's completion, so
 * nothing it does can fail the sync that triggered it. Here it is called inline
 * — Android has no equivalent of "dispatch and forget" that a test can observe —
 * so the swallow has to be explicit instead. A closure txid that was not
 * recorded is a label missing from one row of the transaction list; a sync
 * reported as failed because of it would leave `hasBeenScanned` false, which is
 * what four call sites read to decide whether the user may open the send screen
 * at all. Same asymmetry the persist has, for the same reason.
 *
 * Proved by `ChannelClosureRecorderTest`.
 */
class ChannelClosureRecorder(
    private val store: ChannelClosureStore,
    private val transactions: WalletTransactions,
    private val openChannelFundingTxIds: () -> Collection<String>,
    /** Where a swallowed failure goes. iOS has nowhere; defaulted to a no-op. */
    private val onFailure: (Throwable) -> Unit = {},
) {

    /**
     * Look for the transaction that closed the watched channel, and remember it.
     *
     * @return the closing txid if one was found and recorded, else null.
     */
    fun record(): String? = try {
        recordOrThrow()
    } catch (failure: Exception) {
        onFailure(failure)
        null
    }

    private fun recordOrThrow(): String? {
        val fundingOutpoint = store.channelFundingOutpoint()

        if (!ChannelClosureScan.shouldScan(fundingOutpoint, openChannelFundingTxIds())) {
            return null
        }

        // Non-null: shouldScan returns false for a null outpoint.
        val closingTxId = ChannelClosureScan.findClosingTxId(
            fundingOutpoint = fundingOutpoint!!,
            candidates = transactions.transactions(),
        ) ?: return null

        // Order matters: record the closure, then stop watching. Clearing first
        // and failing to store would lose the txid with nothing left to find it
        // by, because step 1 short-circuits from then on.
        store.storeChannelClosureTxIds(listOf(closingTxId))
        store.removeChannelFundingOutpoint()
        return closingTxId
    }
}
