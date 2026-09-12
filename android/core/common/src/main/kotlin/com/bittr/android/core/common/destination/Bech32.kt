package com.bittr.android.core.common.destination

/**
 * Bech32 and bech32m (BIP-173 / BIP-350).
 *
 * Three of the four things a scanned string can be are bech32 underneath — segwit
 * addresses, BOLT-11 invoices and LNURLs — so the checksum lives here once rather
 * than three times. iOS never needed this file: it hands each candidate to
 * BitcoinDevKit, LDK or `LNURLDecoder` and asks whether they choked
 * (`AddressParsing.swift:129-144`). Those are node libraries, and BIT-100 is meant
 * to be parseable with no node, so the checksum is ported instead of borrowed.
 *
 * **Why the checksum matters and a prefix check would not.** The whole point of
 * validating a destination before the engine sees it is to catch a QR that decoded
 * one character wrong. Bech32's checksum is designed to catch exactly that. Testing
 * for a `bc1` prefix would accept a corrupted address and lose the user's money at
 * broadcast time, which is the failure this parser exists to prevent.
 */
internal object Bech32 {

    private const val CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    /** The polymod residue of a well-formed bech32 string (BIP-173). */
    private const val BECH32_CONST = 1

    /** The residue for bech32m, which segwit v1+ uses instead (BIP-350). */
    private const val BECH32M_CONST = 0x2BC830A3

    /** Which checksum constant a decoded string satisfied. */
    enum class Encoding { BECH32, BECH32M }

    data class Decoded(
        /** The human-readable part, always lower-cased. */
        val hrp: String,
        /** The data part as 5-bit groups, checksum already stripped. */
        val data: ByteArray,
        val encoding: Encoding,
    ) {
        // Generated equals/hashCode would compare `data` by identity. These are only
        // here so the data class behaves for test assertions.
        override fun equals(other: Any?): Boolean =
            this === other ||
                (
                    other is Decoded && hrp == other.hrp &&
                        data.contentEquals(other.data) && encoding == other.encoding
                    )

        override fun hashCode(): Int =
            (hrp.hashCode() * 31 + data.contentHashCode()) * 31 + encoding.hashCode()
    }

    /**
     * Decodes [input], or returns `null` if it is not valid bech32/bech32m.
     *
     * Mixed case is rejected, as BIP-173 requires: `BC1QW508…` and `bc1qw508…` are
     * the same address, but `Bc1Qw508…` is not an address at all. That rule is the
     * reason [DestinationParser] can safely lower-case a scanned string before
     * looking for an invoice or an LNURL — for bech32 payloads, case carries no
     * information, so removing it removes nothing.
     *
     * @param maxLength the BIP-173 90-character cap. It applies to *addresses* only;
     *   BOLT-11 invoices and LNURLs are deliberately longer, so they pass
     *   [Int.MAX_VALUE] rather than being silently truncated into invalidity.
     */
    fun decode(input: String, maxLength: Int = 90): Decoded? {
        if (input.length > maxLength) return null

        val hasUpper = input.any { it in 'A'..'Z' }
        val hasLower = input.any { it in 'a'..'z' }
        if (hasUpper && hasLower) return null

        val normalised = input.lowercase()
        val separator = normalised.lastIndexOf('1')

        // The HRP must be non-empty and there must be room for a 6-character
        // checksum after the separator.
        if (separator < 1 || separator + 7 > normalised.length) return null

        val hrp = normalised.substring(0, separator)
        if (hrp.any { it.code < 33 || it.code > 126 }) return null

        val dataPart = normalised.substring(separator + 1)
        val values = ByteArray(dataPart.length)
        for ((i, c) in dataPart.withIndex()) {
            val index = CHARSET.indexOf(c)
            if (index < 0) return null
            values[i] = index.toByte()
        }

        val encoding = when (polymod(hrpExpand(hrp) + values.map { it.toInt() })) {
            BECH32_CONST -> Encoding.BECH32
            BECH32M_CONST -> Encoding.BECH32M
            else -> return null
        }

        return Decoded(hrp, values.copyOfRange(0, values.size - 6), encoding)
    }

    /**
     * Regroups [data] from [fromBits]-wide groups to [toBits]-wide groups.
     *
     * With `pad = false` — the direction that turns 5-bit bech32 groups back into
     * bytes — any leftover bits must be fewer than [fromBits] and must be zero.
     * Skipping that check is the classic way to accept two distinct encodings of the
     * same payload, so it is enforced rather than assumed.
     */
    fun convertBits(data: ByteArray, fromBits: Int, toBits: Int, pad: Boolean): ByteArray? {
        var acc = 0
        var bits = 0
        val maxValue = (1 shl toBits) - 1
        val out = ArrayList<Byte>(data.size * fromBits / toBits + 1)

        for (value in data) {
            val v = value.toInt() and 0xFF
            if (v shr fromBits != 0) return null
            acc = (acc shl fromBits) or v
            bits += fromBits
            while (bits >= toBits) {
                bits -= toBits
                out.add(((acc shr bits) and maxValue).toByte())
            }
        }

        if (pad) {
            if (bits > 0) out.add(((acc shl (toBits - bits)) and maxValue).toByte())
        } else if (bits >= fromBits || ((acc shl (toBits - bits)) and maxValue) != 0) {
            return null
        }

        return out.toByteArray()
    }

    private fun hrpExpand(hrp: String): List<Int> =
        hrp.map { it.code shr 5 } + listOf(0) + hrp.map { it.code and 31 }

    private fun polymod(values: List<Int>): Int {
        val generator = intArrayOf(0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
        var checksum = 1
        for (value in values) {
            val top = checksum shr 25
            checksum = ((checksum and 0x1FFFFFF) shl 5) xor value
            for (i in 0..4) {
                if ((top shr i) and 1 == 1) checksum = checksum xor generator[i]
            }
        }
        return checksum
    }
}
