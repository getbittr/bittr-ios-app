package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.seedStateDirectory
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **BIT-20 rule 2, the `absent` row — state of unknown provenance is
 * quarantined.**
 *
 * This is the row that reproduces today's iOS behaviour exactly, and it is
 * deliberately the fail-safe default: a state directory with no readable
 * discriminator is quarantined, never adopted. Deleting the discriminator to
 * force a quarantine is therefore a denial of service, not a fund loss —
 * quarantine never deletes, so the material is still there to sweep with.
 *
 * On Android the `absent` row can only be reached by a pre-port dev build or by
 * state placed out of band, because there is no legacy Android population at
 * all. That makes quarantining it unambiguously right, where on iOS the same
 * decision had to be weighed against a real migrating user base
 * (`LightningStorage.swift:19–23`).
 */
class ForeignStateQuarantinedTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    private lateinit var fixture: WalletFixture

    @Before
    fun setUp() {
        fixture = WalletFixture(temporaryFolder.root)
    }

    @Test
    fun `state with no discriminator is quarantined`() {
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "unattributable")

        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertNotNull(result.quarantineDirectory)
        assertEquals(
            "unattributable",
            File(result.quarantineDirectory!!, "ldk_node_data.sqlite").readText(),
        )
        assertFalse(fixture.stateStore.hasLightningState())
        assertTrue(
            "The imported seed's discriminator must be recorded, so the next import " +
                "of the same seed takes the match row rather than quarantining again.",
            result.discriminatorRecorded,
        )
    }

    @Test
    fun `a malformed discriminator is quarantined, not treated as a match`() {
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "truncated-discriminator")
        fixture.paths.discriminatorFile.writeText("deadbeef")

        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertNotNull(
            "A short read must classify as absent — the fail-safe row. Reading it as " +
                "a match is the fund-loss direction.",
            result.quarantineDirectory,
        )
    }

    @Test
    fun `a fresh install records a discriminator without quarantining`() {
        val result = fixture.importer.import(Mnemonics.IOS_VECTOR)

        assertEquals(null, result.quarantineDirectory)
        assertFalse(result.keptExistingState)
        assertTrue(result.discriminatorRecorded)
        assertTrue(
            "Nothing may be created under the quarantine root when there was nothing " +
                "to quarantine.",
            fixture.stateStore.quarantines().isEmpty(),
        )
    }

    @Test
    fun `quarantine survives a re-import of the same foreign state`() {
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "round-one")
        val first = fixture.importer.import(Mnemonics.IOS_VECTOR).quarantineDirectory!!

        // A second wallet lifecycle on the same device: seed removed, new
        // foreign state, new import.
        fixture.vault.clear()
        fixture.paths.discriminatorFile.delete()
        seedStateDirectory(fixture.paths.ldkStateDir, marker = "round-two")
        val second = fixture.importer.import(Mnemonics.OTHER).quarantineDirectory!!

        assertEquals("round-one", File(first, "ldk_node_data.sqlite").readText())
        assertEquals("round-two", File(second, "ldk_node_data.sqlite").readText())
    }
}
