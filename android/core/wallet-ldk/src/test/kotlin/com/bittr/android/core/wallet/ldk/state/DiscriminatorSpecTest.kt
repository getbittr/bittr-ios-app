package com.bittr.android.core.wallet.ldk.state

import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.bip.Bip84Account
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **BIT-20 rule 1 — the discriminator is a full-width SHA-256 of the BIP84
 * account xpub, compared in constant time.**
 *
 * The width is the part with teeth. The obvious cheaper choice is the 4-byte
 * BIP32 master fingerprint, and it is rejected because 32 bits is grindable on
 * a laptop: an attacker who can grind a mnemonic to a chosen fingerprint turns
 * a `mismatch` row into a `match`, which re-opens the precise loss-of-funds
 * path the guard exists to close. Hence the size assertions below are not
 * decoration — they are the rule.
 */
class DiscriminatorSpecTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun `the digest is a full 32 bytes`() {
        val digest = SeedDiscriminator.compute(
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false),
        )

        assertEquals(
            "A truncated discriminator is a grindable one. 32 bits can be matched by " +
                "brute force on a laptop, which converts a mismatch into a match.",
            32,
            digest.size,
        )
        assertEquals(64, SeedDiscriminator.encode(digest).length)
    }

    @Test
    fun `a one-byte perturbation of the xpub mismatches`() {
        val xpub = Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false)
        val perturbed = xpub.dropLast(1) + if (xpub.last() == 'a') 'b' else 'a'

        assertFalse(
            SeedDiscriminator.matches(
                SeedDiscriminator.compute(xpub),
                SeedDiscriminator.compute(perturbed),
            ),
        )
    }

    @Test
    fun `different seeds produce different discriminators`() {
        val mine = SeedDiscriminator.compute(
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false),
        )
        val theirs = SeedDiscriminator.compute(
            Bip84Account.accountXpub(Mnemonics.OTHER, mainnet = false),
        )

        assertFalse(SeedDiscriminator.matches(mine, theirs))
        assertTrue(SeedDiscriminator.matches(mine, mine.copyOf()))
    }

    @Test
    fun `the comparison is the constant-time one`() {
        // A static check, because the property is not observable from a unit
        // test's outputs: `Arrays.equals` and `String.equals` short-circuit on
        // the first differing byte and would pass every behavioural assertion
        // in this file. The comparison call site is one line; this is what
        // keeps it that line.
        val source = File("src/main/kotlin/com/bittr/android/core/wallet/ldk/state/SeedDiscriminator.kt")
        assertTrue("Expected to find $source from ${File(".").canonicalFile}", source.isFile)

        val body = source.readText().lines()
            .filterNot { it.trimStart().startsWith("*") || it.trimStart().startsWith("//") }
            .joinToString("\n")

        assertTrue(
            "SeedDiscriminator.matches must delegate to MessageDigest.isEqual.",
            "MessageDigest.isEqual" in body,
        )
        for (banned in listOf("Arrays.equals", "contentEquals")) {
            assertFalse(
                "$banned is not constant-time; it short-circuits on the first " +
                    "differing byte. Use MessageDigest.isEqual.",
                banned in body,
            )
        }
    }

    @Test
    fun `a malformed record reads as absent, never as a match`() {
        val file = File(temporaryFolder.root, "seed_discriminator")
        val store = DiscriminatorStore(file)

        assertEquals(
            "No file at all is the fresh-install case.",
            DiscriminatorRecord.Absent,
            store.read(),
        )

        for (malformed in listOf("", "   ", "zz", "not-hex", "ab".repeat(31), "ab".repeat(33))) {
            file.writeText(malformed)
            assertEquals(
                "A short, long or non-hex discriminator must classify as absent — the " +
                    "fail-safe row. Absent quarantines, and quarantine never deletes, so " +
                    "corrupting this file is a denial of service. Reading it as a match " +
                    "would be the fund-loss direction.",
                DiscriminatorRecord.Absent,
                store.read(),
            )
        }
    }

    @Test
    fun `a written record round-trips`() {
        val file = File(temporaryFolder.root, "nested/seed_discriminator")
        val store = DiscriminatorStore(file)
        val digest = SeedDiscriminator.compute(
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false),
        )

        store.write(digest)

        val record = store.read()
        assertTrue(record is DiscriminatorRecord.Present)
        assertArrayEquals(digest, (record as DiscriminatorRecord.Present).digest)
    }
}
