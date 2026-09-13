package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The closure scan's sequence, and its place in a sync.
 *
 * `ChannelClosureScanTest` already proves the matching rule — full outpoint, not
 * txid alone. What is new here is everything around it: when the scan is skipped,
 * what order the two cache writes happen in, and that a failure inside it cannot
 * fail the sync that triggered it.
 */
class ChannelClosureRecorderTest {

    private val funding = TxOutpoint(txId = "funding-tx", vout = 1u)

    private class FakeStore(
        var outpoint: TxOutpoint? = null,
    ) : ChannelClosureStore {
        val writes = mutableListOf<String>()
        var storedTxIds: List<String>? = null
        var storeFailure: Exception? = null

        override fun channelFundingOutpoint() = outpoint

        override fun storeChannelClosureTxIds(txIds: List<String>) {
            writes += "store"
            storeFailure?.let { throw it }
            storedTxIds = txIds
        }

        override fun removeChannelFundingOutpoint() {
            writes += "remove"
            outpoint = null
        }
    }

    private fun recorder(
        store: FakeStore,
        transactions: List<Pair<String, List<TxOutpoint>>> = emptyList(),
        openFundingTxIds: List<String> = emptyList(),
        onFailure: (Throwable) -> Unit = {},
    ) = ChannelClosureRecorder(
        store = store,
        transactions = { transactions },
        openChannelFundingTxIds = { openFundingTxIds },
        onFailure = onFailure,
    )

    @Test
    fun `the closing transaction is recorded and the outpoint stops being watched`() {
        val store = FakeStore(outpoint = funding)

        val found = recorder(
            store = store,
            transactions = listOf(
                "unrelated-tx" to listOf(TxOutpoint("other", 0u)),
                "closing-tx" to listOf(funding),
            ),
        ).record()

        assertEquals("closing-tx", found)
        assertEquals(listOf("closing-tx"), store.storedTxIds)
        assertEquals(
            "Record first, then stop watching. The other order loses the txid if the " +
                "store throws, because step 1 short-circuits from then on.",
            listOf("store", "remove"),
            store.writes,
        )
        assertNull(store.outpoint)
    }

    /**
     * Step 1 of `storeChannelClosureTxIDIfFound` — the guard that stops the scan
     * running after every sync for the life of a channel.
     */
    @Test
    fun `a channel that is still open is not scanned for`() {
        val store = FakeStore(outpoint = funding)

        val found = recorder(
            store = store,
            transactions = listOf("closing-tx" to listOf(funding)),
            openFundingTxIds = listOf("funding-tx"),
        ).record()

        assertNull(found)
        assertTrue("Nothing written.", store.writes.isEmpty())
        assertEquals("Still watching.", funding, store.outpoint)
    }

    @Test
    fun `no cached funding outpoint means nothing to look for`() {
        val store = FakeStore(outpoint = null)

        assertNull(recorder(store, transactions = listOf("tx" to listOf(funding))).record())
        assertTrue(store.writes.isEmpty())
    }

    @Test
    fun `a closed channel whose closing transaction has not arrived yet keeps watching`() {
        val store = FakeStore(outpoint = funding)

        val found = recorder(
            store = store,
            transactions = listOf("unrelated-tx" to listOf(TxOutpoint("other", 0u))),
        ).record()

        assertNull(found)
        assertTrue(store.writes.isEmpty())
        assertEquals(
            "The outpoint must survive: the closing transaction may confirm on the " +
                "next sync, and clearing it now would mean never finding it.",
            funding,
            store.outpoint,
        )
    }

    /**
     * The channel list is read at scan time, not at sync time.
     *
     * A full scan is a round trip with a 180-second watchdog, and a channel can
     * close inside one. Capturing the list earlier would ask "was it open when the
     * sync started", which is the wrong question.
     */
    @Test
    fun `the open-channel list is read when the scan runs`() {
        val store = FakeStore(outpoint = funding)
        var stillOpen = true

        val subject = ChannelClosureRecorder(
            store = store,
            transactions = { listOf("closing-tx" to listOf(funding)) },
            openChannelFundingTxIds = { if (stillOpen) listOf("funding-tx") else emptyList() },
        )

        assertNull("Open at the first call.", subject.record())

        stillOpen = false
        assertEquals("closing-tx", subject.record())
    }

    @Test
    fun `a failure inside the scan is swallowed, not returned`() {
        val failure = IllegalStateException("cache write failed")
        val store = FakeStore(outpoint = funding).apply { storeFailure = failure }
        val swallowed = mutableListOf<Throwable>()

        val found = recorder(
            store = store,
            transactions = listOf("closing-tx" to listOf(funding)),
            onFailure = { swallowed += it },
        ).record()

        assertNull(found)
        assertEquals(listOf(failure), swallowed)
        assertEquals(
            "The remove did not run, so the outpoint is still watched and the next " +
                "sync tries again.",
            funding,
            store.outpoint,
        )
    }
}

/**
 * The recorder's place in the sync sequence.
 *
 * iOS calls `storeChannelClosureTxIDIfFound()` from both sync paths and from
 * nowhere else, immediately before reporting success — so "did it run, and only
 * on success" is a property of `OnchainSync`, not of the recorder.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OnchainSyncClosureScanTest {

    private val funding = TxOutpoint(txId = "funding-tx", vout = 0u)

    private class CountingStore : ChannelClosureStore {
        var outpoint: TxOutpoint? = null
        var stored: List<String>? = null
        override fun channelFundingOutpoint() = outpoint
        override fun storeChannelClosureTxIds(txIds: List<String>) { stored = txIds }
        override fun removeChannelFundingOutpoint() { outpoint = null }
    }

    /** A port that applies cleanly, or fails at the step named. */
    private class SimplePort(
        var wallet: String? = "wallet-1",
        val applyFailure: Exception? = null,
    ) : OnchainSyncPort<String, String, String, String> {
        override fun currentWallet() = wallet
        override fun startFullScan(wallet: String) = "full"
        override fun fullScan(request: String, parameters: FullScanParameters) = "update"
        override fun startSyncWithRevealedSpks(wallet: String) = "light"
        override fun sync(request: String, parameters: LightSyncParameters) = "update"
        override fun applyUpdate(wallet: String, update: String) { applyFailure?.let { throw it } }
        override fun persist(wallet: String) = Unit
    }

    private fun TestScope.sync(port: SimplePort, store: CountingStore) = OnchainSync(
        port = port,
        scans = ScanCoordinator(this),
        closures = ChannelClosureRecorder(
            store = store,
            transactions = { listOf("closing-tx" to listOf(funding)) },
            openChannelFundingTxIds = { emptyList() },
        ),
    )

    @Test
    fun `a full scan that applies runs the closure scan`() = runTest {
        val store = CountingStore().apply { outpoint = funding }

        assertTrue(sync(SimplePort(), store).fullScan())

        assertEquals(listOf("closing-tx"), store.stored)
    }

    @Test
    fun `a light sync that applies runs the closure scan`() = runTest {
        val store = CountingStore().apply { outpoint = funding }

        assertTrue(sync(SimplePort(), store).lightSync())

        assertEquals(listOf("closing-tx"), store.stored)
    }

    /**
     * The negative control. iOS's call sits after the persist on the success
     * path; a sync that never applied has not learned anything new about the
     * chain, so scanning its transactions would be scanning a stale wallet.
     */
    @Test
    fun `a sync that did not apply does not run the closure scan`() = runTest {
        val store = CountingStore().apply { outpoint = funding }
        val port = SimplePort(applyFailure = IllegalStateException("cannot connect"))

        assertFalse(sync(port, store).lightSync())

        assertNull(store.stored)
        assertEquals(funding, store.outpoint)
    }

    @Test
    fun `a sync with no recorder behaves exactly as before`() = runTest {
        val outcome = OnchainSync(
            port = SimplePort(),
            scans = ScanCoordinator(this),
        ).runLightSync()

        assertTrue(outcome.applied)
    }
}
