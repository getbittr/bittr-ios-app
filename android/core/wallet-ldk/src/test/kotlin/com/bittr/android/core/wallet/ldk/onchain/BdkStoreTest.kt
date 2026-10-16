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
 * The kept store, its recreate, and the fence that stops a delete reaching the seed.
 *
 * The first tests are the ported behaviour: `Connection.open()` keeps the stored
 * wallet, `Connection.recreate()` throws it away, and the creation time stands in
 * for the database file's creation date. The rest are the fence, and they are the
 * reason this class matters: the iOS delete is safe on iOS *because of a directory
 * layout*, and the port had the wrong layout until the delete was fenced.
 */
class BdkStoreTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private fun paths() = WalletPaths(temporaryFolder.newFolder("no_backup"))

    @Test
    fun `open creates the store directory and returns the database path`() {
        val paths = paths()
        val returned = BdkStore.open(paths.bdkDatabaseFile)

        assertEquals(paths.bdkDatabaseFile, returned)
        assertTrue("The store directory must exist afterwards", paths.bdkStoreDir.isDirectory)
    }

    @Test
    fun `open keeps an existing store, so the stored wallet can load`() {
        val paths = paths()
        paths.bdkStoreDir.mkdirs()
        paths.bdkDatabaseFile.writeText("stored chain data")

        BdkStore.open(paths.bdkDatabaseFile)

        assertEquals("stored chain data", paths.bdkDatabaseFile.readText())
    }

    @Test
    fun `recreate deletes an existing store, sidecars included`() {
        val paths = paths()
        paths.bdkStoreDir.mkdirs()
        paths.bdkDatabaseFile.writeText("stale chain data")
        File(paths.bdkStoreDir, "bdk_wallet.sqlite-wal").writeText("stale wal")

        BdkStore.recreate(paths.bdkDatabaseFile)

        assertFalse("The old database must be gone", paths.bdkDatabaseFile.exists())
        assertEquals(
            "SQLite sidecars must go with it — a -wal left beside a deleted " +
                "database is how SQLite reopens onto a half-state.",
            listOf(BdkStore.CREATED_AT_FILE),
            paths.bdkStoreDir.list()?.toList() ?: emptyList<String>(),
        )
    }

    @Test
    fun `delete removes the whole store directory`() {
        val paths = paths()
        BdkStore.open(paths.bdkDatabaseFile)
        paths.bdkDatabaseFile.writeText("removed wallet's history")

        BdkStore.delete(paths.bdkDatabaseFile)

        assertFalse(paths.bdkStoreDir.exists())
    }

    @Test
    fun `the creation time is recorded by a recreate and kept by later opens`() {
        val paths = paths()
        val before = System.currentTimeMillis() / 1000
        BdkStore.recreate(paths.bdkDatabaseFile)
        paths.bdkDatabaseFile.writeText("database")
        val created = BdkStore.creationEpochSeconds(paths.bdkDatabaseFile)!!
        assertTrue(created >= before)

        File(paths.bdkStoreDir, BdkStore.CREATED_AT_FILE).writeText("1000")
        BdkStore.open(paths.bdkDatabaseFile)

        assertEquals("an open must not move the creation time", 1000L, BdkStore.creationEpochSeconds(paths.bdkDatabaseFile))
    }

    @Test
    fun `a store with no recorded creation time counts as created at its first open`() {
        val paths = paths()
        paths.bdkStoreDir.mkdirs()
        paths.bdkDatabaseFile.writeText("database from an older build")
        assertEquals(null, BdkStore.creationEpochSeconds(paths.bdkDatabaseFile))

        val before = System.currentTimeMillis() / 1000
        BdkStore.open(paths.bdkDatabaseFile)

        assertTrue(BdkStore.creationEpochSeconds(paths.bdkDatabaseFile)!! >= before)
    }

    @Test
    fun `there is no creation time without a database`() {
        val paths = paths()
        BdkStore.recreate(paths.bdkDatabaseFile)

        assertEquals(null, BdkStore.creationEpochSeconds(paths.bdkDatabaseFile))
    }

    @Test
    fun `recreate does not touch the seed blob, the LDK state or a quarantine`() {
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

        BdkStore.recreate(paths.bdkDatabaseFile)
        BdkStore.delete(paths.bdkDatabaseFile)

        assertTrue("The seed blob must survive a BDK store wipe", paths.seedBlobFile.exists())
        assertEquals("wrapped seed blob", paths.seedBlobFile.readText())
        assertTrue("Channel state must survive", channelState.exists())
        assertTrue("The BIT-20 discriminator must survive", paths.discriminatorFile.exists())
        assertTrue("A prior quarantine must survive", priorQuarantine.isDirectory)
    }

    @Test
    fun `the store refuses a database sited directly in the wallet directory`() {
        // The layout that existed before `bdkStoreDir`. It must fail loudly
        // rather than wipe `walletDir`.
        val paths = paths()
        paths.createDirectories()
        paths.seedBlobFile.writeText("wrapped seed blob")

        val misSited = File(paths.walletDir, "bdk_wallet.sqlite")
        val failure = assertThrows(IllegalArgumentException::class.java) {
            BdkStore.recreate(misSited)
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
    fun `the store refuses the LDK state directory itself`() {
        val paths = paths()
        paths.createDirectories()
        val channelState = File(paths.ldkStateDir, "ldk_node_data.sqlite")
        channelState.writeText("channel monitors")

        assertThrows(IllegalArgumentException::class.java) {
            BdkStore.delete(File(paths.ldkStateDir, "bdk_wallet.sqlite"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            BdkStore.open(File(paths.ldkStateDir, "bdk_wallet.sqlite"))
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

    /** An unreadable creation time would otherwise force a full scan on every launch. */
    @Test
    fun `an unreadable creation time is written again`() {
        val paths = paths()
        BdkStore.open(paths.bdkDatabaseFile)
        paths.bdkDatabaseFile.writeText("database")
        File(paths.bdkStoreDir, BdkStore.CREATED_AT_FILE).writeText("not a number")

        BdkStore.open(paths.bdkDatabaseFile)

        assertTrue(BdkStore.creationEpochSeconds(paths.bdkDatabaseFile) != null)
    }

    @Test
    fun `delete refuses a store directory that is a symbolic link`() {
        val paths = paths()
        paths.createDirectories()
        paths.bdkStoreDir.deleteRecursively()
        val elsewhere = temporaryFolder.newFolder("elsewhere")
        val kept = File(elsewhere, "kept").apply { writeText("kept") }
        java.nio.file.Files.createSymbolicLink(paths.bdkStoreDir.toPath(), elsewhere.toPath())

        assertThrows(IllegalArgumentException::class.java) { BdkStore.delete(paths.bdkDatabaseFile) }

        assertTrue(kept.exists())
    }
}
