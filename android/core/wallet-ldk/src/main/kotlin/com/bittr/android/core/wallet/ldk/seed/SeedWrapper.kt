package com.bittr.android.core.wallet.ldk.seed

/**
 * Wraps and unwraps the mnemonic under a device-bound key.
 *
 * Extracted as an interface for one reason that matters more than testability:
 * it puts every `KeyGenParameterSpec` decision in exactly one file
 * ([AndroidKeystoreSeedWrapper]), so rules 2 and 5 have a single site to audit
 * and a single site for the negative guards to police. The classification and
 * guard logic that decides whether a user keeps their channels then sits above
 * this line, in plain Kotlin, exercisable without an emulator.
 *
 * Implementations must throw rather than return null on failure — the whole
 * point of [SeedBlobClassifier] is that "could not read" and "nothing there" are
 * different answers, and a nullable return cannot express that difference.
 */
interface SeedWrapper {

    /** True if the wrapping key exists. Does not prove the blob decrypts. */
    fun hasKey(): Boolean

    /** Creates the wrapping key if absent. Idempotent. */
    fun ensureKey()

    /** @throws Exception classified by [SeedBlobClassifier]. */
    fun wrap(plaintext: ByteArray): ByteArray

    /** @throws Exception classified by [SeedBlobClassifier]. */
    fun unwrap(ciphertext: ByteArray): ByteArray

    /** Removes the wrapping key. Used by wallet removal, and by tests. */
    fun deleteKey()
}
