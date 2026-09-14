package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureCache
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The caller `WalletBalanceSnapshot.of` did not have, and the three cache writes
 * it makes.
 *
 * `WalletBalanceSnapshotTest` owns the arithmetic and which writes a given wallet
 * state *asks for*. What is asserted here is that they are *performed*, and
 * performed the way the snapshot's contract says — which is where a port loses
 * the funding outpoint:
 *
 * - `null means do not write` collapses into `store(null)` or into an
 *   unconditional `remove` the moment somebody tidies the `?.let` away, and the
 *   wallet then forgets the channel it is watching every time a read happens
 *   while the channel is pending.
 * - the closure txids are written **unconditionally**, including empty, because
 *   the key's union semantics are what make its second writer safe. A guard on
 *   `isNotEmpty()` would look like an optimisation and be one — but a *replace*
 *   here would silently erase `ChannelClosureRecorder`'s find, so the pair is
 *   asserted together.
 *
 * The recording store is the real `CachedChannelClosureStore`'s contract as an
 * order-preserving log, because two of the three claims are about ordering and
 * about what did *not* happen. `ClosureScanWiringTest` runs the same reader
 * against the real file-backed store and the real recorder.
 */
class WalletBalanceReaderTest {

    private val fundingTxo = TxOutpoint(txId = "funding-tx", vout = 1u)

    /** Every call, in order. Absence is half of what these tests assert. */
    private class RecordingCache : ChannelClosureCache {

        val calls = mutableListOf<String>()

        /** Not read by the reader; present because the interface carries it. */
        override fun channelFundingOutpoint(): TxOutpoint? = null

        override fun store(outpoint: TxOutpoint) {
            calls += "store(${outpoint.txId}:${outpoint.vout})"
        }

        override fun storeChannelClosureTxIds(txIds: List<String>) {
            calls += "closureTxIds($txIds)"
        }

        override fun removeChannelFundingOutpoint() {
            calls += "remove"
        }
    }

    private fun reader(
        reading: WalletNodeReading?,
        cache: ChannelClosureCache,
        onFailure: (Throwable) -> Unit = { throw it },
    ) = WalletBalanceReader(
        node = ReadingOnlyPort(reading),
        closures = cache,
        onFailure = onFailure,
    )

    // ---- The write that was missing. ----

    @Test
    fun `an active channel's funding outpoint is written to the cache`() {
        val cache = RecordingCache()

        val snapshot = reader(reading(channels = listOf(channel(fundingTxo = fundingTxo))), cache)
            .read()

        assertNotNull(snapshot)
        assertEquals(
            "This is the write BIT-144 is about. Without it ChannelClosureScan.shouldScan " +
                "short-circuits on every sync for the life of the wallet.",
            listOf("store(funding-tx:1)", "closureTxIds([])"),
            cache.calls,
        )
    }

    @Test
    fun `a pending channel writes no outpoint and clears nothing`() {
        val cache = RecordingCache()

        reader(
            reading(channels = listOf(channel(isChannelReady = false, fundingTxo = fundingTxo))),
            cache,
        ).read()

        // Null means do not write, not write null — and not "remove" either. The
        // channel being watched is whatever was cached before this read.
        assertEquals(listOf("closureTxIds([])"), cache.calls)
    }

    // ---- The clear, and the case where both fire. ----

    @Test
    fun `a pending closure clears the watched outpoint`() {
        val cache = RecordingCache()

        reader(
            reading(
                balances = balances(
                    pendingBalancesFromChannelClosures = listOf(
                        PendingSweepView.PendingBroadcast(amountSatoshis = 7_000uL),
                    ),
                ),
            ),
            cache,
        ).read()

        assertEquals(listOf("closureTxIds([])", "remove"), cache.calls)
    }

    /**
     * Two channels: one live, one force-closing. iOS writes the outpoint and then
     * removes it, and the order is ported rather than reversed.
     *
     * The reason is the direction the two failures point. A cleared outpoint
     * costs a closure label the user never sees; a stale one costs a label that
     * is wrong, recorded against whatever spends that output next. The next tick
     * re-offers the live channel's outpoint anyway, so the cost of iOS's order is
     * bounded by how long the sweep takes.
     *
     * Asserted so that a reordering is a decision somebody makes on purpose.
     */
    @Test
    fun `when both fire the clear runs last, which is iOS's order`() {
        val cache = RecordingCache()

        reader(
            reading(
                channels = listOf(channel(fundingTxo = fundingTxo)),
                balances = balances(
                    pendingBalancesFromChannelClosures = listOf(
                        PendingSweepView.PendingBroadcast(amountSatoshis = 1_000uL),
                    ),
                ),
            ),
            cache,
        ).read()

        assertEquals(
            listOf("store(funding-tx:1)", "closureTxIds([])", "remove"),
            cache.calls,
        )
    }

    // ---- The key with two writers. ----

    @Test
    fun `the closure spending txids are written even when there are none`() {
        val cache = RecordingCache()

        reader(reading(), cache).read()

        assertEquals(
            "Guarding this on isNotEmpty() reads as an optimisation and hides the " +
                "contract: storeChannelClosureTxIds is a union, so an empty write is a " +
                "no-op rather than an erasure, and the day it stops being a union this " +
                "call site is where the damage shows.",
            listOf("closureTxIds([])"),
            cache.calls,
        )
    }

    @Test
    fun `broadcast sweeps are handed to the store as the union it expects`() {
        val cache = RecordingCache()

        reader(
            reading(
                balances = balances(
                    pendingBalancesFromChannelClosures = listOf(
                        PendingSweepView.PendingBroadcast(1_000uL),
                        PendingSweepView.BroadcastAwaitingConfirmation(2_000uL, "sweep-a"),
                        PendingSweepView.AwaitingThresholdConfirmations(3_000uL, "sweep-b"),
                    ),
                ),
            ),
            cache,
        ).read()

        assertEquals(
            listOf("closureTxIds([sweep-a, sweep-b])", "remove"),
            cache.calls,
        )
    }

    // ---- No node. ----

    /**
     * The state a configured build spends every restart in, and the unconfigured
     * build spends its whole life in.
     *
     * Nothing may be written. A reader that treated "no node" as an empty wallet
     * would clear no outpoint — `clearChannelFundingOutpoint` is false on empty
     * balances — but it *would* write an empty closure-txid list and, worse,
     * would report a zero balance as a real reading to whatever reads the
     * snapshot next. `ldkSpendableSats` is built on that distinction.
     */
    @Test
    fun `no node means no snapshot and no writes at all`() {
        val cache = RecordingCache()

        val snapshot = reader(reading = null, cache = cache).read()

        assertNull(snapshot)
        assertEquals(emptyList<String>(), cache.calls)
    }

    // ---- Failures. ----

    /**
     * The sync loop is a `NodeRunner`: an exception out of `read()` ends it, and
     * with it the light-sync timer, until something restarts the node. A cache
     * write that failed is worth one log line and another attempt in thirty
     * seconds — not that.
     */
    @Test
    fun `a failing cache write is swallowed and reported`() {
        val failure = java.io.IOException("no space left on device")
        val failures = mutableListOf<Throwable>()
        val cache = object : ChannelClosureCache {
            override fun channelFundingOutpoint(): TxOutpoint? = null
            override fun store(outpoint: TxOutpoint) = throw failure
            override fun storeChannelClosureTxIds(txIds: List<String>) = Unit
            override fun removeChannelFundingOutpoint() = Unit
        }

        val snapshot = WalletBalanceReader(
            node = ReadingOnlyPort(reading(channels = listOf(channel(fundingTxo = fundingTxo)))),
            closures = cache,
            onFailure = { failures += it },
        ).read()

        assertNull(snapshot)
        assertEquals(listOf<Throwable>(failure), failures)
    }

    /**
     * One `readWalletState()` per read and nothing else.
     *
     * The count is the cheap half; the expensive half is [ReadingOnlyPort],
     * whose three separate reads throw — so a snapshot assembled from three
     * moments fails here rather than passing.
     */
    @Test
    fun `each read asks the node exactly once`() {
        val port = ReadingOnlyPort(reading(channels = listOf(channel(fundingTxo = fundingTxo))))
        val reader = WalletBalanceReader(node = port, closures = RecordingCache())

        reader.read()
        reader.read()

        assertEquals(2, port.reads)
    }
}
