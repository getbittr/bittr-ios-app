package com.bittr.android.core.designsystem

import android.os.SystemClock
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp

/**
 * Pulling a modal screen down past the top of its scroll closes it — iOS's swipe-down on a sheet.
 *
 * iOS presents Move, Swap and their siblings as page sheets, and the shared flows leave them
 * with `swipe: direction: DOWN` (`swap.yaml`, `send_swap_suggestion_*.yaml`). A header Down button
 * is the Android affordance; this makes the gesture the flows use do the same thing.
 *
 * Put it on the screen's root. Two paths, because a screen may or may not scroll:
 * - **Content that scrolls:** the drag the scroll cannot use — pulling down while already at the
 *   top — is offered here through nested scrolling.
 * - **Content that doesn't** (Buy with its cards, a short transaction): a downward drag anywhere
 *   on the screen that no child consumed.
 *
 * Past [threshold] it calls [onDismiss] once per gesture, and never twice within half a second,
 * so one swipe can't pop two screens.
 */
fun Modifier.dismissOnPullDown(onDismiss: () -> Unit, threshold: androidx.compose.ui.unit.Dp = 96.dp): Modifier = composed {
    val thresholdPx = with(LocalDensity.current) { threshold.toPx() }
    val onDismissLatest by rememberUpdatedState(onDismiss)
    val lastDismissAt = remember { longArrayOf(Long.MIN_VALUE / 2) }
    val dismiss = {
        val now = SystemClock.uptimeMillis()
        if (now - lastDismissAt[0] > DISMISS_DEBOUNCE_MS) {
            lastDismissAt[0] = now
            onDismissLatest()
        }
    }
    val connection = remember(thresholdPx) {
        object : NestedScrollConnection {
            private var pulled = 0f
            private var fired = false

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput) return Offset.Zero
                if (available.y > 0f) {
                    pulled += available.y
                    if (!fired && pulled > thresholdPx) {
                        fired = true
                        dismiss()
                    }
                    return Offset(0f, available.y)
                }
                if (consumed.y != 0f || available.y < 0f) pulled = 0f
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                pulled = 0f
                fired = false
                return Velocity.Zero
            }
        }
    }
    nestedScroll(connection).pointerInput(thresholdPx) {
        var pulled = 0f
        var fired = false
        detectVerticalDragGestures(
            onDragStart = {
                pulled = 0f
                fired = false
            },
            onVerticalDrag = { change, dragAmount ->
                pulled += dragAmount
                if (pulled > 0f) change.consume()
                if (!fired && pulled > thresholdPx) {
                    fired = true
                    dismiss()
                }
            },
        )
    }
}

private const val DISMISS_DEBOUNCE_MS = 500L
