package com.bittr.android.core.permissions

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * Deep links into this app's own page in the OS settings app.
 *
 * ### Why this is code rather than a string
 *
 * Android has no second chance at a runtime permission. Once the user has denied
 * camera or location twice, `requestPermissions` returns instantly with the same
 * denial and shows nothing — the only way back is the settings app. iOS has the
 * same rule and the same answer (`UIApplication.openSettingsURLString`).
 *
 * The approved permanently-denied copy (BIT-15 → `decision-brief`, §D3) used to
 * spell out a settings path for the user to walk. It deliberately no longer does,
 * because OEM settings apps disagree about where that page lives and a wrong path
 * is worse than none. The copy now assumes a button that navigates, so the button
 * has to actually navigate — that assumption is this file.
 *
 * ### Why each entry point returns a *list*
 *
 * [Settings.ACTION_APP_NOTIFICATION_SETTINGS] has existed since API 26, which is
 * `minSdk`, so on a compliant device it always resolves. Not every device is
 * compliant: cut-down AOSP images and a handful of OEM builds ship a settings app
 * that does not declare it, and `startActivity` on an unresolvable intent throws
 * [android.content.ActivityNotFoundException] — a crash, from the button whose
 * entire job is to be the way out of a dead end.
 *
 * So each chain is ordered most-specific-first and ends with a target that is part
 * of the platform's own baseline. Pair it with [firstResolvable], which picks the
 * first entry the device can actually open:
 *
 * ```
 * val intent = context.firstResolvable(AppSettings.notificationSettings(context.packageName))
 * if (intent != null) context.startActivity(intent)
 * ```
 *
 * Callers pass an `Activity` context. These intents carry no `FLAG_ACTIVITY_NEW_TASK`
 * on purpose: started from the activity they land in the app's own task, so the
 * system back gesture returns to the screen the user pressed the button on, which
 * is what "go and turn it on, then come back" requires.
 */
object AppSettings {

    /**
     * The app's own page in settings — permissions, storage, notifications.
     *
     * This is the target for the permanently-denied camera (DEV-37) and location
     * (DEV-54) states. There is no per-permission deep link on Android; the app
     * detail page is as close as the platform gets.
     */
    fun applicationDetails(packageName: String): List<Intent> = listOf(
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        ),
    )

    /**
     * The app's notification settings, falling back to [applicationDetails].
     *
     * The fallback is a real downgrade — the app detail page has a *Notifications*
     * row the user has to find — but it is one tap further, not a crash.
     */
    fun notificationSettings(packageName: String): List<Intent> = listOf(
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
    ) + applicationDetails(packageName)
}

/**
 * The first of [candidates] this device has an activity for, or `null` if it has
 * none of them.
 *
 * `null` means the button cannot do what the copy says it does. Handle it by
 * leaving the button out rather than showing one that does nothing.
 */
fun Context.firstResolvable(candidates: List<Intent>): Intent? =
    candidates.firstOrNull { it.resolveActivity(packageManager) != null }
