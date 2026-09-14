package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.onchain.BdkStore
import com.bittr.android.core.wallet.ldk.state.LdkStateStore
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **Where the cache sits is the decision; this is the decision being used.**
 *
 * Both of the cache's neighbours under `no_backup/wallet/` have destructive
 * lifecycles, and an event ledger inside either of them would look correct in
 * every other test in this module:
 *
 * - `LdkStateStore.quarantineLightningState()` **moves** `ldk_state/` wholesale
 *   when a foreign-seed import is detected (BIT-20 rule 4). A ledger under it
 *   would forget every handled event at exactly the moment the app is most
 *   confused about which wallet it is.
 * - `BdkStore.prepare()` **deletes** `bdk_store/` in full on every start, ported
 *   from iOS. A ledger under it would forget everything once per process.
 *
 * Neither failure would show up as an error. Both would show up as the user
 * being notified twice about one payment, and as a force-close whose sweep
 * transaction has no label — which is why the siting gets a test rather than a
 * comment.
 */
class CacheSurvivesStateLifecyclesTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var paths: WalletPaths
    private lateinit var cache: FileWalletCache

    @Before
    fun setUp() {
        paths = WalletPaths(temporaryFolder.newFolder("no_backup"))
        paths.createDirectories()
        cache = FileWalletCache(paths.cacheDir)
        cache.put(CachedEventLedger.KEY, listOf("PaymentReceived(hash=abc)"))
        cache.put(CachedChannelClosureStore.KEY_CLOSURE_TX_IDS, listOf("closure-txid"))
    }

    @Test
    fun `a quarantine of the LDK state leaves the cache untouched`() {
        File(paths.ldkStateDir, "ldk_node_data.sqlite").writeText("channel state")

        assertNotNull(
            "Nothing was quarantined, so this test is asserting about an event that " +
                "did not happen.",
            LdkStateStore(paths).quarantineLightningState(),
        )

        assertEquals(
            listOf("PaymentReceived(hash=abc)"),
            FileWalletCache(paths.cacheDir).strings(CachedEventLedger.KEY),
        )
        assertEquals(
            listOf("closure-txid"),
            FileWalletCache(paths.cacheDir).strings(CachedChannelClosureStore.KEY_CLOSURE_TX_IDS),
        )
    }

    @Test
    fun `clearing BDK's store on start leaves the cache untouched`() {
        paths.bdkDatabaseFile.writeText("bdk chain data")

        BdkStore.prepare(paths.bdkDatabaseFile)

        assertFalse("The BDK store really was cleared.", paths.bdkDatabaseFile.exists())
        assertEquals(
            listOf("PaymentReceived(hash=abc)"),
            FileWalletCache(paths.cacheDir).strings(CachedEventLedger.KEY),
        )
    }

    /**
     * The structural half, so a future move is caught before its consequences
     * are: the cache is a sibling of the two, not a child of either.
     */
    @Test
    fun `the cache directory is a sibling of the state and store directories`() {
        assertEquals(paths.walletDir, paths.cacheDir.parentFile)
        assertFalse(paths.cacheDir.canonicalFile.startsWith(paths.ldkStateDir.canonicalFile))
        assertFalse(paths.cacheDir.canonicalFile.startsWith(paths.bdkStoreDir.canonicalFile))
    }
}
