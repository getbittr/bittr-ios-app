package com.bittr.android.core.designsystem

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.View
import android.view.Window
import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import java.util.WeakHashMap

/**
 * Keeps this screen out of screenshots, screen recordings and the Recents thumbnail while it is on
 * screen — `FLAG_SECURE` on its window. For the screens that show the recovery phrase or take it
 * typed in: whoever has those twelve words has the wallet.
 *
 * Android's answer to iOS's seed-phrase screenshot warning (DEV-18): iOS cannot stop a screenshot
 * and warns after one (`userDidTakeScreenshotNotification`); Android can stop it, so it does.
 *
 * **Scoped, never app-wide.** This is a single-window app, and the flag is the window's: set for
 * the session it would blank every Maestro `takeScreenshot` without failing one — see
 * `ScreenshotBlockingGuardTest` and `android/docs/play-store-screenshots.md`. It is added when the
 * first protected screen on a window appears and cleared when the last one goes, counted per
 * window: during a page slide the outgoing and the incoming page are both protected and both on
 * screen, and a plain add-on-enter, clear-on-leave would let the outgoing one clear it under the
 * incoming one.
 */
@Composable
fun ScreenshotProtection() {
    val view = LocalView.current
    DisposableEffect(view) {
        val window = view.window()
        if (window != null) SecureWindows.acquire(window)
        onDispose { if (window != null) SecureWindows.release(window) }
    }
}

/** How many protected screens each window has up. Main thread only, as composition is. */
private object SecureWindows {
    private val holders = WeakHashMap<Window, Int>()

    fun acquire(window: Window) {
        val count = holders[window] ?: 0
        if (count == 0) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        holders[window] = count + 1
    }

    fun release(window: Window) {
        val count = (holders[window] ?: return) - 1
        if (count <= 0) {
            holders.remove(window)
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            holders[window] = count
        }
    }
}

/** The window this view is drawn in: a dialog's own, or else the activity's. */
private fun View.window(): Window? =
    (parent as? DialogWindowProvider)?.window ?: context.activity()?.window

private tailrec fun Context.activity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.activity()
    else -> null
}
