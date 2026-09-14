package com.bittr.android.core.wallet.ldk.seed

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

/**
 * **The channel `KeystoreKeyInfoTest`'s observations reach the host on. BIT-114.**
 *
 * The long form of the argument is in `:app`'s copy of this object, next to
 * `BackupExclusionTest`. The short form: the JUnit XML AGP writes for a
 * connected test comes from `com.android.ddmlib.testrunner.XmlTestRunListener`,
 * which has a `system-err` element and **no `system-out` element at all**, so
 * the `println`s these tests emit have never reached
 * `check-wallet-instrumented-results.py` and never could. They go to a file too,
 * and `ci-wallet-instrumented.sh` reads it off the device after Gradle exits.
 *
 * This module's half is not decoration. `recordTheObservedSecurityLevel` is a
 * test that deliberately asserts almost nothing — API 26–27 legitimately falls
 * back to a software keystore — so its *output* is the whole of its value, and
 * the BIT-18 device matrix is fed from it. A recording test whose recording is
 * discarded is a test that costs an emulator boot and reports nothing.
 *
 * Duplicated rather than shared with `:app`: the two modules' suites run in
 * different Gradle tasks against different packages, and the only thing they
 * must agree on is [FILE_NAME], which
 * `android/scripts/test_ci_wallet_host_phase.sh` pins across both files and the
 * host script in the build job.
 *
 * The package under test here is this test APK itself — a library module's
 * instrumented tests are self-instrumenting — so [FILE_NAME] lands under
 * `…core.wallet.ldk.test`'s data directory, which is why the host globs
 * `/data/data/com.bittr.android*` instead of naming one package.
 */
internal object EvidenceLog {

    /** See `:app`'s copy. Pinned against it and against the host script. */
    const val FILE_NAME = "instrumentation_evidence.txt"

    /** Truncated once per instrumentation process, on first use. */
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
     * A write failure is reported and swallowed: the lines are a record, and
     * turning a failure to record into a failure of the thing being recorded
     * would make a Keystore result depend on a file system.
     */
    fun record(line: String) {
        println(line)
        try {
            synchronized(this) { file.appendText(line.trimEnd() + "\n") }
        } catch (throwable: Throwable) {
            println(
                "EVIDENCE_LOG_WRITE_FAILED ${throwable.javaClass.name}: ${throwable.message}. " +
                    "The KEYSTORE_KEY_INFO lines for this run reach only stdout (BIT-114).",
            )
        }
    }
}
