package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the one line that makes every `assertVisible: id:` in `shared/flows/` work.
 *
 * Compose's `Modifier.testTag` is invisible to UIAutomator — and so to Maestro —
 * unless an ancestor sets `testTagsAsResourceId = true`, which bridges the tag onto
 * the accessibility tree as a resource id. It is set once, on the app root in
 * `MainActivity.kt`.
 *
 * **Why this needs a source scan rather than a real assertion.** Robolectric reads
 * the Compose semantics tree directly, so [AppLaunchTest] and
 * [com.bittr.android.feature.signup.SignupStartScreenTestIdsTest] both pass with the
 * line present *or* absent — they cannot see the bridge, only the tags. Nothing on
 * the JVM can fail when it is deleted. The alternative to this guard is not a better
 * test; it is finding out on an emulator.
 *
 * **Why it is worth guarding at all.** Deleting it is a one-line change that leaves
 * the app looking completely correct on screen and every unit test green, while
 * every flow on both suites fails with "element not found" — the same symptom as a
 * broken emulator, a missing tag, or a bad selector. It is the highest
 * blast-radius, lowest-visibility line in the Android tree.
 *
 * The same reasoning covers `core.launchComplete`: every flow gates on it via the
 * iOS `helpers/wait_for_launch.yaml`, so if the root stops carrying it, all of them
 * hang until their `extendedWaitUntil` times out.
 *
 * This checks the property is *present*, not where it lives — the root can be
 * restructured freely as long as it still enables the bridge.
 */
class TestTagsAsResourceIdGuardTest {

    private companion object {
        const val ROOT_FILE = "app/src/main/kotlin/com/bittr/android/MainActivity.kt"
    }

    private val rootSource: String by lazy {
        val file = File(SourceTree.root, ROOT_FILE)
        assertTrue(
            "$ROOT_FILE does not exist. It holds `testTagsAsResourceId = true`, which is " +
                "what makes Compose test tags visible to Maestro at all. If the app root " +
                "moved, point this guard at its new home — do not delete the guard.",
            file.isFile,
        )
        file.readText()
    }

    @Test
    fun `the app root bridges Compose test tags onto the accessibility tree`() {
        assertTrue(
            "$ROOT_FILE no longer sets `testTagsAsResourceId = true`. Without it every " +
                "Modifier.testTag in the app is invisible to Maestro, so every " +
                "`assertVisible: id:` in shared/flows/ fails with \"element not found\" " +
                "while the app renders perfectly on screen. No JVM test can catch this — " +
                "Robolectric reads the semantics tree directly and passes either way.",
            Regex("""testTagsAsResourceId\s*=\s*true""").containsMatchIn(rootSource),
        )
    }

    @Test
    fun `the app root still carries the launch-complete gate`() {
        assertTrue(
            "$ROOT_FILE no longer tags the root with TestID.Core.launchComplete. Every " +
                "flow waits on core.launchComplete before its first assertion, so without " +
                "it they do not fail fast — they hang until extendedWaitUntil times out.",
            Regex("""testTag\(\s*TestID\.Core\.launchComplete\s*\)""").containsMatchIn(rootSource),
        )
    }
}
