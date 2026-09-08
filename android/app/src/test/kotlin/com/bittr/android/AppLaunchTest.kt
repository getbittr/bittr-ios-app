package com.bittr.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The JVM half of `shared/flows/android/scaffold_smoke.yaml`.
 *
 * The smoke flow is two claims — *the app launches* and *the first screen asserts* —
 * and until this test existed only the second half was covered off-emulator.
 * [com.bittr.android.feature.signup.SignupStartScreenTestIdsTest] composes
 * `SignupStartScreen` directly, which deliberately skips everything the launch
 * actually exercises:
 *
 *   - **Hilt.** `BittrApplication` is `@HiltAndroidApp` and `MainActivity` is
 *     `@AndroidEntryPoint`. A missing binding, or an `@InstallIn` on the wrong
 *     component, throws at activity attach — not at compile time.
 *   - **The manifest.** `android:name=".BittrApplication"` is what makes the Hilt
 *     application the one Android instantiates. Drop it and injection fails at run
 *     time with the DI graph itself perfectly correct.
 *   - **The theme.** `MainActivity` resolves `@style/Theme.Bittr` before any
 *     composition happens.
 *   - **Navigation.** `BittrNavHost`'s start destination is what decides that a
 *     fresh install lands on signup at all.
 *
 * Every one of those fails as a *launch crash*, which on the emulator reads as
 * "Maestro could not find the element" — indistinguishable from a broken flow, a
 * missing test tag, or a bad emulator, and it costs a full boot to find out. Here
 * it costs seconds and names the cause.
 *
 * **What this still does not cover**, and what only the emulator can prove:
 * `testTagsAsResourceId`. Robolectric reads the Compose semantics tree directly, so
 * these assertions pass whether or not the tags are bridged onto the accessibility
 * tree that Maestro actually reads. That single line is guarded separately, by
 * source, in [TestTagsAsResourceIdGuardTest].
 *
 * The assertions below are the flow's steps in the flow's order. If a step is added
 * to `scaffold_smoke.yaml`, add it here too.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AppLaunchTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun `app launches and the smoke flow's first screen is on it`() {
        // scaffold_smoke.yaml: extendedWaitUntil visible id core.launchComplete.
        // Reaching this assertion at all is the launch claim — the rule has already
        // constructed the Hilt graph, inflated the activity and run the composition.
        composeRule.onNodeWithTag(TestID.Core.launchComplete).assertIsDisplayed()

        // scaffold_smoke.yaml: the three assertVisible steps.
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.headerLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.createWalletButton).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.restoreButton).assertIsDisplayed()
    }

    /**
     * Names the cause of one specific launch crash.
     *
     * The test above would also fail if `android:name` were missing from the manifest
     * — `@AndroidEntryPoint` injection throws when the application is not a Hilt one —
     * but it would fail as "element not found", which is the same message as a dozen
     * unrelated problems. This asserts the wiring directly so the report says which.
     *
     * Deliberately not asserted here: the biometric flag. That invariant is about the
     * APK rather than the launch, it is expressed against `APPLICATION_ID` rather than
     * the build type, and [BiometricUnlockFlagTest] already covers both branches of it.
     */
    @Test
    fun `the manifest points Android at the Hilt application`() {
        val app = composeRule.activity.application
        assertTrue(
            "The launched application is ${app.javaClass.name}, not a BittrApplication. " +
                "android:name=\".BittrApplication\" in AndroidManifest.xml is what makes " +
                "the @HiltAndroidApp application the one Android instantiates; without it " +
                "every @AndroidEntryPoint fails to inject at run time while the DI graph " +
                "itself compiles perfectly.",
            app is BittrApplication,
        )
    }
}
