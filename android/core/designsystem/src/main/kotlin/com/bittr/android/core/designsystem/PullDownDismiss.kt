package com.bittr.android.core.designsystem

import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
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
 * Put it on an ancestor of the screen's vertical scroll: the drag the scroll cannot use — pulling
 * down while already at the top — is offered here, and past [threshold] it calls [onDismiss] once
 * per gesture.
 */
fun Modifier.dismissOnPullDown(onDismiss: () -> Unit, threshold: androidx.compose.ui.unit.Dp = 96.dp): Modifier = composed {
    val thresholdPx = with(LocalDensity.current) { threshold.toPx() }
    val dismiss by rememberUpdatedState(onDismiss)
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
    nestedScroll(connection)
}
