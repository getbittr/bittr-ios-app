package com.bittr.android.core.wallet.keystore

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletStorageException
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * [SecureStore] backed by an Android Keystore AES/GCM key.
 *
 * Each value is sealed with a key the app never sees — the Keystore holds it, and on
 * most devices since API 23 it lives in the TEE or a StrongBox, so a copy of the
 * app's data directory taken off the device decrypts to nothing.
 *
 * ### The key is deliberately not auth-bound
 *
 * There is no `setUserAuthenticationRequired(true)` and no
 * `setUnlockedDeviceRequired(true)` below, and that is the decided model (BIT-8),
 * not an omission.
 *
 * It is the faithful port of the class iOS stores the mnemonic under —
 * `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`CacheManager.swift:358`).
 * "After first unlock, this device only" means: available to background work once
 * the user has unlocked the device at least once since boot, and never present in a
 * backup or on another device. The Keystore equivalent of *that* is a key with no
 * per-use authentication and no device-unlocked requirement.
 *
 * Binding the key harder than iOS does would not be a free upgrade. A wallet has to
 * be able to act while the screen is off — BIT-6's node has to respond to an
 * incoming HTLC, and a user with no lockscreen credential at all would be unable to
 * generate a key that required one. The user-facing gate is the PIN, which sits in
 * front of the app at every launch; see
 * `com.bittr.android.core.wallet.seed.SeedWalletService`.
 *
 * BIT-18 verifies this on a device. BIT-20 constrains which directory the blobs may
 * live in. `KeystoreKeySpecGuardTest` in `:app` fails the build if the flags above
 * are ever added without that conversation being had again.
 *
 * @param directory where the sealed blobs go. Defaults to a subdirectory of the
 *   app's private `filesDir`, which is `MODE_PRIVATE` and excluded from cloud backup
 *   by the app's backup rules.
 */
class KeystoreSecureStore(
    private val directory: File,
    private val keyAlias: String = DEFAULT_KEY_ALIAS,
) : SecureStore {

    constructor(context: Context) : this(File(context.filesDir, DIRECTORY_NAME))

    override fun read(key: String): ByteArray? {
        val file = fileFor(key)
        if (!file.isFile) return null
        return try {
            val sealed = file.readBytes()
            if (sealed.size <= IV_BYTES) {
                throw WalletStorageException("Sealed blob for $key is truncated")
            }
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(
                    Cipher.DECRYPT_MODE,
                    existingKey() ?: throw WalletStorageException(
                        "The Keystore key is gone but $key is still on disk",
                    ),
                    GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES),
                )
            }
            cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
        } catch (e: WalletStorageException) {
            throw e
        } catch (e: Exception) {
            // A failure here is not "no value" — it is a value we can no longer read,
            // which for a seed is the difference between "create a wallet" and "your
            // funds are gone". Never let it degrade into null.
            throw WalletStorageException("Could not decrypt $key", e)
        }
    }

    override fun write(key: String, value: ByteArray) {
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, orCreateKey())
            }
            check(cipher.iv.size == IV_BYTES) { "Expected a $IV_BYTES-byte GCM IV" }
            val sealed = cipher.iv + cipher.doFinal(value)

            directory.mkdirs()
            // Write-then-rename, so a kill mid-write cannot leave a half-written seed
            // where a whole one used to be.
            val temp = File(directory, "${fileNameFor(key)}.tmp")
            temp.writeBytes(sealed)
            if (!temp.renameTo(fileFor(key))) {
                temp.delete()
                throw WalletStorageException("Could not move $key into place")
            }
        } catch (e: WalletStorageException) {
            throw e
        } catch (e: Exception) {
            throw WalletStorageException("Could not store $key", e)
        }
    }

    override fun contains(key: String): Boolean = fileFor(key).isFile

    override fun remove(key: String) {
        val file = fileFor(key)
        if (file.isFile && !file.delete()) {
            throw WalletStorageException("Could not remove $key")
        }
    }

    private fun fileNameFor(key: String): String {
        require(key.matches(SAFE_KEY)) { "Unsupported store key: $key" }
        return "$key.bin"
    }

    private fun fileFor(key: String) = File(directory, fileNameFor(key))

    private fun existingKey(): SecretKey? =
        (KeyStore.getInstance(PROVIDER).apply { load(null) }
            .getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry)?.secretKey

    private fun orCreateKey(): SecretKey = existingKey() ?: KeyGenerator
        .getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        .apply {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(KEY_BITS)
                    // No setUserAuthenticationRequired, no setUnlockedDeviceRequired.
                    // Read the class documentation before adding either — see BIT-8.
                    .build(),
            )
        }
        .generateKey()

    companion object {
        const val DEFAULT_KEY_ALIAS = "co.getbittr.wallet.seed.v1"
        const val DIRECTORY_NAME = "wallet"

        private const val PROVIDER = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val KEY_BITS = 256
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128
        private val SAFE_KEY = Regex("[a-zA-Z0-9._-]{1,64}")
    }
}
