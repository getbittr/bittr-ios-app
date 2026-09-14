package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey

/**
 * The LNURL-auth signature — iOS's `signLNURLAuthK1DERHex` and `compressedPublicKeyHex`
 * (`SendLNURL.swift:608–654`, `734–756`): secp256k1 ECDSA over the 32-byte `k1` as given
 * (no extra hashing), DER-encoded, with the compressed public key.
 */
object LnurlAuthSigner {

    data class Signed(val keyHex: String, val signatureHex: String)

    fun sign(k1: ByteArray, linkingPrivateKey: ByteArray): Signed {
        require(k1.size == 32) { "k1 must be 32 bytes" }
        require(linkingPrivateKey.size == 32) { "a linking key must be 32 bytes" }
        val key = PrivateKey(linkingPrivateKey)
        val compact = Crypto.sign(ByteVector32(k1), key).toByteArray()
        return Signed(
            keyHex = key.publicKey().toHex(),
            signatureHex = der(compact).toHexString(),
        )
    }

    /** A 64-byte `r || s` as a DER `SEQUENCE { INTEGER r, INTEGER s }` — secp256k1's `serialize_der`. */
    internal fun der(compact: ByteArray): ByteArray {
        fun integer(bytes: ByteArray): ByteArray {
            var start = 0
            while (start < bytes.size - 1 && bytes[start] == 0.toByte()) start++
            val trimmed = bytes.copyOfRange(start, bytes.size)
            val value = if (trimmed[0].toInt() and 0x80 != 0) byteArrayOf(0) + trimmed else trimmed
            return byteArrayOf(0x02, value.size.toByte()) + value
        }
        val body = integer(compact.copyOfRange(0, 32)) + integer(compact.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }

    private fun ByteArray.toHexString(): String = joinToString("") { "%02x".format(it) }
}
