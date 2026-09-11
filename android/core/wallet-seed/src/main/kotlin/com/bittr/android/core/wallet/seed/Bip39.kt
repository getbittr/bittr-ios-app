package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * BIP-39 mnemonic generation and validation, English wordlist.
 *
 * Hand-rolled rather than pulled from a library, for one reason: the algorithm is
 * forty lines and fully specified, while adding a dependency to the wallet's key
 * path is a supply-chain decision that belongs to the Bitcoin Wallet Engineer and
 * BIT-6, not to the screen that displays the words. When ldk-node lands it brings
 * its own BIP-39; at that point this should be deleted in favour of it rather than
 * kept as a second implementation.
 *
 * The wordlist is ported verbatim from `ios/bittr/Helpers/Bip39Words.swift`, so both
 * platforms tokenise the same phrase identically. [WORDLIST_SHA256] pins it.
 */
object Bip39 {

    /** bittr issues 12-word phrases, the same as iOS. */
    const val WORD_COUNT = 12

    /** 128 bits, the entropy a 12-word phrase encodes. */
    const val ENTROPY_BYTES = 16

    /**
     * SHA-256 of the wordlist as newline-separated text with a trailing newline.
     *
     * This is the published digest of the official BIP-39 English list. A test
     * asserts it, which is what makes "ported verbatim" checkable rather than
     * asserted: a single mistyped word here would produce phrases that no other
     * wallet can restore, and nothing else in the build would notice.
     */
    const val WORDLIST_SHA256 = "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"

    private const val RESOURCE = "/com/bittr/android/core/wallet/seed/bip39-english.txt"

    /** The 2048 words, in index order. */
    val wordlist: List<String> by lazy {
        val stream = checkNotNull(Bip39::class.java.getResourceAsStream(RESOURCE)) {
            "BIP-39 wordlist resource $RESOURCE is missing from the packaged module"
        }
        val words = stream.bufferedReader().use { it.readLines() }.filter { it.isNotBlank() }
        check(words.size == 2048) { "BIP-39 needs exactly 2048 words, found ${words.size}" }
        words
    }

    private val wordIndex: Map<String, Int> by lazy {
        wordlist.withIndex().associate { (i, w) -> w to i }
    }

    /**
     * Generate a fresh 12-word phrase.
     *
     * @param random defaults to a new [SecureRandom]. Tests pass a seeded instance;
     *   nothing in production should.
     */
    fun generate(random: SecureRandom = SecureRandom()): Mnemonic {
        val entropy = ByteArray(ENTROPY_BYTES)
        random.nextBytes(entropy)
        return fromEntropy(entropy)
    }

    /**
     * Encode [entropy] as a phrase: entropy bits, then a checksum of `bits/32` taken
     * from the front of SHA-256(entropy), split into 11-bit words.
     */
    fun fromEntropy(entropy: ByteArray): Mnemonic {
        require(entropy.size == ENTROPY_BYTES || entropy.size == 32) {
            "Supported entropy is 16 bytes (12 words) or 32 bytes (24 words), got ${entropy.size}"
        }
        val hash = MessageDigest.getInstance("SHA-256").digest(entropy)
        val entropyBits = entropy.size * 8
        val checksumBits = entropyBits / 32
        val totalBits = entropyBits + checksumBits

        fun bitAt(index: Int): Int = if (index < entropyBits) {
            (entropy[index / 8].toInt() and 0xFF) shr (7 - index % 8) and 1
        } else {
            val i = index - entropyBits
            (hash[i / 8].toInt() and 0xFF) shr (7 - i % 8) and 1
        }

        val words = (0 until totalBits / 11).map { group ->
            var index = 0
            for (bit in 0 until 11) {
                index = (index shl 1) or bitAt(group * 11 + bit)
            }
            wordlist[index]
        }
        return Mnemonic(words)
    }

    /** Whether [word] is in the wordlist at all. Case-insensitive, like the iOS check. */
    fun isValidWord(word: String): Boolean = word.trim().lowercase() in wordIndex

    /**
     * Whether [mnemonic]'s trailing checksum bits match its entropy.
     *
     * Not used on the create path — a phrase we just generated is valid by
     * construction — but it is the check the restore path (BIT-7) needs, and having
     * it here means the round-trip can be tested now.
     */
    fun isChecksumValid(mnemonic: Mnemonic): Boolean {
        val indices = mnemonic.words.map { wordIndex[it] ?: return false }
        val totalBits = indices.size * 11
        val checksumBits = totalBits / 33
        val entropyBits = totalBits - checksumBits

        val bits = BooleanArray(totalBits)
        indices.forEachIndexed { group, index ->
            for (bit in 0 until 11) {
                bits[group * 11 + bit] = (index shr (10 - bit)) and 1 == 1
            }
        }

        val entropy = ByteArray(entropyBits / 8)
        for (i in 0 until entropyBits) {
            if (bits[i]) entropy[i / 8] = (entropy[i / 8].toInt() or (1 shl (7 - i % 8))).toByte()
        }

        val hash = MessageDigest.getInstance("SHA-256").digest(entropy)
        for (i in 0 until checksumBits) {
            val expected = (hash[i / 8].toInt() and 0xFF) shr (7 - i % 8) and 1 == 1
            if (bits[entropyBits + i] != expected) return false
        }
        return true
    }
}
