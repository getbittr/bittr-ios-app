package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the Firebase client config to the APK it ships in (BIT-39).
 *
 * `google-services.json` is keyed by package name, and this app builds two of them —
 * `com.bittr.android` for release and `com.bittr.android.regtest` for debug. The
 * config therefore cannot be a single shared file; there is one per build type, in
 * `app/src/release/` and `app/src/debug/`.
 *
 * Nothing in the build checks this yet. The `google-services` Gradle plugin would
 * (it fails with "No matching client found for package name"), but applying it
 * belongs with the FCM client work, not with provisioning. Until then a wrong or
 * swapped file is invisible: it fails at runtime, on a device, as a push that never
 * arrives — the single most expensive place to discover a one-line config error.
 *
 * Both build types run under `./gradlew test`, so [BuildConfig.APPLICATION_ID] here
 * is the real applicationId of the variant under test — the same trick
 * [BiometricUnlockFlagTest] uses to assert about the shipped artefact rather than
 * about the build type's name.
 */
class GoogleServicesConfigTest {

    private companion object {
        const val RELEASE_APP_ID = "com.bittr.android"
        const val DEBUG_APP_ID = "com.bittr.android.regtest"

        /** Firebase projects, one per environment — see `two projects, not one` below. */
        const val RELEASE_PROJECT = "bittr-prod"
        const val DEBUG_PROJECT = "bittr-regtest"

        val PACKAGE_NAME = Regex("\"package_name\"\\s*:\\s*\"([^\"]+)\"")
        val PROJECT_ID = Regex("\"project_id\"\\s*:\\s*\"([^\"]+)\"")

        fun configFor(buildType: String): File =
            File(SourceTree.root, "app/src/$buildType/google-services.json")

        fun File.readConfig(): String {
            assertTrue(
                "Missing Firebase client config at ${repoPath()}. Config is keyed per " +
                    "package name; the debug and release builds have different ones, so " +
                    "neither build type can fall back to the other's file.",
                isFile,
            )
            return readText()
        }

        fun String.projectId(): String =
            PROJECT_ID.find(this)?.groupValues?.get(1)
                ?: error("No project_id in google-services.json — the file is not a Firebase config.")
    }

    @Test
    fun `the config for this build declares this build's package name`() {
        val buildType = if (BuildConfig.DEBUG) "debug" else "release"
        val packages = configFor(buildType).readConfig()
            .let { PACKAGE_NAME.findAll(it).map { m -> m.groupValues[1] }.toList() }

        assertTrue(
            "app/src/$buildType/google-services.json declares $packages, which does not " +
                "include ${BuildConfig.APPLICATION_ID}. Firebase resolves client config by " +
                "package name, so this build would find no matching client and " +
                "FirebaseApp.initializeApp would fail at launch. If the applicationId or the " +
                "debug applicationIdSuffix changed, the Firebase console app has to be " +
                "re-registered under the new name — the file cannot just be edited, the " +
                "mobilesdk_app_id is issued against the package name.",
            BuildConfig.APPLICATION_ID in packages,
        )
    }

    @Test
    fun `the two build types point at two separate Firebase projects`() {
        // BIT-39's open question 3, decided by the board: two projects, not one project
        // with two apps. A regtest build must not be able to hold a credential that
        // addresses production devices — the same failure class as BIT-32, where a
        // regtest build reads production notification state.
        //
        // The cheap "simplification" this guards against is someone copying one file
        // over the other to make a build work. That produces a green build and a
        // regtest APK registered against production, which is exactly the outcome the
        // decision exists to prevent, and it is silent.
        val debug = configFor("debug").readConfig().projectId()
        val release = configFor("release").readConfig().projectId()

        assertNotEquals(
            "The debug and release builds resolve to the same Firebase project ($debug). " +
                "The two-project split is deliberate: it is what stops a regtest build " +
                "from ever holding a credential that reaches production devices.",
            debug,
            release,
        )
        assertEquals("Debug build must use the regtest Firebase project.", DEBUG_PROJECT, debug)
        assertEquals("Release build must use the production Firebase project.", RELEASE_PROJECT, release)
    }

    @Test
    fun `each config declares exactly the one package it is for`() {
        // Guards the inverse of the test above: a file that lists *both* packages would
        // satisfy the package-name check for either build type, and would mean one
        // Firebase project serving both environments — the one-project option the board
        // did not choose, reintroduced by way of the config file.
        mapOf("debug" to DEBUG_APP_ID, "release" to RELEASE_APP_ID).forEach { (buildType, appId) ->
            val packages = configFor(buildType).readConfig()
                .let { PACKAGE_NAME.findAll(it).map { m -> m.groupValues[1] }.toList() }
            assertEquals(
                "app/src/$buildType/google-services.json must declare exactly one client, $appId, " +
                    "but declares $packages. Two clients in one file means one Firebase project " +
                    "backing both environments.",
                listOf(appId),
                packages,
            )
        }
    }
}
