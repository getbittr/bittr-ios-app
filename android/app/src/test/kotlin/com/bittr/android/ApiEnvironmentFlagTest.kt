package com.bittr.android

import com.bittr.android.core.network.BittrEnvironment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the backend each APK talks to, the way [BiometricUnlockFlagTest] pins the
 * biometric flag: keyed off [BuildConfig.APPLICATION_ID] so the assertion is about
 * the artefact rather than about the build type's name, and asserting on **both**
 * branches so the release build cannot silently drift onto staging.
 *
 * `androidComponents { beforeVariants }` in `app/build.gradle.kts` enables the
 * release unit tests, which is what makes the second branch run at all.
 *
 * This is the test that makes [com.bittr.android.core.network.BittrEnvironment]'s
 * throw-instead-of-fall-back decision affordable: `BITTR_ENVIRONMENT` is a string in
 * a build file with no compiler checking it, so a typo has to be caught *somewhere*.
 * Caught here, it is a red test; caught at runtime it is a crash on launch; not
 * caught at all — which is what a lenient fallback would give — it is a debug build
 * quietly reading the production backend.
 */
class ApiEnvironmentFlagTest {

    private companion object {
        /** The APK `.github/workflows/android-maestro.yml` installs on the emulator. */
        const val MAESTRO_APP_ID = "com.bittr.android.regtest"
    }

    @Test
    fun `the regtest build talks to staging and every other build talks to production`() {
        val environment = BittrEnvironment.fromBuildConfig(BuildConfig.BITTR_ENVIRONMENT)

        if (BuildConfig.APPLICATION_ID == MAESTRO_APP_ID) {
            assertEquals(
                "$MAESTRO_APP_ID must talk to the staging backend. Pointing the regtest " +
                    "build at production is the BIT-32 bug: on the endpoint that matters " +
                    "(/notifications, authenticated by lightning-pubkey signature) it is a " +
                    "debug build reading real customers' payout state.",
                BittrEnvironment.DEVELOPMENT,
                environment,
            )
        } else {
            assertEquals(
                "${BuildConfig.APPLICATION_ID} must talk to the production backend. A " +
                    "shipped build on staging would take real signups and real payouts to " +
                    "the wrong server while looking like it worked.",
                BittrEnvironment.PRODUCTION,
                environment,
            )
        }
    }

    @Test
    fun `the compiled environment name is one BittrEnvironment recognises`() {
        // Deliberately not `runCatching`: if the build file holds a name the enum does
        // not have, the exception message is the useful output and it should be the
        // failure. The assertion below is what stops the test passing vacuously if
        // someone makes the field optional.
        val environment = BittrEnvironment.fromBuildConfig(BuildConfig.BITTR_ENVIRONMENT)

        assertTrue(
            "BITTR_ENVIRONMENT is '${BuildConfig.BITTR_ENVIRONMENT}', which is not one of " +
                "${BittrEnvironment.entries.map { it.name }}.",
            environment in BittrEnvironment.entries,
        )
    }

    @Test
    fun `the debug build is the regtest build`() {
        // Same pairing as BiometricUnlockFlagTest: the override lives on the `debug`
        // build type, the guarantee above is stated in terms of the applicationId, and
        // if those come apart the check above starts asserting about the wrong APK.
        assertTrue(
            "The debug build must be $MAESTRO_APP_ID; it is ${BuildConfig.APPLICATION_ID}.",
            !BuildConfig.DEBUG || BuildConfig.APPLICATION_ID == MAESTRO_APP_ID,
        )
    }

    @Test
    fun `the two environments are not the same backend`() {
        assertNotEquals(
            "DEVELOPMENT and PRODUCTION resolve to the same base URL, so every " +
                "assertion above passes while both builds talk to one backend.",
            BittrEnvironment.DEVELOPMENT.apiBaseUrl,
            BittrEnvironment.PRODUCTION.apiBaseUrl,
        )
    }
}
