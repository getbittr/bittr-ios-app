package com.bittr.android.core.swaps

/** Lower-case hex, as iOS's `hexEncodedString()` writes it and Boltz sends it. */
internal object Hex {

    fun encode(bytes: ByteArray): String = buildString(bytes.size * 2) {
        for (byte in bytes) {
            val value = byte.toInt() and 0xff
            append(DIGITS[value ushr 4])
            append(DIGITS[value and 0x0f])
        }
    }

    /** @throws IllegalArgumentException when [hex] is not an even run of hex digits. */
    fun decode(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Odd-length hex" }
        return ByteArray(hex.length / 2) { index ->
            val high = Character.digit(hex[index * 2], 16)
            val low = Character.digit(hex[index * 2 + 1], 16)
            require(high >= 0 && low >= 0) { "Not hex" }
            ((high shl 4) or low).toByte()
        }
    }

    private const val DIGITS = "0123456789abcdef"
}

internal fun ByteArray.toHex(): String = Hex.encode(this)

/** Bitcoin's CompactSize. */
internal fun compactSize(value: Int): ByteArray = when {
    value < 0xfd -> byteArrayOf(value.toByte())
    value <= 0xffff -> byteArrayOf(0xfd.toByte(), value.toByte(), (value ushr 8).toByte())
    else -> byteArrayOf(
        0xfe.toByte(),
        value.toByte(),
        (value ushr 8).toByte(),
        (value ushr 16).toByte(),
        (value ushr 24).toByte(),
    )
}

/** Unsigned lexicographic order, which is how BIP341 sorts the two branch hashes. */
internal fun compareUnsigned(a: ByteArray, b: ByteArray): Int {
    for (i in 0 until minOf(a.size, b.size)) {
        val diff = (a[i].toInt() and 0xff) - (b[i].toInt() and 0xff)
        if (diff != 0) return diff
    }
    return a.size - b.size
}
