package com.bittr.android.core.common.destination

import java.security.MessageDigest

/**
 * Base58Check, for the two legacy address forms that predate bech32 — P2PKH (`1…`)
 * and P2SH (`3…`).
 *
 * Bittr sends to whatever the user scans, and plenty of the world still hands out
 * `3…` addresses, so "segwit only" would be a regression against iOS, which accepts
 * anything `BitcoinDevKit.Address` accepts.
 *
 * Note that base58 is **case-sensitive** — unlike bech32, where case carries no
 * information. That asymmetry is not a detail: it is the reason iOS tries the
 * address as typed before it tries it lower-cased, and why [BitcoinAddress] does
 * the same rather than normalising up front.
 */
internal object Base58Check {

    private const val ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    /**
     * Decodes [input] and verifies its 4-byte double-SHA256 checksum.
     *
     * @return the version byte and payload, or `null` if the string is not base58,
     *   is the wrong length, or fails its checksum.
     */
    fun decode(input: String): Decoded? {
        if (input.isEmpty()) return null

        var num = java.math.BigInteger.ZERO
        val base = java.math.BigInteger.valueOf(58L)
        for (c in input) {
            val index = ALPHABET.indexOf(c)
            if (index < 0) return null
            num = num.multiply(base).add(java.math.BigInteger.valueOf(index.toLong()))
        }

        // BigInteger drops leading zero bytes, and base58 encodes each of them as a
        // leading '1'. They have to be put back before the checksum is taken.
        val withoutLeadingZeros = num.toByteArray().let {
            if (it.size > 1 && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it
        }
        val leadingZeros = input.takeWhile { it == '1' }.length
        val bytes = ByteArray(leadingZeros) + withoutLeadingZeros

        // 1 version byte + 20 payload bytes + 4 checksum bytes.
        if (bytes.size != 25) return null

        val body = bytes.copyOfRange(0, bytes.size - 4)
        val checksum = bytes.copyOfRange(bytes.size - 4, bytes.size)
        val sha = MessageDigest.getInstance("SHA-256")
        val expected = sha.digest(sha.digest(body)).copyOfRange(0, 4)
        if (!checksum.contentEquals(expected)) return null

        return Decoded(version = body[0].toInt() and 0xFF, payload = body.copyOfRange(1, body.size))
    }

    data class Decoded(val version: Int, val payload: ByteArray) {
        override fun equals(other: Any?): Boolean =
            this === other ||
                (other is Decoded && version == other.version && payload.contentEquals(other.payload))

        override fun hashCode(): Int = version * 31 + payload.contentHashCode()
    }
}
