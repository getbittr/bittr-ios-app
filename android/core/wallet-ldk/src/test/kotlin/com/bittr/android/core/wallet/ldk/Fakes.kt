package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.seed.SeedWrapper
import java.security.UnrecoverableKeyException

/**
 * A [SeedWrapper] that behaves like the Keystore for the purposes the guard cares
 * about — has a key or does not, decrypts or does not, and can be told to fail
 * transiently — without needing a device.
 *
 * The real Keystore is covered separately by `KeystoreKeySpecTest` (on-device,
 * asserts the `KeyInfo` flags) and by `KeystoreKeySpecGuardTest` (static, asserts
 * nobody adds the banned parameters). What is faked here is only the *outcome*,
 * which is the input the classification and guard logic actually consumes.
 */
class FakeSeedWrapper(
    private val xorByte: Byte = 0x5A,
) : SeedWrapper {

    private var keyExists = false

    /** When set, every wrap/unwrap throws this. Used for row 3 of the classifier. */
    var failWith: Throwable? = null

    /** Corrupts unwrap output, simulating a truncated or torn write. */
    var corruptUnwrap = false

    override fun hasKey(): Boolean = keyExists

    override fun ensureKey() {
        failWith?.let { throw it }
        keyExists = true
    }

    override fun wrap(plaintext: ByteArray): ByteArray {
        failWith?.let { throw it }
        if (!keyExists) throw UnrecoverableKeyException("no key")
        return ByteArray(plaintext.size) { (plaintext[it].toInt() xor xorByte.toInt()).toByte() }
    }

    override fun unwrap(ciphertext: ByteArray): ByteArray {
        failWith?.let { throw it }
        if (!keyExists) throw UnrecoverableKeyException("no key")
        val out = ByteArray(ciphertext.size) {
            (ciphertext[it].toInt() xor xorByte.toInt()).toByte()
        }
        return if (corruptUnwrap) out.also { if (it.isNotEmpty()) it[0] = 0 } else out
    }

    override fun deleteKey() {
        keyExists = false
    }
}

/**
 * Test vectors.
 *
 * These are **not** real wallet seeds and hold no funds. The account xpubs below
 * are opaque identifier strings for the discriminator, which hashes whatever it
 * is given — the guard's behaviour does not depend on them parsing as xpubs. The
 * BIP84 derivation that produces a real one arrives with the BDK wiring, and is
 * checked against the shared iOS vectors at that point.
 */
object Vectors {
    const val ACCOUNT_XPUB_A = "vpub5TESTACCOUNTA000000000000000000000000000000000000000000000000"
    const val ACCOUNT_XPUB_B = "vpub5TESTACCOUNTB111111111111111111111111111111111111111111111111"
    val MNEMONIC_A: ByteArray = "test vector mnemonic A - not a real seed".toByteArray()
}
