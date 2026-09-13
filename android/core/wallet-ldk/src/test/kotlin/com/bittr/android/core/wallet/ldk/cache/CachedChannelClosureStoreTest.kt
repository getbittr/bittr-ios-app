package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureRecorder
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The three cache entries behind `ChannelClosureRecorder`, over a real file
 * store.
 *
 * `ChannelClosureRecorderTest` proves the sequence against a counting fake. What
 * is left to prove is the part a fake cannot: that the outpoint survives being
 * written down and read back, and that the txid list accumulates the way
 * `CacheManager` accumulates it rather than the way BIT-125 described it.
 */
class CachedChannelClosureStoreTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var directory: File

    @Before
    fun setUp() {
        directory = temporaryFolder.newFolder("cache")
    }

    private fun store() = CachedChannelClosureStore(FileWalletCache(directory))

    @Test
    fun `the watched outpoint survives the process that wrote it`() {
        store().store(TxOutpoint(txId = "a".repeat(64), vout = 3u))

        assertEquals(
            TxOutpoint(txId = "a".repeat(64), vout = 3u),
            store().channelFundingOutpoint(),
        )
    }

    @Test
    fun `there is no outpoint until one is stored`() {
        assertNull(store().channelFundingOutpoint())
    }

    @Test
    fun `storing a second outpoint replaces the first`() {
        val store = store()
        store.store(TxOutpoint(txId = "a".repeat(64), vout = 0u))

        store.store(TxOutpoint(txId = "b".repeat(64), vout = 1u))

        assertEquals(TxOutpoint("b".repeat(64), 1u), store().channelFundingOutpoint())
    }

    @Test
    fun `removing the outpoint stops the scan short-circuiting on it`() {
        val store = store()
        store.store(TxOutpoint(txId = "a".repeat(64), vout = 0u))

        store.removeChannelFundingOutpoint()

        assertNull(store.channelFundingOutpoint())
        assertNull("And durably.", store().channelFundingOutpoint())
    }

    /**
     * Fail-safe in the direction that matters: a funding outpoint that cannot be
     * parsed makes `ChannelClosureScan.shouldScan` answer false, so no closure is
     * recorded. Reading a damaged entry optimistically would mean scanning for
     * the wrong outpoint and labelling some unrelated transaction as the
     * channel's closure — wrong rather than absent.
     */
    @Test
    fun `a damaged outpoint reads as no outpoint`() {
        FileWalletCache(directory).put(
            CachedChannelClosureStore.KEY_FUNDING_OUTPOINT,
            listOf("not-an-outpoint"),
        )

        assertNull(store().channelFundingOutpoint())
    }

    /**
     * `CacheManager.storeChannelClosureTxIDs` appends what it does not already
     * have (`CacheManager.swift:635–640`). The key has a second writer —
     * `LoadWalletData.swift:49` writes the pending-sweep txids to it on every
     * home-screen load — and under replace semantics the two would erase each
     * other's closure depending on which ran last.
     */
    @Test
    fun `closure txids accumulate across both writers instead of replacing`() {
        val store = store()

        store.storeChannelClosureTxIds(listOf("closure-txid"))
        // The home screen's write: a different closure's sweep txids.
        store.storeChannelClosureTxIds(listOf("sweep-txid-1", "sweep-txid-2"))

        assertEquals(
            listOf("closure-txid", "sweep-txid-1", "sweep-txid-2"),
            store().closureTxIds(),
        )
    }

    @Test
    fun `a txid already stored is not stored twice`() {
        val store = store()

        store.storeChannelClosureTxIds(listOf("closure-txid"))
        store.storeChannelClosureTxIds(listOf("closure-txid", "another"))

        assertEquals(listOf("closure-txid", "another"), store.closureTxIds())
    }

    /**
     * The store in the sequence it was written for: a channel is watched, its
     * closing transaction appears in the wallet, and the record outlives the
     * process that made it.
     */
    @Test
    fun `the recorder finds the closure and the record survives`() {
        val funding = TxOutpoint(txId = "f".repeat(64), vout = 1u)
        store().store(funding)

        val recorded = ChannelClosureRecorder(
            store = store(),
            transactions = { listOf("closing-txid" to listOf(funding)) },
            // The channel is no longer open, which is what makes the scan run.
            openChannelFundingTxIds = { emptySet() },
        ).record()

        assertEquals("closing-txid", recorded)
        assertEquals(listOf("closing-txid"), store().closureTxIds())
        assertNull("Watched no longer — the closure has been found.", store().channelFundingOutpoint())
    }
}
