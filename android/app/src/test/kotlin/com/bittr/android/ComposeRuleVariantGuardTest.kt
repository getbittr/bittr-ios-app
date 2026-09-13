package com.bittr.android

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps `createComposeRule()` out of `:app`'s unit tests, where it cannot work on
 * every variant it will be run on.
 *
 * **The trap.** `createComposeRule()` launches a bare
 * `androidx.activity.ComponentActivity`, which has to be resolvable from the
 * manifest Robolectric reads or the rule throws in `before()`:
 *
 * ```
 * java.lang.RuntimeException: Unable to resolve activity for Intent {
 *   act=android.intent.action.MAIN cat=[android.intent.category.LAUNCHER]
 *   cmp=com.bittr.android/androidx.activity.ComponentActivity }
 * ```
 *
 * That activity is declared inside the `ui-test-manifest` artefact, which every
 * module here wires as `debugImplementation` — the wiring AndroidX documents,
 * because its intended consumer is the androidTest APK and that is only ever built
 * against debug. `:app` is the one module where the assumption breaks: its
 * `androidComponents` block enables unit tests on the **release** variant too (so
 * [BiometricUnlockFlagTest]'s claim about the shipped build actually executes), and
 * release never sees a `debugImplementation`.
 *
 * **Why the fix is here and not in `app/build.gradle.kts`.** `testImplementation
 * (ui-test-manifest)` is the obvious answer and it does not work — it is inert for
 * this, for a non-obvious reason recorded in the build file. The two configurations
 * that would work, `releaseImplementation` and `src/release/AndroidManifest.xml`,
 * both put a bare exported activity into the shipped APK in order to fix a test.
 * Routing through [MainActivity] costs nothing and ships nothing.
 *
 * **Why a source scan rather than a real assertion.** The failure is per-variant, so
 * the only test that can catch it is one that runs on the release variant — and a
 * test written with the bare rule is precisely the test that cannot run there. It
 * does not fail informatively; it fails in `before()` with an Intent-resolution
 * error that names no test, which is how BIT-97 and BIT-100 each closed green over
 * it and BIT-99 added a third case. A green `testDebugUnitTest` is not evidence
 * either way.
 *
 * Scoped to `:app` deliberately. Library modules (`:feature:*`,
 * `:core:designsystem`) have no release unit-test component, so `createComposeRule
 * ()` is correct there and stays allowed.
 */
class ComposeRuleVariantGuardTest {

    private companion object {
        const val TEST_DIR = "app/src/test"

        /** `createComposeRule()` / `createEmptyComposeRule()`, call site or import. */
        val BARE_RULE = Regex("""\bcreate(Empty)?ComposeRule\b""")
    }

    private fun appUnitTestSources(): List<File> {
        val dir = File(SourceTree.root, TEST_DIR)
        assertTrue(
            "$TEST_DIR does not exist, so this guard is scanning nothing and would pass " +
                "no matter what the tests do. If :app's unit tests moved, point the guard " +
                "at their new home — do not delete it.",
            dir.isDirectory,
        )
        val files = dir.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .toList()
        assertTrue("Found no Kotlin sources under $dir.", files.isNotEmpty())
        return files
    }

    /**
     * Scans [SourceTree.codeWithoutLiterals], not raw text — the distinction is the
     * one the other guards in this package learned the hard way, and it applies
     * twice here.
     *
     * Comments must go because six files in this directory name
     * `createComposeRule()` in their KDoc precisely to explain why they do not use
     * it. String literals must go because this test's own failure message names it
     * too. A guard that reads either as a violation fails on the documentation that
     * keeps the rule learnable, and gets deleted rather than obeyed. With literals
     * stripped, this file needs no self-exclusion: the pattern it holds is inside a
     * regex literal, so the scan cannot see it.
     */
    @Test
    fun `no app unit test uses the bare compose rule`() {
        val offenders = appUnitTestSources()
            .filter { BARE_RULE.containsMatchIn(with(SourceTree) { it.codeWithoutLiterals() }) }
            .map { with(SourceTree) { it.repoPath() } }
            .sorted()

        assertEquals(
            "These :app unit tests use createComposeRule(). It launches a bare " +
                "ComponentActivity, which is only in the manifest on debug — so they pass " +
                "under testDebugUnitTest and fail under testReleaseUnitTest with " +
                "\"Unable to resolve activity for Intent\", before reaching any assertion " +
                "(BIT-106). Use createAndroidComposeRule<MainActivity>() and set the " +
                "content with composeRule.activity.setContent { } inside runOnUiThread; " +
                "SettingsFlowTest and ScannerSeamTest are worked examples.\nOffenders: " +
                offenders.joinToString(),
            emptyList<String>(),
            offenders,
        )
    }

    /**
     * The other half of the invariant: this guard is only load-bearing while the
     * release variant actually has unit tests. If that gets switched off, 16 tests
     * stop running and everything stays green — so assert the switch is on rather
     * than trusting a comment in the build file.
     */
    @Test
    fun `the release variant still has unit tests enabled`() {
        val buildFile = File(SourceTree.root, "app/build.gradle.kts")
        assertTrue("app/build.gradle.kts does not exist.", buildFile.isFile)
        val source = buildFile.readText()

        assertTrue(
            "app/build.gradle.kts no longer enables unit tests on the release variant. " +
                "AGP creates a unit-test component for debug only, and `./gradlew test` " +
                "still reports success having skipped release entirely — which is how " +
                "BiometricUnlockFlagTest's assertion about the SHIPPED build was silently " +
                "dead before. If this was removed on purpose, say so here and delete this " +
                "test; do not leave the release variant quietly untested.",
            Regex("""withBuildType\(\s*"release"\s*\)""").containsMatchIn(source) &&
                Regex("""UNIT_TEST_TYPE\b[\s\S]{0,80}?enable\s*=\s*true""").containsMatchIn(source),
        )
    }
}
