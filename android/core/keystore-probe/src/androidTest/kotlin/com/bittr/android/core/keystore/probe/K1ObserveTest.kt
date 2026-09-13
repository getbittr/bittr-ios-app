package com.bittr.android.core.keystore.probe

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Ask the device what its lock screen currently is, and say so on the K1 channel.
 *
 * This is not a test of anything and it never fails. It is the driver script's eyes: every question
 * `android/scripts/k1-lockscreen-matrix.sh` used to ask `adb shell locksettings verify` is now
 * asked here instead, because run #6 established that `verify` exits 0 on the API 34 image whatever
 * is stored — including for a credential the device does not have. See [K1Credential].
 *
 * It costs one `am instrument` round-trip per call, which is why the driver calls it at decision
 * points rather than in loops. It buys two things back. It cannot be satisfied by a shell command
 * that exits 0 and does nothing, and — unlike the probe it replaces — it spends **no failed
 * credential attempt**, so the driver can no longer walk a physical handset into the five-attempt
 * 30-second lockout just by asking it questions. On the Samsung and the Xiaomi, which are the rows
 * K1 exists for, that was a real hazard.
 *
 * No `-e k1_case` argument: an observation is about the device, not about a mutation.
 */
@RunWith(AndroidJUnit4::class)
class K1ObserveTest {

    @Test
    fun observe() {
        val context = K1Harness.context
        K1Harness.report(
            phase = "observe",
            caseId = "-",
            facts = mapOf(
                "deviceSecure" to K1Credential.isDeviceSecure(context).toString(),
                "complexity" to K1Credential.complexity(context),
            ),
        )
    }
}
