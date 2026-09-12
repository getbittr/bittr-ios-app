package com.bittr.android.core.keystore.probe

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties

/**
 * The two Keystore key specs BIT-18/K1 puts on a device.
 *
 * These live in `src/main` rather than in the test source set on purpose: rule 2 of the
 * BIT-8 decision is stated as a set of `KeyGenParameterSpec` parameters, so the thing under
 * test should be readable as source in one place, not reconstructed inline in two test
 * methods that could drift apart between the seal phase and the open phase.
 *
 * **This module ships nothing.** `:app` does not depend on it. It exists to hold a probe and
 * its harness. BIT-6's production `SeedBlobCipher` is a separate class and must be built with
 * [nonAuthBound]'s parameters *exactly*; the spec calls that binding `KeystoreKeySpecTest`
 * (seed-storage-security §1, rule 2) and it is BIT-6's to write. K1 proves the platform
 * behaviour these parameters buy; `KeystoreKeySpecTest` proves production still asks for them.
 */
object K1KeySpecs {

    const val PROVIDER = "AndroidKeyStore"
    const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val GCM_TAG_BITS = 128
    const val KEY_SIZE_BITS = 256

    /**
     * Rule 2, literally.
     *
     * The important part of this builder is what it does **not** call:
     *
     * - no `setUserAuthenticationRequired(true)` — an auth-bound key cannot be used by the two
     *   unauthenticated seed reads that exist on iOS today (`CoreViewController.swift:229`,
     *   `ResetApp.swift:131`), and would break background node start.
     * - no `setUnlockedDeviceRequired(true)` — same reason, and it is API 28+ only, so relying
     *   on it would also mean two different security models across the minSdk 26 range.
     *
     * `setRandomizedEncryptionRequired(true)` is on, so Keystore generates the GCM IV and
     * refuses a caller-supplied one. That is why [K1Envelope] has to carry the IV.
     */
    fun nonAuthBound(alias: String): KeyGenParameterSpec =
        KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_SIZE_BITS)
            .setRandomizedEncryptionRequired(true)
            .build()

    /**
     * The positive control: a key that is *supposed* to die when the lock screen is destroyed.
     *
     * K1's whole risk is a false green — a run where the mutation silently did not happen and
     * the non-auth-bound key "survived" something that never occurred. This key is one of the
     * two witnesses against that (see [K1Case.usesAuthBoundControl]). It is never decrypted,
     * only checked for existence: decrypting it would need a real user authentication, and
     * `UserNotAuthenticatedException` is indistinguishable from invalidation for our purposes.
     *
     * It is a witness for credential *destruction* only (remove, admin reset). A PIN → PIN
     * change re-wraps the synthetic password and auth-bound keys legitimately survive it, so
     * for those cases the witness is the [android.app.KeyguardManager] transition plus the
     * host-side `locksettings verify`. Treating this key as a universal witness would make
     * K1 report false reds on cases 2 and 3.
     */
    fun authBoundControl(alias: String): KeyGenParameterSpec =
        KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_SIZE_BITS)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)
            .apply {
                // Bind to the device credential rather than to biometrics: the mutations
                // under test are credential changes, and a biometric-bound key would be
                // invalidated by fingerprint re-enrolment instead, which is not what we
                // are provoking.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setUserAuthenticationParameters(
                        AUTH_VALIDITY_SECONDS,
                        KeyProperties.AUTH_DEVICE_CREDENTIAL,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(AUTH_VALIDITY_SECONDS)
                }
            }
            .build()

    /**
     * Any positive number binds the control to the device credential rather than to
     * per-use biometric auth. The duration itself is irrelevant — the key is never used.
     */
    private const val AUTH_VALIDITY_SECONDS = 60
}
