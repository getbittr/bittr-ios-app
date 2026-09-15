package com.bittr.android.core.wallet.ldk.host

import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WalletResyncTest {

    private val calls = mutableListOf<String>()
    private var synced = true

    private fun TestScope.resync(
        node: () -> Unit = { calls += "node" },
        onchain: suspend () -> Boolean = { calls += "onchain"; true },
        read: () -> Boolean = { calls += "read"; true },
    ) = WalletResync(
        scope = this,
        canResync = { synced },
        markResyncing = { calls += "mark" },
        endResync = { calls += "end" },
        syncNode = node,
        syncOnchain = onchain,
        readNow = read,
        onchainTimeoutMillis = 5_000,
    )

    @Test
    fun `a pull hides the wallet at once, then syncs the node and the on-chain wallet, and ends`() = runTest {
        val resync = resync()

        assertTrue(resync.refresh())
        assertEquals(listOf("mark"), calls)
        assertTrue(resync.isRefreshing.value)

        advanceUntilIdle()
        assertEquals(listOf("mark", "node", "onchain", "end"), calls)
        assertFalse(resync.isRefreshing.value)
    }

    @Test
    fun `no refresh before the wallet has synced`() = runTest {
        synced = false
        assertFalse(resync().refresh())
        advanceUntilIdle()
        assertTrue(calls.isEmpty())
    }

    @Test
    fun `a second pull while one is running is ignored`() = runTest {
        val resync = resync()
        assertTrue(resync.refresh())
        assertFalse(resync.refresh())
        advanceUntilIdle()
        assertEquals(1, calls.count { it == "mark" })
        assertTrue("a later pull works again", resync.refresh())
    }

    @Test
    fun `a failed node sync still syncs on-chain and ends`() = runTest {
        val failures = mutableListOf<Throwable>()
        val resync = WalletResync(
            scope = this,
            canResync = { true },
            markResyncing = { calls += "mark" },
            endResync = { calls += "end" },
            syncNode = { error("no node") },
            syncOnchain = { calls += "onchain"; true },
            readNow = { calls += "read"; true },
            onFailure = { failures += it },
        )
        resync.refresh()
        advanceUntilIdle()
        assertEquals(listOf("mark", "onchain", "end"), calls)
        assertEquals(1, failures.size)
    }

    @Test
    fun `an on-chain sync that never answers falls back to a direct read`() = runTest {
        val resync = resync(onchain = { awaitCancellation() })
        resync.refresh()
        advanceUntilIdle()
        assertEquals(listOf("mark", "node", "read", "end"), calls)
        assertFalse(resync.isRefreshing.value)
    }

    @Test
    fun `an on-chain sync that published no reading is followed by a direct read`() = runTest {
        val resync = resync(onchain = { calls += "onchain"; false })
        resync.refresh()
        advanceUntilIdle()
        assertEquals(listOf("mark", "node", "onchain", "read", "end"), calls)
    }
}
