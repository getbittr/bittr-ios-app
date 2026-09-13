package com.bittr.android.core.keystore.probe

/**
 * On-disk format for the sealed blob: `[version:1][ivLen:1][iv][ciphertext||tag]`.
 *
 * `setRandomizedEncryptionRequired(true)` means Keystore picks the GCM IV, so the IV is not
 * reconstructible at open time and has to be stored next to the ciphertext. It is not secret.
 *
 * Deliberately hand-rolled and tiny. This file is read by the *open* phase in a different
 * process, after a lock-screen mutation, and the one thing it must never do is fail for a
 * reason of its own — a serialization bug here would surface as "the key did not survive",
 * which is precisely the false red K1 exists to rule out.
 */
object K1Envelope {

    private const val VERSION: Byte = 1

    fun encode(iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(iv.size in 1..255) { "IV length ${iv.size} does not fit in one byte" }
        val out = ByteArray(2 + iv.size + ciphertext.size)
        out[0] = VERSION
        out[1] = iv.size.toByte()
        iv.copyInto(out, 2)
        ciphertext.copyInto(out, 2 + iv.size)
        return out
    }

    fun decode(bytes: ByteArray): Decoded {
        require(bytes.size >= 2) { "envelope truncated: ${bytes.size} bytes" }
        require(bytes[0] == VERSION) { "unknown envelope version ${bytes[0]}" }
        val ivLen = bytes[1].toInt() and 0xFF
        require(bytes.size > 2 + ivLen) { "envelope truncated: ivLen=$ivLen, size=${bytes.size}" }
        return Decoded(
            iv = bytes.copyOfRange(2, 2 + ivLen),
            ciphertext = bytes.copyOfRange(2 + ivLen, bytes.size),
        )
    }

    data class Decoded(val iv: ByteArray, val ciphertext: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is Decoded && iv.contentEquals(other.iv) && ciphertext.contentEquals(other.ciphertext)

        override fun hashCode(): Int = 31 * iv.contentHashCode() + ciphertext.contentHashCode()
    }
}
