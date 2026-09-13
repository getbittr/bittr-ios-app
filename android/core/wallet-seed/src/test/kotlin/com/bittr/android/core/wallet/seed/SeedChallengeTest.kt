package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import java.security.SecureRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The negative coverage BIT-19 records as missing on the seed gate.
 *
 * The happy path is the cheap half. What matters is that a wrong word cannot get
 * through, because the gate is the only thing standing between "the user thinks they
 * wrote the phrase down" and "the user has funded a wallet they cannot recover".
 */
class SeedChallengeTest {

    private val mnemonic = Mnemonic(
        listOf(
            "abandon", "ability", "able", "about", "above", "absent",
            "absorb", "abstract", "absurd", "abuse", "access", "accident",
        ),
    )

    private fun challenge(vararg positions: Int) = SeedChallenge(mnemonic, positions.toList())

    @Test
    fun `the three correct words pass`() {
        val result = challenge(0, 5, 11).check(listOf("abandon", "absent", "accident"))

        assertEquals(SeedCheck.Correct, result)
    }

    @Test
    fun `one wrong word is rejected even though the other two are right`() {
        val result = challenge(0, 5, 11).check(listOf("abandon", "absent", "ability"))

        assertEquals(SeedCheck.Incorrect, result)
    }

    @Test
    fun `every single-field substitution is rejected`() {
        val correct = listOf("abandon", "absent", "accident")

        correct.indices.forEach { field ->
            // "zoo" is a real BIP-39 word and is not in this phrase, so this isolates
            // "wrong word" from "not a word".
            val answers = correct.toMutableList().apply { this[field] = "zoo" }

            assertEquals(
                "Field $field accepted a wrong word",
                SeedCheck.Incorrect,
                challenge(0, 5, 11).check(answers),
            )
        }
    }

    @Test
    fun `right words in the wrong order are rejected`() {
        val result = challenge(0, 5, 11).check(listOf("accident", "absent", "abandon"))

        assertEquals(SeedCheck.Incorrect, result)
    }

    @Test
    fun `a word that is not in the BIP-39 list is called out separately`() {
        val result = challenge(0, 5, 11).check(listOf("abandon", "absentt", "accident"))

        assertEquals(SeedCheck.NotInWordlist, result)
    }

    @Test
    fun `a blank field is called out separately`() {
        assertEquals(
            SeedCheck.Missing,
            challenge(0, 5, 11).check(listOf("abandon", "   ", "accident")),
        )
        assertEquals(
            SeedCheck.Missing,
            challenge(0, 5, 11).check(listOf("", "", "")),
        )
    }

    /** A blank field must not be reported as a typo; the copy differs. */
    @Test
    fun `blank beats not-in-wordlist when both are present`() {
        val result = challenge(0, 5, 11).check(listOf("", "nonsense", "accident"))

        assertEquals(SeedCheck.Missing, result)
    }

    @Test
    fun `answers are trimmed and case-folded, matching iOS`() {
        val result = challenge(0, 5, 11).check(listOf("  Abandon", "ABSENT ", " Accident "))

        assertEquals(SeedCheck.Correct, result)
    }

    @Test
    fun `labels are the one-based word numbers`() {
        assertEquals(listOf(1, 6, 12), challenge(0, 5, 11).labels)
    }

    @Test
    fun `random challenges ask for three distinct ascending positions`() {
        val random = SecureRandom.getInstance("SHA1PRNG").apply { setSeed(7L) }

        repeat(200) {
            val positions = SeedChallenge.random(mnemonic, random).positions

            assertEquals(3, positions.size)
            assertEquals(positions.distinct(), positions)
            assertEquals(positions.sorted(), positions)
            assertTrue(positions.all { it in 0..11 })
        }
    }

    /** If it always asked about the same words, the check would verify nothing. */
    @Test
    fun `random challenges vary`() {
        val seen = (1..200).map { SeedChallenge.random(mnemonic).positions }.toSet()

        assertNotEquals(1, seen.size)
    }
}
