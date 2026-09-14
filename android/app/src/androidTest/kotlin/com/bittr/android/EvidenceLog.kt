package com.bittr.android

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

/**
 * **The channel the per-run observations actually reach the host on. BIT-114.**
 *
 * Every `BACKUP_EXCLUSION` line this suite produces used to be a bare `println`,
 * on the assumption that the runner files instrumentation stdout into
 * `<system-out>` in the JUnit XML, where
 * `android/scripts/check-wallet-instrumented-results.py` reads it from and lifts
 * it into an annotation. **It does not, and it cannot.** The class that writes
 * that XML for a connected test is `com.android.ddmlib.testrunner
 * .XmlTestRunListener` (AGP's `CustomTestRunListener` extends it and overrides
 * no part of this), and in the ddmlib this AGP is built against it has a
 * `system-err` element and **no `system-out` element at all** — no constant, no
 * writer, nothing to switch on. So every run from 110 onward reported "no
 * BACKUP_EXCLUSION or KEYSTORE_KEY_INFO line reached `<system-out>`", including
 * runs 139 and 140, which were green with every test run and every print
 * reached. No instrumentation runner argument changes that; the element is not
 * something this AGP version declines to fill in, it is one it does not know
 * about.
 *
 * So the lines go to a file instead, and `ci-wallet-instrumented.sh` reads it off
 * the device with `adb root` once Gradle has exited — the same hand-off shape
 * BIT-108 used to move the device-transfer backup out of the process it kills,
 * and for the same reason: a channel that is missing exactly when something went
 * wrong is not a channel. See [HANDOFF] in `BackupExclusionTest` for the other
 * instance of it.
 *
 * **Why the `println` stays.** It costs nothing, it is what a local
 * `am instrument` run and `adb logcat -s System.out` show, and the host phase
 * falls back to grepping logcat for these prefixes when the file cannot be read
 * (an image that refuses `adb root`, an APK Gradle uninstalled). Two channels
 * for a diagnostic is not belt-and-braces for its own sake: the whole defect
 * this class exists to fix was one channel that failed silently.
 *
 * **Why [FILE_NAME] sits under `getNoBackupFilesDir()`.** It is written into the
 * data directory of the very app whose backup set this suite inspects, so it has
 * to be somewhere the set cannot reach — `HANDOFF_FILE` is there for the same
 * reason. Note that these lines quote `MARKER_PREFIX`, the literal
 * `check-backup-set.sh` greps the transport's tree for. That adds no new false
 * halt: the wallet material this file describes is planted under the same
 * `no_backup` directory, so any set containing this file already contains the
 * plant, and the halt it would declare is one that was earned.
 *
 * Deliberately duplicated in `:core:wallet-ldk`'s androidTest sources rather
 * than shared. The two modules' suites run in different Gradle tasks against
 * different packages, and the only thing they must agree on is [FILE_NAME],
 * which `android/scripts/test_ci_wallet_host_phase.sh` pins across both files
 * and the host script in the build job.
 */
internal object EvidenceLog {

    /**
     * The file name the host reads. Changing it here means changing it in
     * `:core:wallet-ldk`'s copy and in `ci-wallet-instrumented.sh`; the pin in
     * `test_ci_wallet_host_phase.sh` fails the build job if only one moves.
     */
    const val FILE_NAME = "instrumentation_evidence.txt"

    /**
     * Truncated once per instrumentation process, on first use.
     *
     * Not once per test and not in an `@Before`: the suite spans several classes
     * in one process and each of them appends, so anything narrower would throw
     * away the earlier classes' lines. Once per process is also what makes a
     * stale file impossible to mistake for this run's — the AVD is restored from
     * a cached snapshot and the app's data directory can outlive a run, which is
     * the same hazard `recordTheDeviceState` clears the hand-off for.
     */
    private val file: File by lazy {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        File(context.noBackupFilesDir, FILE_NAME).apply {
            parentFile?.mkdirs()
            writeText("")
        }
    }

    /**
     * Prints [line] and appends it to [FILE_NAME].
     *
     * A write failure is reported and swallowed. Failing the test would convert
     * a diagnostics problem into a red run on the one suite whose red is read as
     * a BIT-20 §5.3 halt, and the absence of the lines is already reported by
     * the gate — loudly, and as an absence rather than as a device finding.
     */
    fun record(line: String) {
        println(line)
        try {
            synchronized(this) { file.appendText(line.trimEnd() + "\n") }
        } catch (throwable: Throwable) {
            println(
                "EVIDENCE_LOG_WRITE_FAILED ${throwable.javaClass.name}: ${throwable.message}. " +
                    "The BACKUP_EXCLUSION lines for this run reach only stdout, so expect the " +
                    "host to fall back to logcat or to report them absent (BIT-114).",
            )
        }
    }
}
