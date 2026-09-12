package com.bittr.android.core.wallet.seed

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The restore gate's rules.
 *
 * BIT-19 records that iOS has no negative coverage on the restore path — the suite
 * only ever types a phrase it knows is good. These are the cases that decide whether
 * someone gets their money back.
 */
class SeedPhraseEntryTest {

    /**
     * The phrase `shared/flows/onboarding/restore_wallet.yaml` types in.
     *
     * Asserting it here is not redundant with the Maestro flow: if this phrase ever
     * stopped being valid BIP-39, the flow would fail on Android with a UI alert and
     * look like a broken screen rather than a broken fixture.
     */
    private val flowPhrase = listOf(
        "attack", "urge", "across", "cupboard", "year", "armor",
        "list", "vital", "outer", "leader", "anxiety", "endorse",
    )

    @Test
    fun `accepts the phrase the restore flow types`() {
        val entry = SeedPhraseEntry.check(flowPhrase)
        assertTrue("Expected Accepted, got $entry", entry is PhraseEntry.Accepted)
        assertEquals(flowPhrase, (entry as PhraseEntry.Accepted).mnemonic.words)
    }

    @Test
    fun `accepts the all-zero-entropy test vector`() {
        val vector = List(11) { "abandon" } + "about"
        assertTrue(SeedPhraseEntry.check(vector) is PhraseEntry.Accepted)
    }

    // --- Rejection path 1: a word that is not BIP-39 at all -------------------

    @Test
    fun `rejects a word that is not in the wordlist`() {
        // "attck" — the misspelling someone actually makes, not a nonsense string.
        val typo = listOf("attck") + flowPhrase.drop(1)
        assertEquals(PhraseEntry.NotInWordlist, SeedPhraseEntry.check(typo))
    }

    @Test
    fun `a bad word is reported ahead of the checksum`() {
        // Both things are wrong with this input. The user can act on the misspelling
        // and cannot act on "the checksum failed", so that is the one to report.
        val broken = listOf("attck", "zzzz") + flowPhrase.drop(2)
        assertEquals(PhraseEntry.NotInWordlist, SeedPhraseEntry.check(broken))
    }

    // --- Rejection path 2: twelve real words that are the wrong phrase --------

    @Test
    fun `rejects twelve real words whose checksum does not match`() {
        // Twelve legitimate BIP-39 words. Nothing about them is misspelled; they are
        // simply not a phrase, which is what a wallet must never accept.
        assertEquals(PhraseEntry.ChecksumFailed, SeedPhraseEntry.check(List(12) { "abandon" }))
    }

    @Test
    fun `rejects the right words in the wrong order`() {
        // The failure this gate exists for: every word is one the user wrote down,
        // and restoring anyway would derive a different seed and show them an empty
        // balance for a wallet that still holds their coins.
        val swapped = flowPhrase.toMutableList().apply { add(0, removeAt(1)) }
        assertEquals(PhraseEntry.ChecksumFailed, SeedPhraseEntry.check(swapped))
    }

    // --- Incomplete ----------------------------------------------------------

    @Test
    fun `rejects a blank field as incomplete rather than invalid`() {
        val missing = flowPhrase.toMutableList().apply { this[6] = "" }
        assertEquals(PhraseEntry.Incomplete, SeedPhraseEntry.check(missing))
    }

    @Test
    fun `a field of spaces is incomplete, not a bad word`() {
        val spaces = flowPhrase.toMutableList().apply { this[3] = "   " }
        assertEquals(PhraseEntry.Incomplete, SeedPhraseEntry.check(spaces))
    }

    @Test
    fun `rejects the wrong number of words`() {
        assertEquals(PhraseEntry.Incomplete, SeedPhraseEntry.check(flowPhrase.drop(1)))
        assertEquals(PhraseEntry.Incomplete, SeedPhraseEntry.check(flowPhrase + "abandon"))
    }

    // --- Normalising ---------------------------------------------------------

    @Test
    fun `trims and lowercases what the keyboard produced`() {
        // A capitalising keyboard and a paste from a password manager are the two
        // ways a correct phrase arrives looking wrong. Neither is the user's mistake.
        val messy = flowPhrase.mapIndexed { index, word ->
            if (index % 2 == 0) " ${word.replaceFirstChar { it.uppercase() }} " else word
        }
        val entry = SeedPhraseEntry.check(messy)
        assertTrue("Expected Accepted, got $entry", entry is PhraseEntry.Accepted)
        assertEquals(flowPhrase, (entry as PhraseEntry.Accepted).mnemonic.words)
    }
}
