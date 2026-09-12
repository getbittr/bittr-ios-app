package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **Keeps `BackupExclusionTest` pointed at the paths the wallet actually uses.**
 *
 * `BackupExclusionTest` is instrumented: it needs a device, so nothing in this
 * container or in CI today can tell you whether it still asserts about the
 * right files. It also cannot reference `WalletPaths` — it runs against
 * `:app`, which deliberately does not depend on `:core:wallet-ldk` yet, and a
 * test-only dependency would pull the bdk/ldk-node native libraries into the
 * test APK for six strings. So the path names are literals over there.
 *
 * Duplicated literals in a test that never runs are how a security test quietly
 * stops covering anything: rename `ldk_state` in `WalletPaths`, and the
 * instrumented test goes on planting a file at the old path, finding it absent
 * from the backup set, and passing. This test runs on the JVM, on every `check`,
 * and fails that rename.
 *
 * It also asserts the class is *runnable*, not merely present. A
 * `connectedAndroidTest` step that runs zero tests exits 0, and an `@Ignore`
 * is indistinguishable from a pass in an exit code — BIT-101 says what lands
 * has to be visible in a run's test count.
 */
class BackupExclusionInstrumentationGuardTest {

    private companion object {
        const val INSTRUMENTED_TEST =
            "app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt"
        const val WALLET_PATHS =
            "core/wallet-ldk/src/main/kotlin/com/bittr/android/core/wallet/ldk/state/" +
                "WalletPaths.kt"

        /**
         * A string literal that names a file or directory: no spaces, no
         * punctuation beyond what a path component carries. Everything else in
         * `WalletPaths` — were a message or a format string added — is not
         * something the instrumented test is expected to plant.
         */
        val PATH_COMPONENT = Regex("""^[A-Za-z0-9_.-]+$""")

        val STRING_LITERAL = Regex(""""([^"\n]*)"""")
    }

    private val instrumentedTest = File(SourceTree.root, INSTRUMENTED_TEST)
    private val walletPaths = File(SourceTree.root, WALLET_PATHS)

    @Test
    fun `the instrumented test exists where connectedAndroidTest will find it`() {
        assertTrue(
            "BIT-20 rule 5's behavioural half is $INSTRUMENTED_TEST, and it is not " +
                "there. BackupExclusionRulesTest, data_extraction_rules.xml and " +
                "docs/wallet-security-properties.md all name it; if it has been moved, " +
                "move this guard with it rather than deleting the guard.",
            instrumentedTest.isFile,
        )
        assertTrue(
            "Expected $WALLET_PATHS — this guard compares the two files and cannot " +
                "compare against one that is not there.",
            walletPaths.isFile,
        )
    }

    @Test
    fun `it plants a file at every path WalletPaths defines`() {
        val instrumented = SourceTree.codeOf(instrumentedTest)

        val expected = STRING_LITERAL.findAll(SourceTree.codeOf(walletPaths))
            .map { it.groupValues[1] }
            .filter { PATH_COMPONENT.matches(it) }
            .toSortedSet()

        assertTrue(
            "Found no path literals in $WALLET_PATHS. Either the file has changed shape " +
                "or this scan has drifted — and a scan that matches nothing passes " +
                "without checking anything, which is worse than no guard at all.",
            expected.isNotEmpty(),
        )

        val missing = expected.filterNot { """"$it"""" in instrumented }
        assertTrue(
            "WalletPaths names $missing, and BackupExclusionTest does not plant anything " +
                "there. A wallet file the instrumented test never writes is a wallet file " +
                "it cannot prove stays out of a backup set — and the test would still be " +
                "green. Add the path to the marker list, or to the decoys if it is not " +
                "wallet material.",
            missing.isEmpty(),
        )
    }

    @Test
    fun `it is runnable, and every case counts`() {
        val instrumented = SourceTree.codeOf(instrumentedTest)

        val tests = Regex("""@Test""").findAll(instrumented).count()
        assertTrue(
            "BackupExclusionTest declares $tests @Test methods. BIT-101 asks for the " +
                "cloud-backup path, the device-transfer path, and the precondition that " +
                "makes either of them mean anything — three, at least.",
            tests >= 3,
        )
        assertTrue(
            "BackupExclusionTest carries an @Ignore. An ignored test and a passing test " +
                "are the same exit code, and this is the only evidence that rule 5 holds " +
                "in behaviour rather than in configuration. If it cannot run, say so in " +
                "docs/wallet-security-properties.md — do not silence it here.",
            "@Ignore" !in instrumented,
        )
        assertTrue(
            "BackupExclusionTest no longer drives bmgr. It is the only tool that makes " +
                "the platform produce a real backup set; without it the class is reading " +
                "configuration again, which BackupExclusionRulesTest already does.",
            "bmgr" in instrumented,
        )
    }
}
