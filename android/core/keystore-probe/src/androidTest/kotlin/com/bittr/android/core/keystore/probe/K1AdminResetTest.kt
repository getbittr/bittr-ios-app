package com.bittr.android.core.keystore.probe

import android.app.admin.DevicePolicyManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.security.SecureRandom

/**
 * The mutation for BIT-18's case 5 — "forced reset of the secure lock screen (device admin wipe
 * of credentials, where reachable)". Runs *between* [K1SealTest] and [K1OpenTest], as its own
 * `am instrument` invocation, and only for [K1Case.M6_ADMIN_RESET].
 *
 * ### Why this is not just `locksettings clear`
 *
 * `locksettings clear --old 1234` is a removal *with* the credential and is already case M5.
 * Case 6 is the one where the credential is destroyed by policy, by a party that does not know
 * it. On API 26+ that is `resetPasswordWithToken`; `DevicePolicyManager.resetPassword` was
 * deprecated in O and throws for a device owner from P onward, so it is not a route.
 *
 * ### Why "where reachable" is load-bearing
 *
 * The token has to be *activated* before it can be used, and activation requires the user to
 * confirm the existing credential once (or a reboot). The driver script drives an unlock with
 * the known PIN to provoke that, but it is not guaranteed on every image, and
 * [DevicePolicyManager.setResetPasswordToken] itself needs secure hardware to escrow the token
 * and throws where there is none.
 *
 * Where any of that fails, this test **skips** via [assumeTrue] and says why. It does not pass.
 * A skipped case is recorded as `not reachable` in the result table with the reason attached,
 * which is the finding the issue asks for — "where reachable" is a question K1 answers, not a
 * clause that lets the row be quietly dropped.
 */
@RunWith(AndroidJUnit4::class)
class K1AdminResetTest {

    @Test
    fun forceResetCredential() {
        val case = K1Harness.case()
        assumeTrue(
            "K1AdminResetTest only applies to ${K1Case.M6_ADMIN_RESET.id}, not ${case.id}",
            case == K1Case.M6_ADMIN_RESET,
        )

        val context = K1Harness.context
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        val admin = K1DeviceAdminReceiver.component(context)

        assumeTrue(
            "not a device owner. The driver script did not run (or could not run) " +
                "`adb shell dpm set-device-owner ${admin.flattenToShortString()}` — case " +
                "${case.id} is not reachable on this device.",
            dpm.isDeviceOwnerApp(context.packageName),
        )

        val token = ByteArray(32).also { SecureRandom().nextBytes(it) }

        val tokenSet = try {
            dpm.setResetPasswordToken(admin, token)
        } catch (e: SecurityException) {
            K1Harness.report("mutate", case, mapOf("reachable" to "false", "reason" to "SecurityException:${e.message}"))
            assumeTrue("setResetPasswordToken threw SecurityException: ${e.message}", false)
            return
        } catch (e: UnsupportedOperationException) {
            // Thrown where there is no secure hardware to escrow the token.
            K1Harness.report("mutate", case, mapOf("reachable" to "false", "reason" to "no_secure_hardware:${e.message}"))
            assumeTrue("this device cannot escrow a reset-password token: ${e.message}", false)
            return
        }
        assumeTrue("setResetPasswordToken returned false", tokenSet)

        assumeTrue(
            "the reset token is set but not active. It activates when the existing credential " +
                "is confirmed once; the driver script's unlock did not achieve that on this " +
                "image, so case ${case.id} is not reachable here.",
            dpm.isResetPasswordTokenActive(admin),
        )

        // Empty password == remove the lock screen, by policy, without knowing the old one.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            DevicePolicyManager.RESET_PASSWORD_REQUIRE_ENTRY
        } else {
            0
        }
        val cleared = dpm.resetPasswordWithToken(admin, null, token, flags)
        assumeTrue("resetPasswordWithToken returned false", cleared)

        // The mutation must have landed before the open phase is allowed to draw a conclusion.
        assertFalse(
            "resetPasswordWithToken reported success but the device is still secure",
            K1Harness.isDeviceSecure(),
        )

        K1Harness.report("mutate", case, mapOf("reachable" to "true", "credentialCleared" to "true"))
    }
}
