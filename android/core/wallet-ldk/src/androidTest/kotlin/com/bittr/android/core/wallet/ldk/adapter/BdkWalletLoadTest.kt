package com.bittr.android.core.wallet.ldk.adapter

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.core.wallet.ldk.onchain.BdkScanRecord
import com.bittr.android.core.wallet.ldk.onchain.BdkStore
import org.bitcoindevkit.KeychainKind
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * `didStartBDK()` against the real library — the Android half of iOS's
 * `BDKWalletLoadTests` (PR #99).
 *
 * `BdkWalletOpenerTest` proves the decision tree on the JVM. What only the native
 * library can answer is whether its errors land where the tree expects them: that
 * `Wallet.load` refuses another seed's database, reports an empty one as nothing
 * stored, and that a file which isn't a database is recognised as corrupt.
 *
 * Every database here is a throwaway file under the instrumentation's cache
 * directory. Nothing touches the app's wallet.
 */
@RunWith(AndroidJUnit4::class)
class BdkWalletLoadTest {

    // Public BIP39 test vectors, chosen so neither is anyone's wallet.
    private val seedA = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private val seedB = "legal winner thank year wave sausage worth useful legal winner thank yellow"

    private lateinit var root: File
    private lateinit var databaseFile: File

    private class FakeRecord : BdkScanRecord {
        var fullScanStored = false
        override var rebuildRequested = false
        override val hasStoredFullScan: Boolean get() = fullScanStored
        override fun storeFullScanCompletion() { fullScanStored = true }
        override fun clearFullScanCompletion() { fullScanStored = false }
        override fun requestRebuild() { rebuildRequested = true; fullScanStored = false }
        override fun clearRebuildRequest() { rebuildRequested = false }
    }

    @Before
    fun setUp() {
        val cache = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir
        root = File(cache, "bdk-load-test-${System.nanoTime()}")
        databaseFile = File(File(root, BdkStore.EXPECTED_DIR_NAME), "bdk_wallet.sqlite")
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun open(seed: String, record: BdkScanRecord = FakeRecord(), log: MutableList<String> = mutableListOf()) =
        BdkWalletFactory.open(
            mnemonic = seed,
            network = WalletNetwork.Testnet,
            databaseFile = databaseFile,
            record = record,
            topPoolIndex = { null },
            log = { log += it },
            onError = { _, _ -> },
        )

    private fun BdkWallet.firstAddress(): String {
        val info = wallet.peekAddress(KeychainKind.EXTERNAL, 0u)
        return try {
            info.address.use { it.toString() }
        } finally {
            info.destroy()
        }
    }

    @Test
    fun the_same_seed_loads_its_stored_wallet_with_its_revealed_addresses() {
        open(seedA).use { created ->
            created.wallet.revealAddressesTo(KeychainKind.EXTERNAL, 5u).forEach { it.destroy() }
            created.wallet.persist(created.connection)
        }

        val log = mutableListOf<String>()
        open(seedA, log = log).use { loaded ->
            assertTrue(log.toString(), "Did load the stored BDK wallet." in log)
            // Revealing to the index already persisted produces nothing new, which it only
            // can if the revealed index survived. That is what makes a light sync enough.
            assertEquals(0, loaded.wallet.revealAddressesTo(KeychainKind.EXTERNAL, 5u).size)
        }
    }

    @Test
    fun an_empty_database_builds_a_new_wallet() {
        val log = mutableListOf<String>()
        open(seedA, log = log).close()

        assertTrue(log.toString(), "No stored BDK wallet to load (nothing stored). Creating one." in log)
    }

    /** The load-bearing one: a load against someone else's history would report the wrong balance. */
    @Test
    fun another_seeds_database_is_replaced_rather_than_loaded() {
        val addressA = open(seedA).use { it.firstAddress() }

        val log = mutableListOf<String>()
        val record = FakeRecord().apply { fullScanStored = true }
        open(seedB, record, log).use { replaced ->
            assertNotEquals(addressA, replaced.firstAddress())
            assertEquals(0uL, replaced.wallet.balance().total.toSat())
        }
        assertTrue(log.toString(), "No stored BDK wallet to load (stored data did not match). Creating one." in log)
        assertFalse("the other seed's scan no longer stands", record.fullScanStored)
    }

    @Test
    fun a_file_that_is_not_a_database_is_replaced() {
        databaseFile.parentFile!!.mkdirs()
        databaseFile.writeBytes(ByteArray(4096) { 0x42 })

        val log = mutableListOf<String>()
        open(seedA, log = log).close()

        // BDK reports the junk either on opening the connection or on loading from it.
        // Both count as corrupt, and either way a new wallet is built.
        assertTrue(log.toString(), log.any { it.startsWith("No stored BDK wallet to load") })
        assertNotEquals("a new database replaced the junk", 0x42.toByte(), databaseFile.readBytes().first())
    }

    @Test
    fun a_requested_rebuild_starts_from_an_empty_database() {
        open(seedA).use { created ->
            created.wallet.revealAddressesTo(KeychainKind.EXTERNAL, 5u).forEach { it.destroy() }
            created.wallet.persist(created.connection)
        }

        val record = FakeRecord().apply { rebuildRequested = true }
        open(seedA, record).use { rebuilt ->
            assertEquals("nothing revealed survived", 6, rebuilt.wallet.revealAddressesTo(KeychainKind.EXTERNAL, 5u).size)
        }
        assertFalse(record.rebuildRequested)
    }
}
