package com.bittr.android

import java.io.File
import org.junit.Assert.assertNotNull
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

        /** The host half of the split BIT-108 forced. See the two tests at the bottom. */
        const val HOST_SCRIPT = "scripts/ci-wallet-instrumented.sh"

        /** The method that must plant and stop, rather than back up. */
        const val DEVICE_TRANSFER_TEST =
            "deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial"

        /**
         * A string literal that names a file or directory: no spaces, no
         * punctuation beyond what a path component carries. Everything else in
         * `WalletPaths` — were a message or a format string added — is not
         * something the instrumented test is expected to plant.
         */
        val PATH_COMPONENT = Regex("""^[A-Za-z0-9_.-]+$""")

        val STRING_LITERAL = Regex(""""([^"\n]*)"""")

        /**
         * A `bmgr restore` driven from inside the instrumented test.
         *
         * Matches the command as a string literal, with or without an
         * interpolated token, which is every shape `DeviceShell` can send —
         * it tokenises on whitespace and does not go through `sh`, so a restore
         * cannot be assembled any other way.
         */
        val IN_PROCESS_RESTORE = Regex(""""restore[\s"]""")

        /**
         * The constant `check-backup-set.sh` greps a device for, by name.
         *
         * Split from [MARKER_ASSIGNMENT] so this file does not itself contain
         * the assignment it is warning about — the same trap, one level up.
         */
        const val MARKER_NAME = "MARKER_PREFIX"

        /** `test_check_backup_set.sh`'s Kotlin-side grep, reproduced. */
        val MARKER_ASSIGNMENT = Regex("""\b$MARKER_NAME = "([^"]*)"""")

        /** What a greppable marker can look like: no spaces, nothing exotic. */
        val MARKER_VALUE = Regex("""^[A-Za-z0-9_.-]{8,}$""")
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

    /**
     * The host-side drift check reads a value, not a sentence.
     *
     * `android/scripts/test_check_backup_set.sh` keeps `check-backup-set.sh`'s
     * grep pattern and `BackupExclusionTest`'s marker in step by grepping both
     * files for the assignment and comparing. Its Kotlin side takes the **first**
     * match in the file, and `BackupExclusionTest` documents that constant at
     * length directly above it — so a comment that spells the assignment out
     * feeds the drift check a fragment of prose, which will never equal the
     * shell value. The check then fails for a reason that has nothing to do
     * with drift, or worse is "fixed" by loosening it.
     *
     * This reproduces that grep, on the raw file including comments, and
     * requires the first hit to be the real constant: a value that could
     * plausibly be grepped for on a device.
     */
    @Test
    fun `the marker constant is the first thing that looks like its own assignment`() {
        val raw = instrumentedTest.readText()

        val first = MARKER_ASSIGNMENT.find(raw)
        assertNotNull(
            "No `${MARKER_NAME} = \"…\"` in $INSTRUMENTED_TEST. check-backup-set.sh greps " +
                "the transport's tree for that value and test_check_backup_set.sh compares " +
                "the two; without it here, the host-side check can never match and rule 5 " +
                "has no verdict at all.",
            first,
        )

        val value = first!!.groupValues[1]
        assertTrue(
            "The first `${MARKER_NAME} = \"…\"` in $INSTRUMENTED_TEST is \"$value\", which " +
                "is not a value a grep on a device could match — almost certainly a " +
                "comment mentioning the assignment above the real constant. " +
                "test_check_backup_set.sh takes the first hit, so that comment becomes " +
                "what it compares against. Reword the comment; do not renumber the check.",
            value.isNotEmpty() && MARKER_VALUE.matches(value),
        )
    }

    /**
     * **BIT-108, as a build failure rather than as a comment.**
     *
     * `BackupExclusionTest` used to delete what it planted, run `bmgr restore`,
     * and assert none of it came back. On run 107 — the first time it ran on a
     * device — the device-transfer case produced an empty `<failure>` and every
     * test after it was skipped: `bmgr restore` kills the target process, and
     * the instrumentation runs inside it. A restore assertion cannot live in
     * the process being restored, and rewriting it more carefully does not
     * change that.
     *
     * It is also worth less than it looks. The restore only kills the process
     * when the framework has something to restore, so the assertion passes
     * exactly when nothing was backed up — the case where it had nothing to
     * check — and dies exactly when there was a set worth checking.
     *
     * The verdict therefore comes from `android/scripts/check-backup-set.sh`,
     * which greps the transport's own tree from the host and needs no surviving
     * process. This test is what stops a future reader reintroducing the
     * restore because "it would be stronger evidence": it would be a crash.
     */
    @Test
    fun `it does not restore into the process it asserts from`() {
        val instrumented = SourceTree.codeOf(instrumentedTest)

        assertTrue(
            "BackupExclusionTest drives `bmgr restore`. That kills the instrumentation " +
                "process — it is the observed cause of run 107's empty <failure> and of " +
                "InstalledBackupConfigurationTest never running (BIT-108). Whatever the " +
                "restore was meant to prove has to be observed from outside this process: " +
                "android/scripts/check-backup-set.sh greps the backup transport's own tree " +
                "from the host and needs no surviving process at all. If a restore really " +
                "is needed, drive it from the host in ci-wallet-instrumented.sh, not here.",
            !IN_PROCESS_RESTORE.containsMatchIn(instrumented),
        )
    }

    /**
     * The set has to still be there when the host looks.
     *
     * `check-backup-set.sh` runs after Gradle exits. A `bmgr wipe` in the
     * suite's `@After` therefore deletes the only artefact the run produces
     * before anything can read it — which is what happened on run 107, where
     * the one inspectable set survived only because the device-transfer crash
     * skipped `@After`. The wipe belongs before each backup, where it also
     * makes the surviving set unambiguously this run's.
     */
    @Test
    fun `it leaves the backup set on the transport for the host to inspect`() {
        val instrumented = SourceTree.codeOf(instrumentedTest)

        val after = instrumented.substringAfter("@After", "")
        assertTrue(
            "Expected an @After in BackupExclusionTest — it is what puts the device's " +
                "backup settings back, and a suite that leaves a device reconfigured is " +
                "the next run's flake.",
            after.isNotEmpty(),
        )

        val teardown = after.substringBefore("@Test")
        assertTrue(
            "BackupExclusionTest wipes the backup set in its @After. check-backup-set.sh " +
                "reads the transport's tree from the host after Gradle exits, so a wipe " +
                "there destroys the only evidence the run produces and leaves a green " +
                "grep of a set that is no longer on disk. Wipe before each backup instead " +
                "(BIT-108).",
            "wipe" !in teardown,
        )
    }

    /**
     * **The other half of BIT-108, and the half run 133 proved was still open.**
     *
     * Removing the in-process `bmgr restore` was necessary and not sufficient.
     * Run 133 (`0dd62293`) carried that fix and died in exactly the same place:
     * `deviceTransfer…` with an empty `<failure>`, `InstalledBackupConfigurationTest`
     * never reached. `bmgr backupnow` on the device-transfer path binds a backup
     * agent inside the target process and the framework kills that process when
     * it tears the agent down — so the backup is as unsurvivable as the restore
     * was, for the same reason and one step earlier.
     *
     * The cloud path may still back up in-process, and the asymmetry is real
     * rather than sloppy: `allowBackup="false"` makes the package ineligible
     * there, so no agent is ever bound. This test therefore cannot simply forbid
     * `backupnow` in the file — it has to forbid it in *this method*.
     */
    @Test
    fun `the device-transfer case does not drive the backup that kills it`() {
        val body = bodyOf(DEVICE_TRANSFER_TEST, SourceTree.codeOf(instrumentedTest))

        assertNotNull(
            "Could not find $DEVICE_TRANSFER_TEST in BackupExclusionTest. It is the case " +
                "BIT-108 is about; if it was renamed, rename it here too — and check that " +
                "NAME_ASCENDING still orders it last, because that is what decides which " +
                "path's set the host reads.",
            body,
        )

        assertTrue(
            "$DEVICE_TRANSFER_TEST drives `bmgr backupnow`. On the device-transfer path " +
                "the framework binds a backup agent inside this process and kills the " +
                "process when it tears the agent down, so this is the test killing itself " +
                "— the observed cause of the empty <failure> on runs 107 AND 133, and of " +
                "InstalledBackupConfigurationTest never running on either (BIT-108). The " +
                "in-process restore was removed for the same reason and it was not enough. " +
                "This method plants and stops; android/scripts/ci-wallet-instrumented.sh " +
                "drives the backup from the host, after Gradle exits, where there is no " +
                "instrumentation process left to kill.",
            "backupnow" !in body.orEmpty(),
        )
    }

    /**
     * The two halves are separated by a Gradle exit, so nothing but agreed
     * strings connects them.
     *
     * The host does not back up unless it finds the hand-off file the
     * instrumented test writes — deliberately, because backing up a package that
     * was never planted produces an empty set, and `check-backup-set.sh` cannot
     * tell an empty set from a clean one. That makes a drift between these two
     * literals **silent and green**: the suite passes, the host reports "nothing
     * to inspect", and the run looks like a pass with a warning nobody reads.
     *
     * Same argument as the `MARKER_PREFIX` drift check in
     * `test_check_backup_set.sh`, and the same remedy: fail in the `build` job,
     * seconds in, rather than in an emulator run that still goes green.
     */
    @Test
    fun `the hand-off the host waits for is the one the test writes`() {
        val instrumented = SourceTree.codeOf(instrumentedTest)
        val host = File(SourceTree.root, HOST_SCRIPT).readText()

        val handoff = Regex("""\bHANDOFF = "([^"]*)"""").find(instrumented)?.groupValues?.get(1)
        assertNotNull(
            "BackupExclusionTest no longer assigns a HANDOFF constant. It is what tells " +
                "ci-wallet-instrumented.sh that the wallet material was planted and the " +
                "device-transfer backup is worth driving (BIT-108).",
            handoff,
        )
        assertTrue(
            "BackupExclusionTest's HANDOFF is \"$handoff\", which does not appear in " +
                "$HOST_SCRIPT. The host greps for that exact string before driving the " +
                "device-transfer backup, so with these two out of step it will never back " +
                "up: the suite goes green, the set is never written, and the backup-set " +
                "inspection reports a clean grep of nothing. Update HANDOFF_MARKER there " +
                "in the same commit.",
            handoff.orEmpty().isNotEmpty() && handoff.orEmpty() in host,
        )

        val handoffFile = Regex("""\bHANDOFF_FILE = "([^"]*)"""")
            .find(instrumented)?.groupValues?.get(1)
        assertNotNull(
            "BackupExclusionTest no longer assigns a HANDOFF_FILE constant.",
            handoffFile,
        )
        assertTrue(
            "BackupExclusionTest writes its hand-off to \"$handoffFile\", which does not " +
                "appear in $HOST_SCRIPT's HANDOFF_PATH. The host reads that path with " +
                "`adb root`; a drift means it reads nothing and never backs up.",
            handoffFile.orEmpty().isNotEmpty() && handoffFile.orEmpty() in host,
        )
    }

    /**
     * The body of a named function, by brace matching from its signature.
     *
     * Textual rather than parsed, for the same reason everything else in this
     * file is: it runs on the JVM against a source file belonging to another
     * source set. Returns null if the function is not there, which the caller
     * reports as its own failure rather than as a vacuous pass.
     */
    private fun bodyOf(name: String, source: String): String? {
        val signature = source.indexOf("fun $name(")
        if (signature < 0) return null

        val open = source.indexOf('{', signature)
        if (open < 0) return null

        var depth = 0
        for (i in open until source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> if (--depth == 0) return source.substring(open, i + 1)
            }
        }
        return null
    }
}
