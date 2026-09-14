package com.bittr.android.core.wallet.ldk.onchain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChannelClosureScanTest {

    private val funding = TxOutpoint(txId = "f".repeat(64), vout = 1u)

    @Test
    fun `no cached funding outpoint means nothing to look for`() {
        assertFalse(ChannelClosureScan.shouldScan(null, emptyList()))
    }

    @Test
    fun `an open channel is not scanned for its own closure`() {
        // Without this guard the scan runs after every sync for the life of the
        // channel, walking every wallet transaction each time.
        assertFalse(ChannelClosureScan.shouldScan(funding, listOf(funding.txId)))
    }

    @Test
    fun `a funding outpoint no longer backing an open channel is scanned`() {
        assertTrue(ChannelClosureScan.shouldScan(funding, listOf("a".repeat(64))))
        assertTrue(ChannelClosureScan.shouldScan(funding, emptyList()))
    }

    @Test
    fun `the transaction spending the funding outpoint is the closure`() {
        val closing = "c".repeat(64)
        val candidates = listOf(
            "d".repeat(64) to listOf(TxOutpoint("e".repeat(64), 0u)),
            closing to listOf(TxOutpoint("9".repeat(64), 3u), funding),
        )
        assertEquals(closing, ChannelClosureScan.findClosingTxId(funding, candidates))
    }

    @Test
    fun `a transaction spending a different vout of the same funding tx is not the closure`() {
        // The case that makes the vout half of the match load-bearing. Output 0 of
        // the funding transaction is ordinary change back to this wallet; output 1
        // funds the channel. Matching on txid alone reports the change-spending
        // transaction as the channel closure, shows the user a closure that has
        // not happened, and clears the cached funding outpoint — so the real
        // closure is never recorded.
        val changeSpend = "b".repeat(64)
        val candidates = listOf(
            changeSpend to listOf(TxOutpoint(funding.txId, vout = 0u)),
        )
        assertNull(
            "Only vout 1 funds this channel; spending vout 0 is not a closure",
            ChannelClosureScan.findClosingTxId(funding, candidates),
        )
    }

    @Test
    fun `no match returns null rather than a wrong txid`() {
        val candidates = listOf(
            "d".repeat(64) to listOf(TxOutpoint("e".repeat(64), 0u)),
        )
        assertNull(ChannelClosureScan.findClosingTxId(funding, candidates))
    }

    @Test
    fun `the first match wins, as iOS's early return does`() {
        val first = "1".repeat(64)
        val second = "2".repeat(64)
        val candidates = listOf(
            first to listOf(funding),
            second to listOf(funding),
        )
        assertEquals(first, ChannelClosureScan.findClosingTxId(funding, candidates))
    }

    @Test
    fun `an empty candidate list is not an error`() {
        // Reachable: BDK's store is wiped on every start (BdkStore), so between
        // start and the first completed full scan `transactions()` is empty.
        assertNull(ChannelClosureScan.findClosingTxId(funding, emptyList()))
    }
}
