package com.bittr.android.core.wallet.ldk.seed

import android.security.keystore.KeyPermanentlyInvalidatedException
import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.seedStateDirectory
import java.io.FileNotFoundException
import java.io.IOException
import java.security.KeyStoreException
import java.security.ProviderException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * **BIT-20 rule 3 — a transient Keystore failure is a failure, not an absence.**
 *
 * The classification has to be three-way where iOS's is two-way, and the third
 * row is the one that exists purely to stop a fund-loss outcome arriving by the
 * back door: if a busy or unavailable Keystore provider were read as "no
 * mnemonic here", the guard would fall through to the identity check, find a
 * discriminator it cannot compare against a seed it could not read, and
 * quarantine live channel state because of one flaky call.
 *
 * So the default has to fail towards *not* quarantining. The last test in this
 * file is the one that keeps it that way: an exception type nobody anticipated
 * takes the abort path, because the `when` has no fallback branch meaning
 * "absent".
 *
 * Runs under Robolectric only because `KeyPermanentlyInvalidatedException` is a
 * framework class; nothing here touches a real Keystore.
 */
@RunWith(RobolectricTestRunner::class)
class TransientKeystoreFailureAbortsTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    private lateinit var fixture: WalletFixture

    @Before
    fun setUp() {
        fixture = WalletFixture(temporaryFolder.root)
    }

    @Test
    fun `terminal blob failures classify as no usable mnemonic`() {
        val terminal = listOf<Throwable>(
            AEADBadTagException("tag mismatch"),
            KeyPermanentlyInvalidatedException("key invalidated"),
            FileNotFoundException("no blob"),
            // Terminal markers routinely arrive wrapped, so the cause chain is
            // walked rather than the top type alone.
            IOException("while reading the seed", AEADBadTagException("tag mismatch")),
            RuntimeException(IllegalStateException(KeyPermanentlyInvalidatedException("nested"))),
        )

        for (throwable in terminal) {
            assertEquals(
                "${throwable::class.simpleName} is terminal for the blob: it must route " +
                    "to the restore screen, which is what BIT-8 rule 3 requires of a " +
                    "lost cache.",
                MnemonicPresence.NoUsableMnemonic,
                SeedVaultFailures.classify(throwable),
            )
        }
    }

    @Test
    fun `provider failures classify as unavailable`() {
        val transient = listOf<Throwable>(
            KeyStoreException("Keystore operation failed"),
            ProviderException("keystore is busy"),
            IllegalStateException("binder transaction failed"),
        )

        for (throwable in transient) {
            assertTrue(
                "${throwable::class.simpleName} must not be read as an absence. " +
                    "Collapsing it into 'no mnemonic' quarantines live channel state on " +
                    "a flaky call.",
                SeedVaultFailures.classify(throwable) is MnemonicPresence.Unavailable,
            )
        }
    }

    @Test
    fun `an unrecognised exception takes the abort path`() {
        class SomethingNobodyAnticipated : RuntimeException("from a future OEM build")

        assertTrue(
            "The classifier must have no fallback branch that means 'absent'. An " +
                "unrecognised throwable is row 3 — abort and retry — never row 2. This " +
                "is the assertion that stops row 3 rotting into row 2 as the exception " +
                "surface changes under us.",
            SeedVaultFailures.classify(SomethingNobodyAnticipated()) is MnemonicPresence.Unavailable,
        )
    }

    @Test
    fun `the guard aborts rather than quarantining when the vault is unavailable`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "live-channel-monitor")
        val discriminatorBefore = fixture.paths.discriminatorFile.readText()

        // The blob is intact; the provider is not answering.
        fixture.codec.unwrapFailure = { ProviderException("keystore unavailable") }

        assertThrows(SeedImportAbortedException::class.java) {
            fixture.importer.import(Mnemonics.OTHER)
        }

        assertTrue(
            "Nothing may be quarantined on a transient failure — that is the fund-loss " +
                "outcome by the back door.",
            fixture.stateStore.quarantines().isEmpty(),
        )
        assertTrue(fixture.stateStore.hasLightningState())
        assertEquals(discriminatorBefore, fixture.paths.discriminatorFile.readText())

        // And it is genuinely retryable: once the provider answers, the same
        // call behaves as though the failure never happened.
        fixture.codec.unwrapFailure = null
        assertTrue(fixture.importer.import(Mnemonics.OTHER).alreadyProvisioned)
    }

    @Test
    fun `an unavailable vault does not report an absent mnemonic`() {
        fixture.importer.import(Mnemonics.IOS_VECTOR)
        fixture.blobStore.readFailure = { ProviderException("keystore unavailable") }

        val presence = fixture.vault.presence()

        assertTrue(presence is MnemonicPresence.Unavailable)
        assertFalse(presence == MnemonicPresence.NoUsableMnemonic)
    }
}
