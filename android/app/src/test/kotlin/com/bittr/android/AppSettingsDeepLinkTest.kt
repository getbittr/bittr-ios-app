package com.bittr.android

import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.permissions.AppSettings
import com.bittr.android.core.permissions.firstResolvable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Covers the capability the permanently-denied copy assumes: the app can send the
 * user to its own settings page.
 *
 * The approved permanently-denied strings (BIT-15 → `decision-brief` §D3) used to
 * name an OS settings path for the user to walk. They deliberately no longer do —
 * OEM settings apps disagree about where that page lives, and a wrong path is
 * worse than none. What replaced it is a button that navigates, which makes the
 * navigation part of what compliance approved rather than an implementation
 * detail (BIT-57).
 *
 * Android gives no second chance at a runtime permission: after the second denial
 * `requestPermissions` returns instantly with the same answer and shows nothing.
 * If this button does not work, the permanently-denied state is not a dead end with
 * a way out — it is just a dead end, and the copy says otherwise.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AppSettingsDeepLinkTest {

    private companion object {
        const val PKG = "com.bittr.android.regtest"
        val SETTINGS = ComponentName("com.android.settings", "com.android.settings.Settings")

        const val PERMISSIONS_MANIFEST = "core/permissions/src/main/AndroidManifest.xml"
    }

    private val context = RuntimeEnvironment.getApplication()

    /** Registers a settings activity that answers [action], as a real device would. */
    private fun installSettingsHandler(action: String, dataScheme: String? = null) {
        val shadow = shadowOf(context.packageManager)
        shadow.addActivityIfNotPresent(SETTINGS)
        shadow.addIntentFilterForActivity(
            SETTINGS,
            IntentFilter(action).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                dataScheme?.let(::addDataScheme)
            },
        )
    }

    @Test
    fun `the app detail link points at this app's own page`() {
        val intent = AppSettings.applicationDetails(PKG).single()

        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.action)
        // `package:<id>` is the only thing that distinguishes "bittr's settings page"
        // from "the app list". Without the data URI the intent opens the list, and
        // the user is asked to find bittr in it — which is the hunting the copy was
        // rewritten to stop.
        assertEquals("package:$PKG", intent.data.toString())
    }

    @Test
    fun `the notification link asks for this app's notification screen`() {
        val intent = AppSettings.notificationSettings(PKG).first()

        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, intent.action)
        assertEquals(PKG, intent.getStringExtra(Settings.EXTRA_APP_PACKAGE))
    }

    @Test
    fun `the notification link falls back to the app detail page`() {
        // A device whose settings app does not answer ACTION_APP_NOTIFICATION_SETTINGS
        // — cut-down AOSP images and a few OEM builds. Without the fallback,
        // startActivity throws ActivityNotFoundException: the button whose job is to
        // be the way out of a dead end crashes the app instead.
        installSettingsHandler(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, dataScheme = "package")

        val chosen = context.firstResolvable(AppSettings.notificationSettings(PKG))

        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, chosen?.action)
        assertEquals("package:$PKG", chosen?.data.toString())
    }

    @Test
    fun `the notification link prefers the notification screen when it exists`() {
        installSettingsHandler(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        installSettingsHandler(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, dataScheme = "package")

        val chosen = context.firstResolvable(AppSettings.notificationSettings(PKG))

        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, chosen?.action)
    }

    @Test
    fun `nothing resolvable is reported rather than crashed`() {
        // No settings handler registered at all. firstResolvable answers null so the
        // caller can leave the button out; the alternative is a button that throws.
        assertNull(context.firstResolvable(AppSettings.notificationSettings(PKG)))
        assertNull(context.firstResolvable(AppSettings.applicationDetails(PKG)))
    }

    /**
     * The half no JVM test can exercise: package visibility.
     *
     * From `targetSdk` 30 the platform hides other packages from this one, and
     * `resolveActivity` returns null for a hidden target. Robolectric does not
     * implement that filtering, so every test above passes with the `<queries>`
     * block present *or* absent — and on a real device its absence would make
     * `firstResolvable` answer "this device cannot open its own settings" **every
     * time**, indistinguishable from the rare OEM case the fallback exists for.
     * The symptom would be the settings button quietly missing on every device.
     *
     * So it is guarded by source, the same way `testTagsAsResourceId` is.
     */
    @Test
    fun `the permissions module declares settings visibility`() {
        val manifest = SourceTree.root.resolve(PERMISSIONS_MANIFEST)
        assertTrue("$PERMISSIONS_MANIFEST does not exist.", manifest.isFile)
        val text = manifest.readText()

        listOf(
            "android.settings.APP_NOTIFICATION_SETTINGS",
            "android.settings.APPLICATION_DETAILS_SETTINGS",
        ).forEach { action ->
            assertTrue(
                "$PERMISSIONS_MANIFEST no longer declares a <queries> entry for $action. " +
                    "Package visibility filtering (targetSdk 30+) then hides the settings " +
                    "app, resolveActivity returns null, and firstResolvable reports that " +
                    "the device cannot open its own settings — on every device, silently.",
                action in text,
            )
        }
        assertTrue(
            "$PERMISSIONS_MANIFEST has the settings actions but no <queries> element to " +
                "put them in. Only entries inside <queries> grant visibility.",
            "<queries>" in text,
        )
    }
}
