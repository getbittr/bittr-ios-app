package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.seedStateDirectory
import java.io.File
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **The ordering: quarantine first, blob second. Never the other way.**
 *
 * `storeMnemonic` quarantines before it persists and throws out of the whole
 * function on a quarantine failure (`CacheManager.swift:351–359`), so no
 * mnemonic is stored over state that could not be made safe. On iOS that reads
 * as tidy error handling — the path fires at most once, in a migration. On
 * Android, where process death mid-operation is routine, it is the difference
 * between a recoverable interruption and an unrecoverable one:
 *
 * - crash **after** quarantine, **before** the blob write → next launch sees
 *   no mnemonic and no state. Clean; the user restores again.
 * - crash **after** the blob write, **before** quarantine → a mnemonic now
 *   exists, so the guard's first branch returns early on **every** subsequent
 *   launch. Foreign state is live under a new seed and the guard can never
 *   fire again.
 *
 * The second row is why the reverse order cannot be traded for anything. These
 * tests inject a failure at each point and assert the guard still reaches the
 * right conclusion on the next start.
 */
class QuarantineOrderingCrashTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    private lateinit var fixture: WalletFixture

    @Before
    fun setUp() {
        fixture = WalletFixture(temporaryFolder.root)
    }

    @Test
    fun `a crash after quarantine and before the blob write leaves a clean device`() {
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "foreign")

        // "Crash": the blob write throws after the guard has already moved the
        // state aside.
        fixture.codec.wrapFailure = { IOException("process died mid-write") }
        assertThrows(IOException::class.java) { fixture.importer.import(Mnemonics.OTHER) }

        // Next launch.
        fixture.codec.wrapFailure = null
        assertEquals(
            "No mnemonic was stored, so the device must present as fresh.",
            MnemonicPresence.NoUsableMnemonic,
            fixture.vault.presence(),
        )
        assertFalse(
            "The foreign state was already moved aside and must stay aside — the " +
                "quarantine is fsync'd before the blob write is attempted.",
            fixture.stateStore.hasLightningState(),
        )
        assertEquals(1, fixture.stateStore.quarantines().size)

        val retried = fixture.importer.import(Mnemonics.OTHER)
        assertFalse(retried.alreadyProvisioned)
        assertEquals(Mnemonics.OTHER, fixture.vault.read())
    }

    @Test
    fun `a failed quarantine prevents the seed from being stored at all`() {
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "foreign")

        // Make the quarantine impossible: a plain file where the quarantine
        // root has to be a directory.
        fixture.paths.quarantineRoot.parentFile!!.mkdirs()
        fixture.paths.quarantineRoot.writeText("not a directory")

        assertThrows(SeedImportAbortedException::class.java) {
            fixture.importer.import(Mnemonics.OTHER)
        }

        assertEquals(
            "Storing the mnemonic here would make the guard return early forever, " +
                "leaving foreign state live under a new seed. iOS throws out of the " +
                "whole function for the same reason (CacheManager.swift:355).",
            MnemonicPresence.NoUsableMnemonic,
            fixture.vault.presence(),
        )
        assertTrue(
            "And the state must still be there — quarantine never deletes, and a " +
                "quarantine that could not happen must not have half-happened.",
            fixture.stateStore.hasLightningState(),
        )
    }

    @Test
    fun `a crash after the blob write leaves the discriminator recoverable`() {
        // The remaining window is between the blob write and the discriminator
        // write. It is deliberately the harmless one: an unwritten
        // discriminator reads as `absent`, which quarantines on the next
        // import — a denial of service, never a fund loss, because quarantine
        // never deletes.
        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)
        assertTrue(result.discriminatorRecorded)

        fixture.paths.discriminatorFile.delete()
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "state-with-lost-discriminator")
        fixture.destroySeedBlob()
        fixture.allowReads()

        val afterLoss = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertNotNull(
            "Losing the discriminator degrades to today's iOS behaviour — quarantine " +
                "— which is exactly what keeps BIT-8 rule 1 intact: nothing new is " +
                "secret or irreplaceable.",
            afterLoss.quarantineDirectory,
        )
        assertEquals(
            "state-with-lost-discriminator",
            File(afterLoss.quarantineDirectory!!, "ldk_node_data.sqlite").readText(),
        )
        assertTrue(
            "And the wallet itself still comes back from the mnemonic.",
            afterLoss.discriminatorRecorded,
        )
        assertEquals(Mnemonics.IOS_VECTOR, fixture.vault.read())
    }
}
