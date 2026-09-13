package com.bittr.android.core.wallet.ldk.onchain

import com.bittr.android.core.wallet.ldk.state.WalletPaths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * The wipe-per-start, and the fence that stops it reaching the seed.
 *
 * The first two tests are the ported behaviour. The rest are the fence, and they
 * are the reason this class matters: the iOS line being ported is safe on iOS
 * *because of a directory layout*, and the port had the wrong layout until the
 * delete was written down and fenced.
 */
class BdkStoreTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private fun paths() = WalletPaths(temporaryFolder.newFolder("no_backup"))

    @Test
    fun `prepare leaves an empty store directory and returns the database path`() {
        val paths = paths()
        val returned = BdkStore.prepare(paths.bdkDatabaseFile)

        assertEquals(paths.bdkDatabaseFile, returned)
        assertTrue("The store directory must exist afterwards", paths.bdkStoreDir.isDirectory)
        assertEquals(
            "A fresh store directory must be empty",
            emptyList<String>(),
            paths.bdkStoreDir.list()?.toList() ?: emptyList<String>(),
        )
    }

    @Test
    fun `prepare deletes an existing store, which is what forces the full scan`() {
        val paths = paths()
        paths.bdkStoreDir.mkdirs()
        paths.bdkDatabaseFile.writeText("stale chain data")
        File(paths.bdkStoreDir, "bdk_wallet.sqlite-wal").writeText("stale wal")

        BdkStore.prepare(paths.bdkDatabaseFile)

        assertFalse("The old database must be gone", paths.bdkDatabaseFile.exists())
        assertEquals(
            "SQLite sidecars must go with it — a -wal left beside a deleted " +
                "database is how SQLite reopens onto a half-state.",
            emptyList<String>(),
            paths.bdkStoreDir.list()?.toList() ?: emptyList<String>(),
        )
    }

    @Test
    fun `prepare does not touch the seed blob, the LDK state or a quarantine`() {
        // The fund-loss case. If the BDK database ever sits next to these again,
        // the recursive delete above destroys the user's only on-device copy of
        // the seed and every channel state they have.
        val paths = paths()
        paths.createDirectories()
        paths.quarantineRoot.mkdirs()

        paths.seedBlobFile.writeText("wrapped seed blob")
        val channelState = File(paths.ldkStateDir, "ldk_node_data.sqlite")
        channelState.writeText("channel monitors")
        paths.discriminatorFile.writeText("discriminator")
        val priorQuarantine = File(paths.quarantineRoot, "foreign-1").also { it.mkdirs() }

        BdkStore.prepare(paths.bdkDatabaseFile)

        assertTrue("The seed blob must survive a BDK store wipe", paths.seedBlobFile.exists())
        assertEquals("wrapped seed blob", paths.seedBlobFile.readText())
        assertTrue("Channel state must survive", channelState.exists())
        assertTrue("The BIT-20 discriminator must survive", paths.discriminatorFile.exists())
        assertTrue("A prior quarantine must survive", priorQuarantine.isDirectory)
    }

    @Test
    fun `prepare refuses a database sited directly in the wallet directory`() {
        // The layout that existed before `bdkStoreDir`. It must fail loudly
        // rather than wipe `walletDir`.
        val paths = paths()
        paths.createDirectories()
        paths.seedBlobFile.writeText("wrapped seed blob")

        val misSited = File(paths.walletDir, "bdk_wallet.sqlite")
        val failure = assertThrows(IllegalArgumentException::class.java) {
            BdkStore.prepare(misSited)
        }

        assertTrue(
            "The message should name the directory it refused: ${failure.message}",
            failure.message!!.contains(BdkStore.EXPECTED_DIR_NAME),
        )
        assertTrue(
            "Refusing must not have deleted anything on the way out",
            paths.seedBlobFile.exists() && paths.ldkStateDir.isDirectory,
        )
    }

    @Test
    fun `prepare refuses the LDK state directory itself`() {
        val paths = paths()
        paths.createDirectories()
        val channelState = File(paths.ldkStateDir, "ldk_node_data.sqlite")
        channelState.writeText("channel monitors")

        assertThrows(IllegalArgumentException::class.java) {
            BdkStore.prepare(File(paths.ldkStateDir, "bdk_wallet.sqlite"))
        }
        assertTrue("Channel state must be intact", channelState.exists())
    }

    @Test
    fun `the fence's expected name matches the path layer's constant`() {
        // BdkStore duplicates the name on purpose — `onchain/` may not depend on
        // `state/`. This is what stops the duplicate drifting into a fence that
        // permits nothing, or permits everything.
        assertEquals(WalletPaths.BDK_STORE_DIR, BdkStore.EXPECTED_DIR_NAME)
    }

    @Test
    fun `the BDK store is not inside the LDK state directory`() {
        // BIT-20 rule 4 quarantines `ldkStateDir` by moving it. BDK's rebuildable
        // cache must not ride along.
        val paths = paths()
        assertFalse(
            "bdkStoreDir must not live under ldkStateDir",
            paths.bdkStoreDir.canonicalPath.startsWith(paths.ldkStateDir.canonicalPath),
        )
    }
}
