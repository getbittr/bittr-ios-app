package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.seedStateDirectory
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * **BIT-8 rule 3 — the Keystore-wrapped blob is a cache, never the only copy.**
 *
 * This is the test the definition of done specifically asks for: the app still
 * recovers after the Keystore blob is destroyed. Until BIT-20 it was
 * unwritable, because the correct final assertion differed between the two
 * candidate designs. It is now fully specified, and both rows are here.
 *
 * | case | setup | assertion |
 * |---|---|---|
 * | own seed | destroy the alias **and** the blob; leave state and discriminator | restore succeeds, same account, **channel state retained**, discriminator unchanged |
 * | foreign seed | same, but a different mnemonic | state quarantined into a fresh, uniquely-named subdirectory; prior quarantines still present |
 *
 * A third row is added here that the spec did not have to spell out, because
 * it only exists on Android: the wrapping key invalidated while the blob is
 * still on disk. It matters because `KeyPermanentlyInvalidatedException` is
 * raised on *encrypt* as well as decrypt, so a codec that does not replace the
 * dead key makes the restore path itself fail — turning rule 3's routine case
 * into loss of access.
 *
 * The first row is the one that does not exist on iOS. Ported literally, the
 * guard would infer "no mnemonic ⇒ foreign" and quarantine the user's own
 * channels — leaving them in exactly the position `LightningStorage.swift:84`
 * warns about, needing the quarantined file to sweep a force-close.
 */
@RunWith(RobolectricTestRunner::class)
class BlobDestroyedRecoversTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    private lateinit var fixture: WalletFixture

    @Before
    fun setUp() {
        fixture = WalletFixture(temporaryFolder.root)
    }

    @Test
    fun `the users own mnemonic recovers the channel state, unquarantined`() {
        // A wallet that has been running: seed installed, channels open.
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "live-channel-monitor")
        val discriminatorBefore = fixture.paths.discriminatorFile.readText()

        // The Keystore blob is lost. Not an uninstall — the state directory
        // survives, which is the whole point of the case.
        fixture.destroySeedBlob()
        fixture.allowReads()

        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertTrue(
            "The user's own state must be kept. Quarantining here is the misfire " +
                "BIT-20 exists to prevent: it degrades 'restore from mnemonic' to an " +
                "on-chain-only sweep and strands the channel balance.",
            result.keptExistingState,
        )
        assertNull("Nothing should have been quarantined.", result.quarantineDirectory)
        assertTrue(fixture.stateStore.quarantines().isEmpty())
        assertEquals(
            "live-channel-monitor",
            File(fixture.paths.ldkStateDir, "ldk_node_data.sqlite").readText(),
        )
        assertEquals(
            "The discriminator describes the same seed, so it must not change.",
            discriminatorBefore,
            fixture.paths.discriminatorFile.readText(),
        )
        assertEquals(
            "The mnemonic must be readable again after the restore.",
            Mnemonics.IOS_VECTOR,
            fixture.vault.read(),
        )
    }

    @Test
    fun `an invalidated wrapping key still allows a restore`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "live-channel-monitor")

        // The blob is still on disk; the key that reads it is gone. This is the
        // case BIT-18/K1 measures the likelihood of, and rule 2's non-auth-bound
        // key is what should make it rare — but "rare" is not "impossible", and
        // the recovery has to work when it happens.
        fixture.codec.keyInvalidated = true

        assertEquals(
            MnemonicPresence.NoUsableMnemonic,
            fixture.vault.presence(),
        )

        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertTrue(
            "A dead wrapping key must not make the restore path unreachable. " +
                "KeyPermanentlyInvalidatedException is raised on encrypt too, so a " +
                "codec that does not replace the key turns 'restore from mnemonic' " +
                "into 'cannot restore' — loss of access, not loss of a cache.",
            result.keptExistingState,
        )
        assertEquals(Mnemonics.IOS_VECTOR, fixture.vault.read())
        assertTrue(fixture.stateStore.quarantines().isEmpty())
        assertEquals(
            "live-channel-monitor",
            File(fixture.paths.ldkStateDir, "ldk_node_data.sqlite").readText(),
        )
    }

    @Test
    fun `a different mnemonic quarantines into a fresh subdirectory`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "someone-elses-channel")

        fixture.destroySeedBlob()
        fixture.allowReads()

        val result = fixture.importer.import(Mnemonics.OTHER)

        assertFalse(result.keptExistingState)
        assertNotNull(
            "Importing a seed that does not own the state on disk is the loss-of-funds " +
                "path the iOS guard exists to prevent (CacheManager.swift:353–354).",
            result.quarantineDirectory,
        )
        assertEquals(
            "someone-elses-channel",
            File(result.quarantineDirectory!!, "ldk_node_data.sqlite").readText(),
        )
        assertFalse(
            "State must not remain where the node would pick it up under the new seed.",
            fixture.stateStore.hasLightningState(),
        )
        assertEquals(
            "The discriminator must now describe the newly imported seed.",
            fixture.discriminatorStore.read(),
            com.bittr.android.core.wallet.ldk.state.DiscriminatorRecord.Present(
                com.bittr.android.core.wallet.ldk.state.SeedDiscriminator.compute(
                    com.bittr.android.core.wallet.ldk.bip.Bip84Account
                        .accountXpub(Mnemonics.OTHER, mainnet = false),
                ),
            ),
        )
    }

    @Test
    fun `a second foreign import does not destroy the first quarantine`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "first")
        fixture.destroySeedBlob()
        fixture.allowReads()
        val first = fixture.importer.import(Mnemonics.OTHER).quarantineDirectory

        seedStateDirectory(fixture.paths.ldkStateDir, marker = "second")
        fixture.destroySeedBlob()
        fixture.allowReads()
        val second = fixture.importer.import(Mnemonics.IOS_VECTOR).quarantineDirectory

        assertNotNull(first)
        assertNotNull(second)
        assertEquals("first", File(first!!, "ldk_node_data.sqlite").readText())
        assertEquals("second", File(second!!, "ldk_node_data.sqlite").readText())
        assertEquals(2, fixture.stateStore.quarantines().size)
    }

    @Test
    fun `importing over a live wallet touches nothing`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "live")

        val result = fixture.importer.import(Mnemonics.OTHER)

        assertTrue(
            "iOS returns early when a mnemonic already exists (CacheManager.swift:363). " +
                "So do we — and in particular the existing seed is not replaced.",
            result.alreadyProvisioned,
        )
        assertEquals(Mnemonics.IOS_VECTOR, fixture.vault.read())
        assertEquals("live", File(fixture.paths.ldkStateDir, "ldk_node_data.sqlite").readText())
        assertTrue(fixture.stateStore.quarantines().isEmpty())
    }
}
