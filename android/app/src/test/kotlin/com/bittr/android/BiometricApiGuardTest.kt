package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Makes "biometrics are off in the test build" enforceable rather than aspirational.
 *
 * `BuildConfig.BIOMETRIC_UNLOCK_ENABLED` only helps if unlock actually consults it.
 * Nothing stops DEV-17 from calling `BiometricPrompt` directly, and that mistake is
 * invisible until an emulator with a fingerprint enrolled fails ~90% of the suite
 * in one run. So the rule is checked in the cheapest place that can see it: any
 * reference to the biometric APIs outside [ALLOWED_FILES] fails the JVM tests.
 *
 * **This is a routing rule, not a ban.** Shipping `BiometricPrompt` is expected —
 * put the call in a file listed here and gate it on
 * [com.bittr.android.core.common.AuthCapabilities.biometricUnlockEnabled]. Adding a
 * name to the list is the moment to check that gate exists, which is the whole
 * point of routing it through one place.
 */
class BiometricApiGuardTest {

    private companion object {
        val BIOMETRIC_SYMBOLS = listOf(
            "androidx.biometric",
            "BiometricPrompt",
            "BiometricManager",
            "USE_BIOMETRIC",
        )

        /**
         * Files allowed to name the biometric APIs.
         *
         * `AuthCapabilities.kt` / `AuthModule.kt` define and bind the gate; the two
         * guard tests and their documentation quote the API names in prose. When
         * unlock lands, add its file here — and only after it reads
         * `biometricUnlockEnabled` first.
         */
        val ALLOWED_FILES = setOf(
            "AuthCapabilities.kt",
            "AuthModule.kt",
            "BiometricApiGuardTest.kt",
            "BiometricUnlockFlagTest.kt",
            // A third guard test that quotes the API name in prose, exactly as
            // the two above do: WalletKeystorePolicyGuardTest bans
            // setUserAuthenticationRequired(true) on the seed key, and its
            // failure message explains that an auth-bound key "conflicts with
            // BiometricPrompt unlock (BIT-13)". It contains no call — the whole
            // file is a source scanner.
            //
            // Added by BIT-59, which is the first run of this repo's JVM tests
            // with :core:wallet-ldk present. Two guards that each work by naming
            // a banned symbol will always collide this way; the routing rule in
            // this class's header is what says the resolution is the allowlist
            // and not a reworded assertion.
            "WalletKeystorePolicyGuardTest.kt",
        )
    }

    @Test
    fun `biometric APIs are only reachable through the AuthCapabilities gate`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val text = file.readText()
                val hit = BIOMETRIC_SYMBOLS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (references $hit)"
            }

        assertTrue(
            "Biometric APIs must be reached through AuthCapabilities.biometricUnlockEnabled, " +
                "which is false in com.bittr.android.regtest. Unguarded uses put a " +
                "BiometricPrompt ahead of the PIN pad on any emulator with a fingerprint " +
                "enrolled, which fails 296 of the 329 takeScreenshot steps.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "If the call is genuinely gated, add the file name to ALLOWED_FILES.",
            offenders.isEmpty(),
        )
    }
}
