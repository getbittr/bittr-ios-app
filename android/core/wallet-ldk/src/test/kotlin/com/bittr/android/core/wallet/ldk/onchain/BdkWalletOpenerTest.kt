package com.bittr.android.core.wallet.ldk.onchain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `didStartBDK()`'s store and wallet half (PR #99), driven on the JVM with no BDK.
 *
 * What is asserted is iOS's decision tree: when the stored wallet is loaded, when the
 * database is thrown away and a new wallet built, and when the file is left for the
 * next launch. Whether `Wallet.load` itself refuses another seed's database is a
 * property of the library; iOS's `BDKWalletLoadTests` settled it.
 */
class BdkWalletOpenerTest {

    private class Failure(val kind: String) : Exception(kind)

    /** A recording [BdkOpenPort] over strings. */
    private class FakePort : BdkOpenPort<String, String> {
        val calls = mutableListOf<String>()
        var stores = 0

        var openFailure: Failure? = null
        var recreateFailure: Failure? = null
        var loadFailure: Failure? = null
        var createFailure: Failure? = null
        var onThisNetwork = true

        override fun openStore(): String {
            calls += "openStore"
            openFailure?.let { throw it }
            return "store-${++stores}"
        }

        override fun recreateStore(): String {
            calls += "recreateStore"
            recreateFailure?.let { throw it }
            return "store-${++stores}"
        }

        override fun closeStore(store: String) {
            calls += "closeStore($store)"
        }

        override fun load(store: String): String {
            calls += "load($store)"
            loadFailure?.let { throw it }
            return "loaded-from-$store"
        }

        override fun isOnThisNetwork(wallet: String) = onThisNetwork

        override fun closeWallet(wallet: String) {
            calls += "closeWallet($wallet)"
        }

        override fun create(store: String): String {
            calls += "create($store)"
            createFailure?.let { throw it }
            return "created-in-$store"
        }

        override fun revealTo(wallet: String, store: String, index: Int) {
            calls += "revealTo($index)"
        }

        override fun isCorruptDatabase(failure: Throwable) = (failure as? Failure)?.kind == "corrupt"

        override fun nothingToLoadReason(failure: Throwable): String? = when ((failure as? Failure)?.kind) {
            "couldNotLoad" -> "nothing stored"
            "invalidChangeSet" -> "stored data did not match"
            else -> null
        }
    }

    private class FakeRecord : BdkScanRecord {
        var fullScanStored = true
        override var rebuildRequested = false
        override val hasStoredFullScan: Boolean get() = fullScanStored
        override fun storeFullScanCompletion() { fullScanStored = true }
        override fun clearFullScanCompletion() { fullScanStored = false }
        override fun requestRebuild() { rebuildRequested = true; fullScanStored = false }
        override fun clearRebuildRequest() { rebuildRequested = false }
    }

    private val port = FakePort()
    private val record = FakeRecord()
    private var topPoolIndex: Int? = null

    private fun opener() = BdkWalletOpener(port, record, topPoolIndex = { topPoolIndex })

    @Test
    fun `the stored wallet is loaded and its full scan kept`() {
        val opened = opener().open()

        assertEquals("loaded-from-store-1", opened.wallet)
        assertTrue(opened.loaded)
        assertEquals(listOf("openStore", "load(store-1)"), port.calls)
        assertTrue(record.fullScanStored)
    }

    @Test
    fun `nothing stored builds a new wallet in a new database`() {
        port.loadFailure = Failure("couldNotLoad")

        val opened = opener().open()

        assertEquals("created-in-store-2", opened.wallet)
        assertEquals("store-2", opened.store)
        assertFalse(opened.loaded)
        assertEquals(
            listOf("openStore", "load(store-1)", "closeStore(store-1)", "recreateStore", "create(store-2)"),
            port.calls,
        )
        assertFalse(record.fullScanStored)
    }

    /** Another seed's database is the InvalidChangeSet case. */
    @Test
    fun `stored data that does not match is replaced`() {
        port.loadFailure = Failure("invalidChangeSet")

        assertEquals("created-in-store-2", opener().open().wallet)
        assertFalse(record.fullScanStored)
    }

    @Test
    fun `a wallet stored on another network is replaced`() {
        port.onThisNetwork = false

        val opened = opener().open()

        assertEquals("created-in-store-2", opened.wallet)
        assertTrue("the loaded one is released", "closeWallet(loaded-from-store-1)" in port.calls)
    }

    @Test
    fun `a corrupt database found on load is replaced`() {
        port.loadFailure = Failure("corrupt")

        assertEquals("created-in-store-2", opener().open().wallet)
    }

    /** A read failure may pass, so the file is kept for the next launch. */
    @Test
    fun `any other load failure keeps the database and fails the start`() {
        port.loadFailure = Failure("busy")

        assertThrows(Failure::class.java) { opener().open() }

        assertFalse("nothing is deleted", "recreateStore" in port.calls)
        assertEquals("closeStore(store-1)", port.calls.last())
        assertTrue("the stored scan still stands", record.fullScanStored)
    }

    @Test
    fun `a corrupt database found on open is replaced by an empty one`() {
        port.openFailure = Failure("corrupt")
        port.loadFailure = Failure("couldNotLoad")

        val opened = opener().open()

        assertEquals("created-in-store-2", opened.wallet)
        assertEquals("openStore", port.calls.first())
        assertEquals("recreateStore", port.calls[1])
        assertFalse(record.fullScanStored)
    }

    @Test
    fun `any other open failure keeps the database and fails the start`() {
        port.openFailure = Failure("locked")

        assertThrows(Failure::class.java) { opener().open() }

        assertEquals(listOf("openStore"), port.calls)
        assertTrue(record.fullScanStored)
    }

    @Test
    fun `a requested rebuild starts from an empty database, and is done once a wallet is built`() {
        record.rebuildRequested = true
        port.loadFailure = Failure("couldNotLoad")

        val opened = opener().open()

        assertEquals("recreateStore", port.calls.first())
        assertFalse(opened.loaded)
        assertFalse(record.rebuildRequested)
    }

    @Test
    fun `a rebuild that could not build the wallet stays requested`() {
        record.rebuildRequested = true
        port.loadFailure = Failure("couldNotLoad")
        port.createFailure = Failure("create")

        assertThrows(Failure::class.java) { opener().open() }

        assertTrue(record.rebuildRequested)
        assertEquals("closeStore(store-2)", port.calls.last())
    }

    /** A new wallet has revealed nothing, so the cached pool is revealed again, and five beyond. */
    @Test
    fun `a new wallet reveals the cached address pool again`() {
        port.loadFailure = Failure("couldNotLoad")
        topPoolIndex = 7

        opener().open()

        assertEquals("revealTo(12)", port.calls.last())
    }

    @Test
    fun `a new wallet with no cached pool reveals nothing`() {
        port.loadFailure = Failure("couldNotLoad")

        opener().open()

        assertFalse(port.calls.any { it.startsWith("revealTo") })
    }

    @Test
    fun `a loaded wallet reveals nothing`() {
        topPoolIndex = 7

        opener().open()

        assertFalse(port.calls.any { it.startsWith("revealTo") })
    }

    @Test
    fun `a failed recreate after a corrupt open fails the start`() {
        port.openFailure = Failure("corrupt")
        port.recreateFailure = Failure("disk")

        val failure = assertThrows(Failure::class.java) { opener().open() }

        assertEquals("disk", failure.kind)
    }
}
