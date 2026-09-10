package com.bittr.android.core.keystore.probe

import android.app.admin.DeviceAdminReceiver
import android.content.ComponentName
import android.content.Context

/**
 * The device-admin component BIT-18's mutation 5 ("forced reset of the secure lock screen")
 * needs. Declared in the **androidTest** manifest, so it exists only in the test APK and is
 * never part of anything shippable.
 *
 * Nothing promotes this to a device owner by itself; that is an explicit host-side
 * `adb shell dpm set-device-owner` in the driver script, behind `--with-device-owner`. It is
 * off by default and the script refuses it on a device it did not recognise as an emulator:
 * a device owner cannot be removed without a factory reset, and setting one on somebody's
 * physical Samsung to run a test would be an unreasonable thing to do to their phone.
 */
class K1DeviceAdminReceiver : DeviceAdminReceiver() {
    companion object {
        fun component(context: Context): ComponentName =
            ComponentName(context, K1DeviceAdminReceiver::class.java)
    }
}
