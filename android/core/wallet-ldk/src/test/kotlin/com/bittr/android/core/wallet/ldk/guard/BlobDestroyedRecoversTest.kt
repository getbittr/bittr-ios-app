package com.bittr.android.core.wallet.ldk.guard

import android.security.keystore.KeyPermanentlyInvalidatedException
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.wallet.ldk.FakeSeedWrapper
import com.bittr.android.core.wallet.ldk.Vectors
import com.bittr.android.core.wallet.ldk.seed.SeedVault
import com.bittr.android.core.wallet.ldk.storage.WalletPaths
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/**
 * Rule 3's proof: **the wrapped blob is a cache, never the only copy.**
 *
 * Losing the blob must degrade to "restore from mnemonic", never to "funds lost"
 * — and under BIT-20 that now includes keeping the *channels*, not just the
 * on-chain funds. Before BIT-20 this test was unwritable, because the correct
 * final assertion differed between the two candidate designs.
 *
 * The two cases are the whole point, and they must not be collapsed:
 *
 * | Case | Setup | Assertion |
 * |---|---|---|
 * | Own seed | destroy alias + blob, leave state and discriminator | state retained, nothing quarantined |
 * | Foreign seed | same, but a different mnemonic | quarantined into a fresh subdirectory |
 *
 * The own-seed case runs with `matchKeepEnabled = true` because it is testing the
 * *guard logic*, which is what BIT-20 decided. Whether that branch is live in the
 * shipped build is a separate question, gated on the backup exclusion being
 * proven on a device and asserted by [MatchKeepRequiresBackupProofTest].
 */
@RunWith(AndroidJUnit4::class)
class BlobDestroyedRecoversTest {

    @get:Rule val temp = TemporaryFolder()

    private lateinit var paths: WalletPaths
    private lateinit var wrapper: FakeSeedWrapper
    private lateinit var vault: SeedVault

    private fun setUpWalletWithLiveState(): File {
        paths = WalletPaths.forTesting(temp.newFolder("wallet"))
        wrapper = FakeSeedWrapper()
        vault = SeedVault(paths, wrapper)

        // A wallet exists, with channel state and a recorded owner.
        vault.write(Vectors.MNEMONIC_A)
        val channelState = File(paths.ldkStateDir, "channel_monitors.dat")
        channelState.parentFile!!.mkdirs()
        channelState.writeText("live channel state - the force-close sweep material")
        guard(matchKeep = true).recordOwnership(Vectors.ACCOUNT_XPUB_A)
        return channelState
    }

    private fun guard(matchKeep: Boolean) =
        LdkStateGuard(paths, vault, StateQuarantine(paths), matchKeepEnabled = matchKeep)

    /** Exactly the rule-3 scenario: the Keystore lost the key, the state did not. */
    private fun destroyBlobAndKey() {
        wrapper.deleteKey()
        assertTrue("blob should have existed before we destroyed it", paths.seedBlob.delete())
    }

    @Test
    fun `own mnemonic re-entered - channel state is retained, not quarantined`() {
        val channelState = setUpWalletWithLiveState()
        val discriminatorBefore = paths.discriminator.readText()
        destroyBlobAndKey()

        val outcome = guard(matchKeep = true).onSeedImport(Vectors.ACCOUNT_XPUB_A)

        assertEquals(GuardOutcome.StateKept, outcome)
        assertTrue(
            "The user's own channel state was destroyed by re-entering their own mnemonic. " +
                "This is the misfire BIT-20 exists to prevent: under rule 3 a lost blob is " +
                "routine, so the iOS inference 'no mnemonic => foreign state' is false here.",
            channelState.isFile,
        )
        assertEquals(
            "live channel state - the force-close sweep material",
            channelState.readText(),
        )
        assertTrue(
            "Nothing should have been quarantined",
            StateQuarantine(paths).existing().isEmpty(),
        )
        assertEquals(
            "The discriminator must be left alone when state is kept",
            discriminatorBefore,
            paths.discriminator.readText(),
        )
    }

    @Test
    fun `different mnemonic - state is quarantined into a fresh subdirectory`() {
        val channelState = setUpWalletWithLiveState()
        val stateContents = channelState.readText()
        destroyBlobAndKey()

        val outcome = guard(matchKeep = true).onSeedImport(Vectors.ACCOUNT_XPUB_B)

        val quarantined = outcome as GuardOutcome.StateQuarantined
        assertEquals(
            GuardOutcome.StateQuarantined.Reason.DiscriminatorMismatch,
            quarantined.reason,
        )
        assertTrue(
            "Foreign state must leave the live directory - importing a foreign seed onto live " +
                "channel state is the loss-of-funds path the iOS guard exists to prevent.",
            !File(paths.ldkStateDir, "channel_monitors.dat").exists(),
        )
        assertTrue(
            "Quarantine must never delete: the quarantined file is the only material that can " +
                "sweep funds from a force-closed channel (LightningStorage.swift:83-84).",
            File(quarantined.directory, "channel_monitors.dat").isFile,
        )
        assertEquals(
            stateContents,
            File(quarantined.directory, "channel_monitors.dat").readText(),
        )
    }

    @Test
    fun `a key invalidated by the Keystore is recoverable, not an error`() {
        setUpWalletWithLiveState()
        // The blob file survives but the key is gone - what a Keystore
        // invalidation actually looks like. iOS's real behaviour here is to
        // propagate, which would turn rule 3's routine case into "cannot
        // restore". Rule 3 mandates the divergence.
        wrapper.failWith = KeyPermanentlyInvalidatedException("key invalidated")

        val outcome = guard(matchKeep = true).onSeedImport(Vectors.ACCOUNT_XPUB_A)

        assertEquals(
            "An invalidated key must route to restore-from-mnemonic and keep the user's own " +
                "state, not throw.",
            GuardOutcome.StateKept,
            outcome,
        )
    }

    @Test
    fun `a wallet with no prior state is not treated as foreign`() {
        paths = WalletPaths.forTesting(temp.newFolder("wallet"))
        wrapper = FakeSeedWrapper()
        vault = SeedVault(paths, wrapper)

        val outcome = guard(matchKeep = true).onSeedImport(Vectors.ACCOUNT_XPUB_A)

        assertEquals(GuardOutcome.NoStatePresent, outcome)
        assertNotEquals(
            "A fresh install has nothing to quarantine",
            0,
            StateQuarantine(paths).existing().size + 1,
        )
    }
}
