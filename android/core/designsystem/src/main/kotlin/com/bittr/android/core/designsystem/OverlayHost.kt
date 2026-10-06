package com.bittr.android.core.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * A layer above a host's own chrome, where a page inside it can put an overlay — iOS's views that
 * `CoreViewController` draws over everything, the menu bar included (its sync view).
 *
 * A page doesn't draw over the chrome its host draws after it, so it hands the overlay to the host
 * through [AboveChrome] instead, and the host draws [content] last.
 */
@Stable
class OverlayHost {
    var content: (@Composable () -> Unit)? by mutableStateOf(null)
        internal set
}

/** The [OverlayHost] of the screen around this one, or null where there is none. */
val LocalOverlayHost = staticCompositionLocalOf<OverlayHost?> { null }

/**
 * [content] above the surrounding host's chrome for as long as this is composed. Without a host —
 * a preview, a test, a screen shown on its own — it is drawn where it stands.
 */
@Composable
fun AboveChrome(content: @Composable () -> Unit) {
    val host = LocalOverlayHost.current
    if (host == null) {
        content()
        return
    }
    val latest by rememberUpdatedState(content)
    DisposableEffect(host) {
        val entry: @Composable () -> Unit = { latest() }
        host.content = entry
        onDispose { if (host.content === entry) host.content = null }
    }
}

/** Where a host draws what its pages put [AboveChrome]: after its own chrome. */
@Composable
fun OverlayHostLayer(host: OverlayHost) {
    host.content?.invoke()
}
