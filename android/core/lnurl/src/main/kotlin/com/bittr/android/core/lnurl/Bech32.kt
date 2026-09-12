package com.bittr.android.core.lnurl

/**
 * Bech32 (BIP-173) decoding, strict.
 *
 * Only used by [LnurlDetector], and only to answer one question: *is this string
 * genuinely an `lnurl1…` and what URL does it contain?* Everything here is
 * validation; nothing is lenient.
 *
 * **Why hand-rolled rather than lenient string handling.** BIT-33 R-6 exists
 * because iOS decides "this is an LNURL" with
 * `h.lowercased().contains("lnurl")` in the injected observer and
 * `absolute.hasPrefix("lnurl") || absolute.contains("tag=login")` in
 * `decidePolicyFor`. Both match `https://evil.example/?utm=lnurl`. A checksum is
 * the cheapest thing that cannot be faked by putting five letters in a query
 * string, so detection is a real parse or it is nothing.
 *
 * **Deliberate deviation from BIP-173: no 90-character limit.** Real LNURLs
 * routinely exceed it — the encoded payload is a whole URL — so enforcing it
 * would reject valid input. The checksum's guarantee weakens for very long
 * strings, which does not matter here: the checksum is being used to reject
 * strings that were never LNURLs, not to correct typos in ones that were.
 *
 * Bech32 only (constant 1), never bech32m. LNURL predates BIP-350 and does not
 * use it; accepting both would double the space of strings that decode.
 */
internal object Bech32 {

    private const val CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private const val CHECKSUM_LENGTH = 6
    private const val SEPARATOR = '1'

    private val GENERATORS = intArrayOf(
        0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3,
    )

    /** A successfully decoded bech32 string: its human-readable part and its payload bytes. */
    data class Decoded(val hrp: String, val data: ByteArray) {

        // data class + ByteArray needs these written out, or equality is identity
        // and the tests compare references.
        override fun equals(other: Any?): Boolean =
            this === other ||
                (other is Decoded && hrp == other.hrp && data.contentEquals(other.data))

        override fun hashCode(): Int = 31 * hrp.hashCode() + data.contentHashCode()
    }

    /**
     * Decodes [input], or returns `null` if it is not a valid bech32 string.
     *
     * Rejects: empty input, mixed case, a missing or misplaced separator, an empty
     * human-readable part, characters outside printable US-ASCII in the HRP,
     * characters outside the bech32 charset in the data part, a failing checksum,
     * and a payload whose 5-to-8-bit regrouping has non-zero or over-long padding.
     */
    fun decode(input: String): Decoded? {
        if (input.isEmpty()) return null

        // Mixed case is invalid per BIP-173 and is not a formatting nicety: it is
        // how the same logical string gets two different checksums.
        val hasLower = input.any { it in 'a'..'z' }
        val hasUpper = input.any { it in 'A'..'Z' }
        if (hasLower && hasUpper) return null

        val normalised = input.lowercase()

        // Last separator, not the first: the HRP may not contain '1' but the data
        // part may, so `lnurl1...1...` is one HRP and a payload containing '1'.
        val separatorAt = normalised.lastIndexOf(SEPARATOR)
        if (separatorAt < 1) return null
        if (normalised.length - separatorAt - 1 < CHECKSUM_LENGTH) return null

        val hrp = normalised.substring(0, separatorAt)
        if (hrp.any { it.code < 33 || it.code > 126 }) return null

        val values = IntArray(normalised.length - separatorAt - 1)
        for (i in values.indices) {
            val index = CHARSET.indexOf(normalised[separatorAt + 1 + i])
            if (index < 0) return null
            values[i] = index
        }

        if (!checksumIsValid(hrp, values)) return null

        val payload = convertBits(values.copyOf(values.size - CHECKSUM_LENGTH)) ?: return null
        return Decoded(hrp, payload)
    }

    private fun checksumIsValid(hrp: String, values: IntArray): Boolean =
        polymod(expandHrp(hrp) + values.toList()) == 1

    private fun expandHrp(hrp: String): List<Int> =
        hrp.map { it.code shr 5 } + listOf(0) + hrp.map { it.code and 31 }

    private fun polymod(values: List<Int>): Int {
        var checksum = 1
        for (value in values) {
            val top = checksum shr 25
            checksum = ((checksum and 0x1ffffff) shl 5) xor value
            for (bit in GENERATORS.indices) {
                if ((top shr bit) and 1 == 1) checksum = checksum xor GENERATORS[bit]
            }
        }
        return checksum
    }

    /**
     * Regroups 5-bit values into bytes, rejecting anything that is not an exact
     * encoding of a whole number of bytes.
     *
     * The padding checks are the part worth keeping: without them several distinct
     * bech32 strings decode to the same bytes, which means an attacker can produce
     * a second spelling of an LNURL that a comparison or a cache keyed on the
     * original will not recognise.
     */
    private fun convertBits(values: IntArray): ByteArray? {
        var accumulator = 0
        var bits = 0
        val out = ArrayList<Byte>(values.size * 5 / 8)

        for (value in values) {
            if (value < 0 || value shr 5 != 0) return null
            accumulator = (accumulator shl 5) or value
            bits += 5
            while (bits >= 8) {
                bits -= 8
                out.add(((accumulator shr bits) and 0xff).toByte())
            }
        }

        if (bits >= 5) return null
        if ((accumulator shl (8 - bits)) and 0xff != 0) return null

        return out.toByteArray()
    }
}
