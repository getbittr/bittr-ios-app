package com.bittr.android

import android.content.Intent
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The background wake, read back out of the **merged** manifest (BIT-133).
 *
 * `BackgroundWakeTest` proves what the wake decides. This proves the framework
 * would ever hand it anything, which is a different claim and the one that fails
 * silently: `firebase-messaging`'s own AAR declares a fallback
 * `FirebaseMessagingService` for `com.google.firebase.MESSAGING_EVENT` at
 * `android:priority="-500"`, so an app that loses its own `<service>` entry does
 * not crash and does not log — FCM resolves Google's base class, whose
 * `onMessageReceived` is empty, and the wake goes quiet.
 *
 * It reads the merged manifest rather than `app/src/main/AndroidManifest.xml`
 * for the reason [LocationPrecisionGuardTest] gives: between the source and the
 * install there is a manifest merge, and a `tools:node` directive or a
 * dependency's own entry can change the answer without this repo's source
 * moving.
 *
 * ## The device half, and why this is not it
 *
 * `FcmWakeTest` asserts the same wiring on the installed package. That is not
 * redundancy — Robolectric's package manager is a model of the platform's, and
 * the thing it models least well is intent-filter *priority*, which is exactly
 * what decides whether our service or the library's fallback receives the
 * message. So the ordering claim is made there, on a real `PackageManager`, and
 * what is made here is the cheap half: the entry exists, it is not exported, and
 * the dependency has not quietly widened the app's permission set.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class FcmWakeWiringTest {

    private companion object {

        const val MESSAGING_EVENT = "com.google.firebase.MESSAGING_EVENT"
        const val SERVICE = "com.bittr.android.core.push.fcm.BittrMessagingService"
        const val LIBRARY_FALLBACK = "com.google.firebase.messaging.FirebaseMessagingService"

        /**
         * What `firebase-messaging` adds to the merged manifest **that was not
         * already in it**, measured rather than read off the documentation.
         *
         * The AAR (`firebase-messaging-25.1.3.aar`) declares four:
         * `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`, `WAKE_LOCK` and
         * `com.google.android.c2dm.permission.RECEIVE`. Two of those were
         * already in the merge and are therefore not a change to the shipped
         * APK — `POST_NOTIFICATIONS` is the app's own, for the Settings → Device
         * details row, and `ACCESS_NETWORK_STATE` arrives from MapLibre's AAR,
         * which declares it alongside `ACCESS_WIFI_STATE`. The diff that reaches
         * a Play listing is the two below.
         *
         * Pinned because it is a listing change arriving through a dependency,
         * which is the shape the BIT-57 block at the top of the app manifest
         * exists to make visible. A third one appearing in a Firebase version
         * bump should be a red test and a conversation, not a line in the store
         * listing nobody reviewed.
         */
        val FCM_PERMISSIONS = setOf(
            "android.permission.WAKE_LOCK",
            "com.google.android.c2dm.permission.RECEIVE",
        )

        /**
         * Everything the app requested before BIT-133, plus [FCM_PERMISSIONS].
         *
         * Listed in full rather than as a diff so that a permission arriving
         * from *any* dependency — not only Firebase's — shows up here. The three
         * names BIT-57 holds out of the merge are correctly absent, and at least
         * one of them is genuinely declared by MapLibre's own AAR, so that
         * absence is the `tools:node="remove"` directive working rather than
         * nothing having tried. [LocationPrecisionGuardTest] owns that claim and
         * spells the permission out; this file must not, because that test is a
         * string scan over the app's Kotlin sources and naming it here trips it.
         *
         * `<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` is added by
         * the AGP/androidx merge, not by this repo; it is signature-level and
         * scoped to the package, and it is derived from [android.content.Context.getPackageName]
         * rather than written out because `./gradlew test` runs both build
         * types and the debug one carries the `.regtest` suffix.
         */
        val EXPECTED_PERMISSIONS = setOf(
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.INTERNET",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.FOREGROUND_SERVICE",
            "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
            // The scanner (BIT-72).
            "android.permission.CAMERA",
            // MapLibre's, both of them (BIT-53).
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.ACCESS_WIFI_STATE",
        ) + FCM_PERMISSIONS
    }

    private val context get() = RuntimeEnvironment.getApplication()

    @Test
    fun `the merged manifest declares the app's own messaging service`() {
        val services = context.packageManager
            .queryIntentServices(Intent(MESSAGING_EVENT).setPackage(context.packageName), 0)
            .map { it.serviceInfo.name }

        assertTrue(
            "Nothing in the merged manifest handles $MESSAGING_EVENT under this package name. " +
                "Without it there is no background wake at all — BIT-133's whole subject. " +
                "Restore the <service> block in core/push-fcm/src/main/AndroidManifest.xml.\n" +
                "Resolved: $services",
            SERVICE in services,
        )
    }

    @Test
    fun `the library's fallback service is present too, which is why the entry can be lost quietly`() {
        // Not a requirement — a statement of the trap, asserted so the reasoning
        // in the manifest comment and in FcmWakeTest cannot go stale. If Firebase
        // ever stops shipping this fallback, a missing app entry would start
        // failing loudly, and both of those comments would be describing a
        // hazard that no longer exists.
        val services = context.packageManager
            .queryIntentServices(Intent(MESSAGING_EVENT).setPackage(context.packageName), 0)
            .map { it.serviceInfo.name }

        assertTrue(
            "firebase-messaging no longer declares its own $LIBRARY_FALLBACK for " +
                "$MESSAGING_EVENT. That changes the failure mode of a missing app entry from " +
                "silent to loud, which is good news — update the comments in " +
                "core/push-fcm/src/main/AndroidManifest.xml and FcmWakeTest that describe it.\n" +
                "Resolved: $services",
            LIBRARY_FALLBACK in services,
        )
    }

    @Test
    fun `the messaging service is not exported`() {
        val service = context.packageManager
            .getServiceInfo(android.content.ComponentName(context.packageName, SERVICE), 0)

        assertNotNull(service)
        assertFalse(
            "$SERVICE is exported. FCM delivers in-process through Play services, so nothing " +
                "outside the app needs to reach it, and an exported wake path is a way for any " +
                "app on the device to make this one start a Lightning node and put a " +
                "foreground notification up.",
            service.exported,
        )
    }

    @Test
    fun `the merged manifest requests exactly the permissions this app has decided on`() {
        val requested = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toSet()
            .orEmpty()

        val expected = EXPECTED_PERMISSIONS +
            "${context.packageName}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"

        assertEquals(
            "The merged permission set has moved. Every name here reaches the Play listing " +
                "and, for the runtime ones, a system dialog — see the block at the top of " +
                "app/src/main/AndroidManifest.xml for why this repo treats that as a decision " +
                "rather than a merge artefact. Firebase's two are " +
                "$FCM_PERMISSIONS; anything else new arrived from somewhere that has not been " +
                "reviewed. Find the source with `./gradlew :app:processDebugMainManifest` and " +
                "read app/build/outputs/logs/manifest-merger-debug-report.txt.\n" +
                "Added: ${requested - expected}\n" +
                "Missing: ${expected - requested}",
            expected,
            requested,
        )
    }
}
