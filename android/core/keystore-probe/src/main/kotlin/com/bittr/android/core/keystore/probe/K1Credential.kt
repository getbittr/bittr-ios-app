package com.bittr.android.core.keystore.probe

import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Build

/**
 * What the device says about its own lock-screen credential.
 *
 * ## Why this exists rather than `adb shell locksettings verify`
 *
 * K1's first six runs took the host's word for it. Run #6 proved the host cannot be taken at its
 * word: on the API 34 `default` image every form of `locksettings verify` exits 0, including a
 * deliberately wrong credential and a bare `verify` with no argument. A witness that always says
 * yes is precisely how a false green gets made — "the key survived a PIN change", reported from a
 * run that never established a PIN change happened.
 *
 * So the witness moved to the other side of adb. Both readings here come from the same framework
 * services the OS itself uses to decide whether the device is locked, in the process that owns the
 * key, and neither of them can be satisfied by a shell command that exits 0 and does nothing.
 *
 * ## What each reading can and cannot see
 *
 * [isDeviceSecure] answers "is there a credential at all". It is available on every API in the
 * matrix and it is decisive for exactly the mutations that cross that line: M1 sets one where none
 * existed, M5 and M6 destroy one. It is blind to M2/M3/M4, which are secure on both sides.
 *
 * [complexity] is what carries those three. `DevicePolicyManager.getPasswordComplexity()` buckets
 * the current credential into NONE/LOW/MEDIUM/HIGH, and the driver picks credentials that sit in
 * different buckets, so a mutation that landed shows up as a bucket move and one that exited 0 and
 * did nothing does not. It arrived in API 29, so on API 26-28 it reads [UNREADABLE] and those three
 * cases have no witness at all — recorded as `not reachable`, which this issue's own position is
 * that a finding is not a gap.
 *
 * Note what [complexity] is *not*: it is not the credential's type. Nothing public reports whether
 * the lock screen is a PIN, a pattern or a password. A bucket move proves the credential changed;
 * the driver's `set-pattern` versus `set-password` is what names which change it was, and the
 * driver records the bucket transition in the table so a reader can see the actual evidence rather
 * than the label.
 */
object K1Credential {

    /** No answer from this device — not "no credential", which is [COMPLEXITY_NONE]. */
    const val UNREADABLE = "unreadable"

    const val COMPLEXITY_NONE = "NONE"

    fun isDeviceSecure(context: Context): Boolean =
        context.getSystemService(KeyguardManager::class.java).isDeviceSecure

    /**
     * NONE / LOW / MEDIUM / HIGH, or [UNREADABLE] when this device will not answer.
     *
     * Every failure path returns [UNREADABLE] rather than a bucket. A wrong bucket would be read
     * as a credential that did or did not change; "I could not tell" cannot be mistaken for either,
     * and the caller is built to treat it as "this case has no witness here".
     *
     * `getPasswordComplexity()` needs `REQUEST_PASSWORD_COMPLEXITY`, declared in the androidTest
     * manifest. It is a `normal` permission, so it is granted at install without a prompt — but an
     * OEM build that hardened it would throw [SecurityException] here rather than at install time,
     * which is why that is caught rather than assumed away.
     */
    fun complexity(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return UNREADABLE
        val dpm = context.getSystemService(DevicePolicyManager::class.java) ?: return UNREADABLE
        return try {
            when (dpm.passwordComplexity) {
                DevicePolicyManager.PASSWORD_COMPLEXITY_NONE -> COMPLEXITY_NONE
                DevicePolicyManager.PASSWORD_COMPLEXITY_LOW -> "LOW"
                DevicePolicyManager.PASSWORD_COMPLEXITY_MEDIUM -> "MEDIUM"
                DevicePolicyManager.PASSWORD_COMPLEXITY_HIGH -> "HIGH"
                else -> UNREADABLE
            }
        } catch (_: SecurityException) {
            UNREADABLE
        } catch (_: NoSuchMethodError) {
            // The same shape of mistake K1 already made once with
            // KeyInfo.isUnlockedDeviceRequired: compileSdk hides a method the device does not
            // have. Asking and catching is cheaper than being right about every OEM's API level.
            UNREADABLE
        }
    }

    /** True when [complexity] gave a real bucket on both sides of a mutation. */
    fun isReadable(value: String): Boolean = value != UNREADABLE && value.isNotEmpty()
}
