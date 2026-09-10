package com.bittr.android.core.keystore.probe

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry

/**
 * The bits both phases need: which case is running, and how a result gets out of the device.
 */
object K1Harness {

    /** `adb logcat -s K1:I` after `adb logcat -c` is how the driver script reads results. */
    const val TAG = "K1"

    private const val ARG_CASE = "k1_case"

    val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext

    /**
     * Which mutation this invocation is part of, passed as `-e k1_case M2`.
     *
     * No default. A missing argument means the driver script and the test disagree about what
     * is being run, and defaulting to some case would produce a result table row that does not
     * describe what happened.
     */
    fun case(): K1Case {
        val raw = InstrumentationRegistry.getArguments().getString(ARG_CASE)
            ?: throw IllegalStateException(
                "missing instrumentation argument -e $ARG_CASE <case>; " +
                    "run this through android/scripts/k1-lockscreen-matrix.sh",
            )
        return K1Case.byId(raw)
    }

    fun isDeviceSecure(): Boolean =
        context.getSystemService(KeyguardManager::class.java).isDeviceSecure

    /**
     * Emit one machine-readable line per phase.
     *
     * Both channels on purpose. Logcat is what the script parses (it clears the buffer before
     * each phase, so there is no staleness window). `sendStatus` puts the same facts in the
     * `am instrument -r` stream, which survives in CI logs even when a later step wipes the
     * logcat buffer. The test's own pass/fail is a third, independent signal — the script
     * checks the instrumentation exit status too, and treats a green exit with no result line
     * as a harness failure rather than as a pass.
     */
    fun report(phase: String, case: K1Case, facts: Map<String, String>) {
        val all = linkedMapOf(
            "phase" to phase,
            "case" to case.id,
            "api" to Build.VERSION.SDK_INT.toString(),
            "device" to "${Build.MANUFACTURER}/${Build.MODEL}",
            "build" to Build.FINGERPRINT,
        ).apply { putAll(facts) }

        Log.i(TAG, all.entries.joinToString(" ") { (k, v) -> "$k=${v.replace(' ', '_')}" })

        val bundle = Bundle().apply { all.forEach { (k, v) -> putString("k1_$k", v) } }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, bundle)
    }
}
