package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import java.util.Base64

/**
 * Bitcoin message signatures (BIP137 style) — iOS's `BitcoinMessage.sign(message:privateKeyHex:segwitType:)`
 * (`Helpers/BitcoinMessage.swift`).
 *
 * This is the `bitcoin_signature` in `POST /customer`: the customer proves they own the address at
 * `m/84'/{1 dev, 0 prod}'/0'/0/0` by signing the registration message with its key. The backend
 * verifies it with a standard message verifier, so the bytes have to match iOS exactly:
 *
 * - **Digest.** `magicHash` builds `varint(len) "Bitcoin Signed Message:\n" varint(len) message` and
 *   takes SHA-256 once; P256K's `signature(for:)` then hashes that again before signing. The
 *   signed digest is therefore double SHA-256 — the standard `hash256` — and so it is here.
 * - **Signature.** secp256k1 ECDSA with RFC 6979 nonces and low-S, which both libraries produce, so
 *   the same key and message give the same signature on both platforms.
 * - **Header byte.** `27 + recoveryId + 12` for P2WPKH (8 for segwit, 4 for compressed), then the
 *   64-byte compact signature, base64.
 */
object BitcoinMessageSigner {

    private val PREFIX = "Bitcoin Signed Message:\n".toByteArray(Charsets.UTF_8)

    /** The flag iOS adds for `.p2wpkh`: 8 (segwit) + 4 (P2WPKH). */
    private const val P2WPKH_FLAG = 12

    /** The double SHA-256 of the prefixed message — the 32 bytes that are actually signed. */
    fun messageDigest(message: String): ByteArray {
        val body = message.toByteArray(Charsets.UTF_8)
        val preimage = varint(PREFIX.size) + PREFIX + varint(body.size) + body
        return Crypto.sha256(Crypto.sha256(preimage))
    }

    /** Sign [message] for a native segwit (P2WPKH) address owned by [privateKey]. Base64. */
    fun signP2wpkh(message: String, privateKey: PrivateKey): String {
        val digest = messageDigest(message)
        val signature = Crypto.sign(ByteVector32(digest), privateKey)
        val publicKey = privateKey.publicKey()
        val recoveryId = (0..3).firstOrNull { id ->
            runCatching { Crypto.recoverPublicKey(signature, digest, id) == publicKey }.getOrDefault(false)
        } ?: error("No recovery id reproduces the signing key")
        val header = (27 + recoveryId + P2WPKH_FLAG).toByte()
        return Base64.getEncoder().encodeToString(byteArrayOf(header) + signature.toByteArray())
    }

    /** Bitcoin's CompactSize, as `BitcoinMessage.varintEncode` writes it. */
    internal fun varint(value: Int): ByteArray = when {
        value < 0xfd -> byteArrayOf(value.toByte())
        value <= 0xffff -> byteArrayOf(0xfd.toByte(), (value and 0xff).toByte(), ((value shr 8) and 0xff).toByte())
        else -> byteArrayOf(
            0xfe.toByte(),
            (value and 0xff).toByte(),
            ((value shr 8) and 0xff).toByte(),
            ((value shr 16) and 0xff).toByte(),
            ((value shr 24) and 0xff).toByte(),
        )
    }

    /** iOS's `defaultBip84SigningPath()`: the first external address of account 0. */
    fun defaultSigningPath(mainnet: Boolean): String = if (mainnet) "m/84'/0'/0'/0/0" else "m/84'/1'/0'/0/0"
}
