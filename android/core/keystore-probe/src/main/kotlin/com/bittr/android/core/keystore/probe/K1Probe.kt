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
            unlockedDeviceRequired = unlockedDeviceRequiredOf(info),
            securityLevel = securityLevelOf(info),
        )
    }

    /**
     * Whether Keystore says this key is unlocked-device-bound, or `null` where the device
     * cannot be asked.
     *
     * WHY REFLECTION AND NOT A VERSION GUARD
     *
     * This read used to be `if (SDK_INT >= P) info.isUnlockedDeviceRequired else false`, and it
     * threw `NoSuchMethodError` on every device in K1's matrix — API 26, 30, 33, 34 and 35 —
     * because the guard names the wrong API level by eight. `setUnlockedDeviceRequired` is on
     * `KeyGenParameterSpec.Builder` from API 28; the *readback* on [KeyInfo] arrived only in
     * **36.1**. It compiled because compileSdk is 37, and the whole matrix came back as five
     * ERROR rows with no verdict on rule 2.
     *
     * Writing `SDK_INT >= 36` instead would be wrong again in the same direction: 36.1 is a
     * minor release, `SDK_INT` is 36 on both 36.0 and 36.1, and the field that can tell them
     * apart — `Build.VERSION.SDK_INT_FULL` — does not itself exist below 36. A correct version
     * guard here is a two-level check whose failure mode is this exact `NoSuchMethodError`,
     * discoverable only by booting a device.
     *
     * So K1 asks the device instead of asking the documentation, which is the premise the whole
     * issue is built on: "documentation is not a device and OEM builds diverge." An absent
     * method is a fact about that device, and it comes back as `null` — *unknown*, never as
     * `false`. A missing readback must not be able to report itself as a satisfied rule 2.
     *
     * [K1KeySpecs.nonAuthBound] never calls the setter, so the honest reading below 36.1 is
     * "the spec did not ask for it and the device cannot be asked what it did" — which is what
     * K1SealTest asserts and what the result table records per row.
     */
    private fun unlockedDeviceRequiredOf(info: KeyInfo): Boolean? =
        try {
            KeyInfo::class.java.getMethod("isUnlockedDeviceRequired").invoke(info) as? Boolean
        } catch (_: NoSuchMethodException) {
            null
        } catch (_: ReflectiveOperationException) {
            null
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
        /** `null` where [KeyInfo] has no `isUnlockedDeviceRequired` — see [unlockedDeviceRequiredOf]. */
        val unlockedDeviceRequired: Boolean?,
        val securityLevel: String,
    )

    class MissingKeyException(message: String) : RuntimeException(message)
}
