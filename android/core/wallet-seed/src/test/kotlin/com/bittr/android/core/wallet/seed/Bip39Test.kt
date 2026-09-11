package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import java.security.MessageDigest
import java.security.SecureRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Bip39Test {

    /**
     * The wordlist is the one thing here that cannot be caught by any other test: a
     * single wrong word still produces twelve plausible-looking words, and the phrase
     * would simply fail to restore in any other wallet — months later, with funds on
     * it. Pinning the published digest makes "ported verbatim from Bip39Words.swift"
     * a fact the build checks.
     */
    @Test
    fun `wordlist matches the published BIP-39 English digest`() {
        val text = Bip39.wordlist.joinToString("\n") + "\n"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

        assertEquals(Bip39.WORDLIST_SHA256, digest)
        assertEquals(2048, Bip39.wordlist.size)
        assertEquals("abandon", Bip39.wordlist.first())
        assertEquals("zoo", Bip39.wordlist.last())
    }

    /** The BIP-39 spec's first English test vector. */
    @Test
    fun `all-zero entropy produces the spec's test vector`() {
        val mnemonic = Bip39.fromEntropy(ByteArray(16))

        assertEquals(
            "abandon abandon abandon abandon abandon abandon " +
                "abandon abandon abandon abandon abandon about",
            mnemonic.phrase,
        )
    }

    /** The spec's `0x7f…` vector, which exercises the checksum rather than zeroes. */
    @Test
    fun `all-0x7f entropy produces the spec's test vector`() {
        val mnemonic = Bip39.fromEntropy(ByteArray(16) { 0x7f })

        assertEquals(
            "legal winner thank year wave sausage worth useful legal winner thank yellow",
            mnemonic.phrase,
        )
    }

    @Test
    fun `generated phrases are twelve words with a valid checksum`() {
        val random = SecureRandom.getInstance("SHA1PRNG").apply { setSeed(42L) }

        repeat(50) {
            val mnemonic = Bip39.generate(random)

            assertEquals(Bip39.WORD_COUNT, mnemonic.words.size)
            assertTrue(mnemonic.words.all { it in Bip39.wordlist })
            assertTrue("Checksum invalid for $mnemonic", Bip39.isChecksumValid(mnemonic))
        }
    }

    /**
     * Two calls must not return the same phrase. A generator wired to a constant
     * seed would pass every other test in this file and hand every user on earth the
     * same wallet.
     */
    @Test
    fun `generation does not repeat itself`() {
        val phrases = (1..100).map { Bip39.generate().phrase }.toSet()

        assertEquals(100, phrases.size)
    }

    @Test
    fun `a phrase with a tampered last word fails the checksum`() {
        val good = Bip39.fromEntropy(ByteArray(16))
        val tampered = Mnemonic(good.words.dropLast(1) + "zoo")

        assertTrue(Bip39.isChecksumValid(good))
        assertFalse(Bip39.isChecksumValid(tampered))
    }

    @Test
    fun `word validity is case-insensitive and ignores surrounding space`() {
        assertTrue(Bip39.isValidWord("abandon"))
        assertTrue(Bip39.isValidWord("  Abandon "))
        assertFalse(Bip39.isValidWord("abandonn"))
        assertFalse(Bip39.isValidWord(""))
    }

    /** The seed must never fall into a log line by way of string interpolation. */
    @Test
    fun `toString does not print the words`() {
        val mnemonic = Bip39.fromEntropy(ByteArray(16))

        assertFalse("$mnemonic".contains("abandon"))
        assertTrue("$mnemonic".contains("redacted"))
    }
}
