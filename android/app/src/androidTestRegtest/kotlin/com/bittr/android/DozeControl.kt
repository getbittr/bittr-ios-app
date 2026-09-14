package com.bittr.android

import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry

/**
 * Putting the device into Doze and App Standby, and reading back whether it went.
 *
 * BIT-132, K8. `android/docs/wallet-node-device-tests.md` §4 settled the shape:
 * the nightly job has 90 minutes and App Standby buckets move on the order of
 * hours, so the soak has to **drive** the platform into the state rather than
 * wait for it to arrive there. This object is that driving, in one place because
 * [K8DozeMachineryTest] and [K8ChannelFreshnessTest] both need it and a second
 * copy would drift.
 *
 * ## A forced state is a weaker claim, and it is labelled rather than hidden
 *
 * Everything here is the platform being *told* what to believe. `force-idle`
 * skips the screen-off and unplugged preconditions the real thing waits on, and
 * `set-standby-bucket` writes a bucket the platform is free to re-derive a
 * moment later. So a green K8 says *"the node survived a forced deep-idle
 * window"*, which is strictly less than *"the node survived a device that dozed
 * off on its own overnight"*.
 *
 * Both tests say so in their own assertion text rather than leaving the reader
 * of a green row to work it out, and [reading] is what puts the actual observed
 * states into the evidence line — so a future reader can tell a run that reached
 * `IDLE` from a run that asked to and did not.
 *
 * ## Why these commands and not others
 *
 * - **`dumpsys battery unplug` first.** `force-idle` sets `mForceIdle`, which
 *   bypasses the charging check inside the controller — but a charging state
 *   that changes underneath can step the state machine back to `ACTIVE` while
 *   the window is open, and then the soak measures an awake device. Unplugging
 *   removes the input rather than racing it. [leaveForcedIdle] resets it, since
 *   a battery left unplugged leaks into every test that runs afterwards on the
 *   same emulator.
 * - **`dumpsys deviceidle enable deep`.** `force-idle` refuses with *"Unable to
 *   go deep idle; not enabled"* when deep idle is off, which is the state some
 *   images and some previous tests leave behind. Enabling is idempotent.
 * - **`am set-standby-bucket … rare`, read back and *recorded*, never
 *   asserted.** See [setStandbyBucket]. This is the one decision in this file
 *   that changes what K8 is allowed to claim.
 *
 * ## No shell redirection anywhere in this file
 *
 * `UiAutomation.executeShellCommand` hands its string to `Runtime.exec`, which
 * splits on whitespace and executes the binary directly — there is no `sh`, so
 * `>` would be passed to `dumpsys` as a literal argument and the file would
 * never appear. Every command below is therefore a plain argv.
 *
 * That is also why the two hand-off directions K8 uses are asymmetric, and it is
 * worth stating here because it looks like an inconsistency otherwise:
 *
 * - **device → host** goes through logcat ([announce]), which needs no file.
 * - **host → device** is a file under `/data/local/tmp` the *host* writes with
 *   `adb shell`, read here with a plain `cat`. That direction has a real shell
 *   on the writing side, and it is the mechanism K7's hand-off already uses.
 */
internal object Doze {

    /**
     * The logcat tag the host greps for, and the prefix the gate lifts out of
     * `<system-out>`.
     *
     * One string for both channels on purpose. The JUnit XML is what survives
     * into the artefact and the annotation; logcat is what the host can read
     * *while the test is still running*, which is the only reason it is here at
     * all. A reader comparing the two should not have to learn two names.
     *
     * Pinned against `android/scripts/k8-doze-soak.sh` by
     * `android/scripts/test_k8_doze_soak.sh`.
     */
    const val TAG = "K8_DOZE_SOAK"

    /**
     * The installed application id, derived rather than written down.
     *
     * `com.bittr.android.regtest` today — the namespace plus the debug
     * `applicationIdSuffix` — and getting it wrong is the bug BIT-108's host
     * phase shipped with, where `am` commands against a package that does not
     * exist exit 0 and do nothing. Reading it from the context under test means
     * there is no second copy on the device side to drift; the *host* side has
     * one, and `test_k8_doze_soak.sh` pins that one against `build.gradle.kts`.
     */
    val packageUnderTest: String
        get() = InstrumentationRegistry.getInstrumentation().targetContext.packageName

    /**
     * Run a shell command as the shell user and return everything it printed.
     *
     * `UiAutomation` runs as uid 2000, which holds `DUMP` and may drive
     * `deviceidle` and `set-standby-bucket`; the app's own uid may not. Doze
     * does not suspend this channel, which is what makes it usable from *inside*
     * the window.
     */
    fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand(command)
            .let { descriptor ->
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
                    it.readBytes().decodeToString()
                }
            }

    /** `dumpsys deviceidle get deep` — `ACTIVE`, `IDLE_PENDING`, `IDLE`, and so on. */
    fun deepIdleState(): String = shell("dumpsys deviceidle get deep").trim()

    /** `dumpsys deviceidle get light`, recorded alongside the deep state for context. */
    fun lightIdleState(): String = shell("dumpsys deviceidle get light").trim()

    /** `am get-standby-bucket` — 10 active, 20 working set, 30 frequent, 40 rare, 45 restricted. */
    fun standbyBucket(): String = shell("am get-standby-bucket $packageUnderTest").trim()

    /**
     * Ask for a bucket, and return what the platform says it is afterwards.
     *
     * **Deliberately not an assertion, and this is the decision that narrows
     * K8's claim.** An app with a live foreground service is one the platform
     * re-derives as `ACTIVE`, so a read-back of `10` here is the expected
     * outcome of the mitigation under test *working* — the foreground service is
     * exactly what is supposed to keep the wallet out of the restricted buckets.
     * Asserting `RARE` would turn that into a red, and a red that says "the
     * wallet was protected" is the most misleading verdict this suite could
     * produce.
     *
     * So the request and the read-back both go into the evidence line, and the
     * reader gets to see which one happened. A future run where an unprotected
     * build *does* sit in `RARE` is then a difference in the record rather than
     * a difference in a pass.
     */
    fun setStandbyBucket(bucket: String): String {
        shell("am set-standby-bucket $packageUnderTest $bucket")
        return standbyBucket()
    }

    /**
     * Put the device into forced deep idle and report what it did.
     *
     * The controller's `force-idle` shell command steps the state machine
     * (`IDLE_PENDING` → `SENSING` → `LOCATING` → `IDLE`) in a loop before it
     * returns, so the reading taken straight afterwards is meaningful rather
     * than a race. If it is not `IDLE`, the caller has an infrastructure verdict
     * — this image's Doze machinery is not available — and the two K8 tests
     * report that differently from a node failure, because they are different
     * news.
     */
    fun enterForcedIdle(): IdleReading {
        shell("dumpsys battery unplug")
        val enabled = shell("dumpsys deviceidle enable deep").trim()
        val forced = shell("dumpsys deviceidle force-idle").trim()
        return IdleReading(
            enableOutput = enabled,
            forceOutput = forced,
            deep = deepIdleState(),
            light = lightIdleState(),
        )
    }

    /**
     * Come back out, and leave the emulator as it was found.
     *
     * Called from a `finally` in both tests. A device left in forced idle with
     * its battery unplugged is a device every later test on the same boot runs
     * against, and the symptom — a suite that starts failing from wherever K8
     * happens to sit in the run order — names K8 last of anything.
     */
    fun leaveForcedIdle() {
        runCatching { shell("dumpsys deviceidle unforce") }
        runCatching { shell("dumpsys battery reset") }
    }

    /**
     * Emit one observation to both channels: logcat now, JUnit XML at the end.
     *
     * `println` is what `check-wallet-regtest-results.py` lifts out of
     * `<system-out>` into the job's annotation — on this public repository that
     * annotation is the only channel readable without a token. `Log.i` is what
     * `android/scripts/k8-doze-soak.sh` polls while the test is still inside its
     * idle window, which the XML cannot answer because it does not exist yet.
     */
    fun announce(line: String) {
        Log.i(TAG, line)
        println("$TAG $line")
    }

    /**
     * Stay inside the window for [totalMs], reporting every [TICK_MS].
     *
     * The reporting is not decoration. AGP's instrumentation runner watches for
     * output and a silent multi-minute test is the shape that gets reported as
     * *"Test failed to run to completion"* — a harness verdict that would be
     * read as a K8 failure. It is also the only record of what the device's idle
     * state was *during* the window rather than at its two ends, which is the
     * reading that distinguishes a soak from a pair of dumpsys calls.
     *
     * @return every deep-idle state observed, in order.
     */
    fun holdWindow(totalMs: Long, label: String): List<String> {
        val observed = mutableListOf(deepIdleState())
        val deadline = System.currentTimeMillis() + totalMs
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(minOf(TICK_MS, maxOf(0L, deadline - System.currentTimeMillis())))
            val state = deepIdleState()
            observed += state
            announce(
                "tick window=$label remainingMs=${maxOf(0L, deadline - System.currentTimeMillis())} " +
                    "deepIdle=$state bucket=${standbyBucket()}",
            )
        }
        return observed
    }

    /** 30s. Short enough to keep the runner hearing from us, long enough not to be the soak. */
    const val TICK_MS = 30_000L

    /** What [enterForcedIdle] saw, kept together so an assertion can print all of it. */
    internal data class IdleReading(
        val enableOutput: String,
        val forceOutput: String,
        val deep: String,
        val light: String,
    ) {
        val isDeepIdle: Boolean get() = deep == DEEP_IDLE

        override fun toString(): String =
            "deep=$deep light=$light enable='$enableOutput' force='$forceOutput'"
    }

    /** `DeviceIdleController`'s own name for the state this suite is about. */
    const val DEEP_IDLE = "IDLE"
}
