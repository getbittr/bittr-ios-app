package com.bittr.android.core.common.destination

/**
 * Is this string an address on this chain?
 *
 * The port of `String.asBitcoinAddress()` / `isValidBitcoinAddress()`
 * (`AddressParsing.swift:120-131`), which on iOS is one call into
 * `BitcoinDevKit.Address(address:network:)`.
 */
internal object BitcoinAddress {

    /**
     * Returns the address in the form that should be used, or `null`.
     *
     * The two-attempt shape is iOS's, and it is load-bearing rather than defensive
     * (`AddressParsing.swift:120-127`):
     *
     * ```swift
     * if self.isValidBitcoinAddress() { return self }
     * guard self.rangeOfCharacter(from: .lowercaseLetters) == nil else { return nil }
     * return self.lowercased().isValidBitcoinAddress() ? self.lowercased() : nil
     * ```
     *
     * Try the string as scanned first. Only if that fails, *and* the string contains
     * no lower-case letters at all, try it lower-cased. The guard is what keeps the
     * two address families straight:
     *
     * - **bech32** is case-insensitive but must not be mixed-case, and QR encoders
     *   prefer all-upper-case because uppercase alphanumeric mode packs denser. So
     *   `BC1QW508…` is a real scan and must be accepted, lower-cased.
     * - **base58** is case-sensitive: `1BvBMSEY…` and `1bvbmsey…` are different
     *   strings and at most one of them has a valid checksum. Lower-casing a base58
     *   address that merely had a typo could not rescue it, and the guard means we
     *   never try — a base58 address always contains a lower-case letter in
     *   practice, and if it somehow does not, the checksum still decides.
     *
     * The one place this departs from iOS: a valid segwit address is returned
     * **lower-cased even when it was scanned in upper case**, where iOS returns it as
     * typed. Case carries no information in bech32, so this loses nothing, and it
     * means Send and the transaction list show one canonical form no matter how the
     * payee's QR encoder chose to pack the characters.
     */
    fun normalise(candidate: String, network: BitcoinNetwork): String? {
        if (isValidSegwit(candidate, network)) return candidate.lowercase()
        if (isValidBase58(candidate, network)) return candidate

        if (candidate.any { it in 'a'..'z' }) return null
        val lowered = candidate.lowercase()
        return if (isValidBase58(lowered, network)) lowered else null
    }

    /**
     * BIP-173 / BIP-350 segwit: the HRP must be this chain's, the witness version
     * must pick the matching checksum, and the program length must be legal.
     *
     * The version-to-encoding pairing is the part worth being strict about. A v0
     * address carries a bech32 checksum and a v1 (taproot) address carries a
     * bech32m one; accepting either for either is the known BIP-350 footgun, and it
     * would let a corrupted taproot address through.
     */
    private fun isValidSegwit(candidate: String, network: BitcoinNetwork): Boolean {
        val decoded = Bech32.decode(candidate) ?: return false
        if (decoded.hrp != network.bech32Hrp) return false
        if (decoded.data.isEmpty()) return false

        val witnessVersion = decoded.data[0].toInt()
        if (witnessVersion > 16) return false

        val expected =
            if (witnessVersion == 0) Bech32.Encoding.BECH32 else Bech32.Encoding.BECH32M
        if (decoded.encoding != expected) return false

        val program = Bech32.convertBits(
            decoded.data.copyOfRange(1, decoded.data.size),
            fromBits = 5,
            toBits = 8,
            pad = false,
        ) ?: return false

        if (program.size < 2 || program.size > 40) return false
        // v0 is P2WPKH (20) or P2WSH (32) and nothing else.
        if (witnessVersion == 0 && program.size != 20 && program.size != 32) return false

        return true
    }

    private fun isValidBase58(candidate: String, network: BitcoinNetwork): Boolean {
        val decoded = Base58Check.decode(candidate) ?: return false
        return decoded.version == network.p2pkhVersion || decoded.version == network.p2shVersion
    }
}
