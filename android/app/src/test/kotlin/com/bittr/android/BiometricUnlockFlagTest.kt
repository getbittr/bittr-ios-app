package com.bittr.android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the biometric flag to the APK it ships in.
 *
 * The invariant is not "debug is false" but "the artefact CI installs is false",
 * so the test keys off [BuildConfig.APPLICATION_ID] — the same string the workflow
 * exports as `APP_ID` and passes to Maestro as `--env APP_ID`, which is where every
 * shared flow's `appId:` now comes from. Flipping the flag, or renaming the regtest
 * applicationId out from under the flows, both fail here rather than on an emulator.
 *
 * Both branches assert, so this is never vacuous: it also catches the release build
 * silently losing biometrics, which is a shipped-behaviour regression rather than a
 * test one.
 */
class BiometricUnlockFlagTest {

    private companion object {
        /** The APK `.github/workflows/android-maestro.yml` installs on the emulator. */
        const val MAESTRO_APP_ID = "com.bittr.android.regtest"
    }

    @Test
    fun `biometric unlock is off in the build Maestro installs and on elsewhere`() {
        if (BuildConfig.APPLICATION_ID == MAESTRO_APP_ID) {
            assertFalse(
                "BIOMETRIC_UNLOCK_ENABLED must be false in $MAESTRO_APP_ID. 296 of the " +
                    "329 takeScreenshot steps sit behind a PIN entry; a BiometricPrompt " +
                    "ahead of the PIN pad fails ~90% of the suite at once, and early " +
                    "enough that every downstream flow looks broken too.",
                BuildConfig.BIOMETRIC_UNLOCK_ENABLED,
            )
        } else {
            assertTrue(
                "BIOMETRIC_UNLOCK_ENABLED must stay true outside $MAESTRO_APP_ID — " +
                    "biometric unlock is the shipped behaviour (DEV-17); only the test " +
                    "build opts out.",
                BuildConfig.BIOMETRIC_UNLOCK_ENABLED,
            )
        }
    }

    @Test
    fun `the debug build is the regtest build`() {
        // The flag override lives on the `debug` build type but the guarantee above
        // is expressed in terms of the applicationId. If those two ever come apart —
        // someone drops applicationIdSuffix, or adds a build type Maestro runs
        // against — the check above starts asserting about the wrong artefact.
        assertTrue(
            "The debug build must be $MAESTRO_APP_ID; it is ${BuildConfig.APPLICATION_ID}. " +
                "Maestro flows and the CI workflow both name the regtest id literally.",
            !BuildConfig.DEBUG || BuildConfig.APPLICATION_ID == MAESTRO_APP_ID,
        )
    }
}
