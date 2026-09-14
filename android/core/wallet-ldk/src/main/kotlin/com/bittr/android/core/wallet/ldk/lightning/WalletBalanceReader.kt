package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureCache

/**
 * `loadWalletData()` as a call rather than as a screen — the production caller
 * [WalletBalanceSnapshot.of] did not have.
 *
 * BIT-125 landed the arithmetic and BIT-128 landed the cache. Neither landed the
 * thing that runs them: grepping the main source sets for a call to
 * `CachedChannelClosureStore.store` found none, so `channel_funding_outpoint`
 * had no writer, `ChannelClosureScan.shouldScan` short-circuited on every sync,
 * and the closure scan BIT-130 wired in recorded nothing on a running app. This
 * class is the missing step, and the three writes below are the whole of what it
 * is for.
 *
 * ## One read, and it is the port's job to make it one
 *
 * [node] is asked once, through [LightningNodePort.readWalletState], which takes
 * the `Node` handle up front and makes the three FFI calls against the local.
 * Calling `listChannels()`, `listBalances()` and `listPayments()` from here
 * instead would reintroduce exactly the hazard [WalletBalanceSnapshot]'s class
 * comment describes: `NodeLifecycle.current` goes null between two statements
 * routinely on Android, and two thirds of a snapshot plus an empty list is
 * indistinguishable from a wallet with no channels.
 *
 * A null reading is **not** an empty wallet and is not written through. Nothing
 * is cached, nothing is cleared, and [read] answers null — which is the same
 * distinction [WalletBalanceSnapshot.ldkSpendableSats] is built on.
 *
 * ## The three writes, in iOS's order
 *
 * `LoadWalletData.swift:24–27`, `:49`, `:52–54`:
 *
 * 1. **The funding outpoint, only when there is one.** iOS reaches
 *    `storeChannelFundingOutpoint` only inside `if let channelTxo`, and
 *    [WalletBalanceSnapshot.channelFundingOutpointToStore] carries that as a
 *    null. Null means *do not write*, not *write null*: clearing a cached
 *    outpoint because a read happened while the channel was still pending loses
 *    the outpoint the closure scan needs to find the closing transaction. The
 *    `?.let` is the whole of that rule, and [ChannelClosureCache.store] has no
 *    nullable overload for it to be collapsed into.
 * 2. **The closure spending txids, unconditionally, empty list included.**
 *    [ChannelClosureCache.storeChannelClosureTxIds] is a **union**, not a
 *    replace — `CacheManager.swift:635–640` — and that is what makes this key
 *    safe to have two writers. The other one is `ChannelClosureRecorder`, at the
 *    end of every applied sync. Under replace semantics whichever ran last would
 *    erase the other's closure; an empty list from here would wipe the recorder's
 *    find. Under union semantics neither can, which is why it is written
 *    unconditionally rather than guarded on `isNotEmpty()`.
 * 3. **The clear, when a closure is pending.** iOS's
 *    `if pendingBalancesFromChannelClosures > 0 { removeChannelFundingOutpoint() }`.
 *    A force-close has happened, so there is no live funding outpoint to watch,
 *    and dropping it is what stops the scan running after every sync for the rest
 *    of the wallet's life.
 *
 * **Steps 1 and 3 can both fire, and iOS's order means the clear wins.** That is
 * a wallet holding an active channel *and* an unswept closure — two channels,
 * which the app does not have in practice but can have for as long as it takes a
 * force-close to sweep. The order is ported rather than reversed because of the
 * direction the two failures point: a cleared outpoint costs a closure label the
 * user does not see, and a stale one costs a label that is *wrong*, recorded
 * against whatever transaction happens to spend that output next.
 * `CachedChannelClosureStore.decodeOutpoint` chose absent over wrong for the same
 * reason, and the next read re-offers the active channel's outpoint anyway.
 *
 * ## Failures are swallowed, for `ChannelClosureRecorder`'s reason
 *
 * This runs on the on-chain sync loop's tick (see `OnchainSyncLoop`), and the
 * loop is a `NodeRunner`: an exception out of [read] would end the runner, and
 * with it the light-sync timer, until something restarts the node. The cost of
 * the real failure is one cache entry not written and another attempt in thirty
 * seconds. The cost of letting it out is the wallet stopping its on-chain sync
 * over it. Same asymmetry the recorder and the persist have, and [onFailure] is
 * where the trace goes so it is not silent.
 *
 * Proved by `WalletBalanceReaderTest`, and joined to the closure scan by
 * `ClosureScanWiringTest`.
 */
class WalletBalanceReader(
    private val node: LightningNodePort,
    private val closures: ChannelClosureCache,
    /** Where a swallowed failure goes. Defaulted to a no-op; `WalletModule` logs. */
    private val onFailure: (Throwable) -> Unit = {},
    /**
     * Every successful reading, after its cache writes — where Home's overview is
     * published from (`updateTransactionHistory()` follows `loadWalletData()` on iOS).
     */
    private val onReading: (WalletNodeReading, WalletBalanceSnapshot) -> Unit = { _, _ -> },
) {

    /**
     * Take one reading and perform the cache writes it names.
     *
     * @return the snapshot, or null when there was no node to read and when the
     *   read failed. The two are not distinguished here on purpose — every
     *   caller today wants the same thing from both, which is to try again on
     *   the next tick — and [onFailure] is what tells them apart in a log.
     */
    fun read(): WalletBalanceSnapshot? = try {
        readOrThrow()
    } catch (failure: Exception) {
        onFailure(failure)
        null
    }

    private fun readOrThrow(): WalletBalanceSnapshot? {
        // One block, one handle. See the class comment.
        val reading = node.readWalletState() ?: return null

        val snapshot = WalletBalanceSnapshot.of(
            channels = reading.channels,
            balances = reading.balances,
            payments = reading.payments,
        )

        // 1. Only inside `if let channelTxo`.
        snapshot.channelFundingOutpointToStore?.let(closures::store)

        // 2. Unconditional, because the key's other writer relies on the union.
        closures.storeChannelClosureTxIds(snapshot.closureSpendingTxIds)

        // 3. Last, which is iOS's order and is the direction that fails towards
        //    an absent label rather than a wrong one.
        if (snapshot.clearChannelFundingOutpoint) {
            closures.removeChannelFundingOutpoint()
        }

        onReading(reading, snapshot)
        return snapshot
    }
}
