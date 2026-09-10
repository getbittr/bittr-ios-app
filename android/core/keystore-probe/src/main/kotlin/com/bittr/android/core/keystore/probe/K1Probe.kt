package com.bittr.android.core.keystore.probe

import android.os.Build
import android.security.keystore.KeyInfo
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Generate / seal / open against the Android Keystore.
 *
 * Every entry point re-opens the Keystore from scratch. That is the single most important
 * property of this class: a `SecretKey` handle obtained before a lock-screen mutation may
 * still work afterwards from a cached provider state, so a test that held one across the
 * mutation would prove nothing. The open phase runs in a fresh process *and* loads the key
 * by alias *and* re-initialises the Cipher — three independent reasons for a dead key to
 * surface as a failure rather than as a pass.
 */
object K1Probe {

    /** The blob under test. Not a seed, not key material, not derived from anything. */
    val KNOWN_PLAINTEXT: ByteArray =
        "BIT-18/K1 known constant — not a seed, not key material, no funds.".toByteArray(Charsets.UTF_8)

    private fun keyStore(): KeyStore =
        KeyStore.getInstance(K1KeySpecs.PROVIDER).apply { load(null) }

    fun deleteAlias(alias: String) {
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    fun containsAlias(alias: String): Boolean = keyStore().containsAlias(alias)

    fun generate(spec: android.security.keystore.KeyGenParameterSpec): SecretKey =
        KeyGenerator.getInstance("AES", K1KeySpecs.PROVIDER)
            .apply { init(spec) }
            .generateKey()

    private fun loadKey(alias: String): SecretKey {
        val entry = keyStore().getEntry(alias, null)
            ?: throw MissingKeyException("no Keystore entry for alias '$alias'")
        val secret = (entry as? KeyStore.SecretKeyEntry)?.secretKey
            ?: throw MissingKeyException("alias '$alias' is a ${entry.javaClass.simpleName}, not a SecretKeyEntry")
        return secret
    }

    fun seal(alias: String, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(K1KeySpecs.TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, loadKey(alias))
        return K1Envelope.encode(cipher.iv, cipher.doFinal(plaintext))
    }

    fun open(alias: String, envelope: ByteArray): ByteArray {
        val decoded = K1Envelope.decode(envelope)
        val cipher = Cipher.getInstance(K1KeySpecs.TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            loadKey(alias),
            GCMParameterSpec(K1KeySpecs.GCM_TAG_BITS, decoded.iv),
        )
        return cipher.doFinal(decoded.ciphertext)
    }

    /**
     * Read back what Keystore says it actually created.
     *
     * Two jobs. First, the rule-2 flags: if someone edits [K1KeySpecs.nonAuthBound] to bind
     * the key to authentication, K1 would otherwise keep passing — for a key that is no
     * longer the key the decision is about. Second, the security level, which
     * seed-storage-security §4 asks to be *recorded per device* rather than asserted, because
     * API 26–27 devices legitimately fall back to software.
     */
    fun describe(alias: String): KeyFacts {
        val key = loadKey(alias)
        val info = SecretKeyFactory.getInstance(key.algorithm, K1KeySpecs.PROVIDER)
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        return KeyFacts(
            userAuthenticationRequired = info.isUserAuthenticationRequired,
            unlockedDeviceRequired =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.isUnlockedDeviceRequired else false,
            securityLevel = securityLevelOf(info),
        )
    }

    private fun securityLevelOf(info: KeyInfo): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (info.securityLevel) {
                KeyProperties_SECURITY_LEVEL_SOFTWARE -> "SOFTWARE"
                KeyProperties_SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "TRUSTED_ENVIRONMENT"
                KeyProperties_SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
                KeyProperties_SECURITY_LEVEL_UNKNOWN -> "UNKNOWN"
                else -> "UNKNOWN_SECURE(${info.securityLevel})"
            }
        } else {
            // isInsideSecureHardware() is all there is below API 31, and it cannot tell TEE
            // from StrongBox. Recorded as the coarser answer rather than guessed upwards.
            @Suppress("DEPRECATION")
            if (info.isInsideSecureHardware) "SECURE_HARDWARE_UNSPECIFIED" else "SOFTWARE"
        }

    // KeyProperties.SECURITY_LEVEL_* are API 31+ constants; naming them as locals keeps this
    // file compiling against any compileSdk without a NewApi suppression on the whole class.
    private const val KeyProperties_SECURITY_LEVEL_UNKNOWN = -2
    private const val KeyProperties_SECURITY_LEVEL_SOFTWARE = 0
    private const val KeyProperties_SECURITY_LEVEL_TRUSTED_ENVIRONMENT = 1
    private const val KeyProperties_SECURITY_LEVEL_STRONGBOX = 2

    data class KeyFacts(
        val userAuthenticationRequired: Boolean,
        val unlockedDeviceRequired: Boolean,
        val securityLevel: String,
    )

    class MissingKeyException(message: String) : RuntimeException(message)
}
