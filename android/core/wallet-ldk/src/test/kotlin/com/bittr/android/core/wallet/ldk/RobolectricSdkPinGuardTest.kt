package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.WalletSourceTree.modulePath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **A named test that stops running is worse than a test that fails.**
 *
 * This module's definition of done is "each claim naming the test that proves
 * it". That makes a silently-skipped test the most expensive failure available
 * here: the security statement still names it, the build still goes green, and
 * the claim is now backed by nothing.
 *
 * It has already happened once. `compileSdk` moved to 37; this module sets no
 * `targetSdk`, so the library manifest's `targetSdkVersion` followed it; and
 * Robolectric — which defaults to that value when a class does not pin one —
 * could not instantiate an SDK past 36. Three classes stopped running:
 * `BlobDestroyedRecoversTest` (BIT-8 rule 3, the one the definition of done
 * names by name), `TransientKeystoreFailureAbortsTest` (BIT-20 rule 3) and
 * `StateDirLocationTest` (BIT-20 rule 5, layer 3). Between them, fourteen tests
 * and three decided rules.
 *
 * They failed loudly *that* time, as `initializationError`. They would not have
 * if the class had been added after the bump rather than before it — a new
 * Robolectric test written today against an un-instantiable target is reported
 * as an error too, but a class that is *filtered out* for other reasons is not,
 * and the general shape of "the runner quietly declined to run it" is what this
 * guard is aimed at.
 *
 * So the rule is: **in this module, a Robolectric class states the API levels
 * its claim holds at, in its own source.** That is not ceremony. The deliverable
 * is a per-API-level security statement, and a level inherited from
 * `compileSdk` is a level nobody chose — it changes when a Gradle bump says so,
 * not when someone decides the claim now holds somewhere else.
 *
 * Fixing a failure here is one line: add `@Config(sdk = [...])` naming the
 * levels, and say in the KDoc why those. The house triple is 26 / 34 / 36 —
 * `minSdk`, the level the CI emulator boots, and the newest Robolectric 4.16.1
 * can instantiate — but it is a default, not a requirement; `KeystoreKeySpecTest`
 * pins 28 / 34 for a documented reason of its own.
 */
class RobolectricSdkPinGuardTest {

    private companion object {
        const val RUNNER = "@RunWith(RobolectricTestRunner::class)"
        const val PIN = "@Config(sdk"
    }

    @Test
    fun `every Robolectric test in this module pins the API levels it runs at`() {
        // Comments stripped: the KDoc above names both markers on purpose, and
        // so does every test that explains its own choice of levels.
        val unpinned = WalletSourceTree.testSources()
            .filter { RUNNER in WalletSourceTree.codeOf(it) }
            .filterNot { PIN in WalletSourceTree.codeOf(it) }
            .map { it.modulePath() }

        assertTrue(
            "These Robolectric classes do not pin their API levels, so they run at " +
                "whatever the library manifest's targetSdkVersion happens to be — which " +
                "in this module is compileSdk, because no targetSdk is set. When that " +
                "passes what Robolectric ships, the class stops running. The claims here " +
                "are the ones the definition of done names a test for, so a claim whose " +
                "test quietly stopped running is the worst outcome this suite has.\n\n  " +
                unpinned.joinToString("\n  ") +
                "\n\nAdd @Config(sdk = [26, 34, 36]) — minSdk, the CI emulator's level, " +
                "and the newest Robolectric 4.16.1 can instantiate — and say in the KDoc " +
                "why those levels and not others.",
            unpinned.isEmpty(),
        )
    }

    @Test
    fun `the guard is actually scanning the tests it claims to`() {
        // A scan that walks an empty tree passes silently, which would make this
        // guard an instance of the exact problem it exists to catch.
        val sources = WalletSourceTree.testSources()
        assertTrue(
            "Expected to find at least one Robolectric test among the scanned test " +
                "sources. Finding none means the scan is not looking where it thinks, " +
                "not that the module has no Robolectric tests.",
            sources.any { RUNNER in WalletSourceTree.codeOf(it) },
        )
        assertTrue(
            "Expected to find BlobDestroyedRecoversTest — the test the definition of " +
                "done names for BIT-8 rule 3 — among the scanned test sources.",
            sources.any { it.name == "BlobDestroyedRecoversTest.kt" },
        )
    }
}
