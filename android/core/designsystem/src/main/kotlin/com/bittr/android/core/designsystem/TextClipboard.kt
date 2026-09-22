package com.bittr.android.core.designsystem

import android.content.ClipData
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.toClipEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Plain-text copy and paste over Compose's [Clipboard], which replaced the deprecated
 * `LocalClipboardManager`. The new API suspends, so the screens that copy an address or
 * paste an invoice go through this instead of each launching their own coroutine.
 */
class TextClipboard internal constructor(
    private val clipboard: Clipboard,
    private val scope: CoroutineScope,
) {
    /** Puts [text] on the clipboard. Returns at once; the write lands a moment later. */
    fun copy(text: String) {
        scope.launch { clipboard.setClipEntry(ClipData.newPlainText(CLIP_LABEL, text).toClipEntry()) }
    }

    /** Reads the clipboard's first item as text — null when it is empty or not text. */
    fun paste(onText: (String?) -> Unit) {
        scope.launch {
            val clip = clipboard.getClipEntry()?.clipData
            onText(clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString())
        }
    }

    private companion object {
        const val CLIP_LABEL = "bittr"
    }
}

/**
 * Whether the system tells the user that something was copied.
 *
 * Android 13 shows its own clipboard confirmation — a chip with a preview, bottom-left —
 * for every copy an app makes, and the platform's guidance is not to add a second one.
 * Below 13 nothing appears, so the app's own "Copied" alert is still the only feedback
 * there. iOS has no such chip and keeps its alert on every version.
 */
val SYSTEM_CONFIRMS_COPY: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

@Composable
fun rememberTextClipboard(): TextClipboard {
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    return remember(clipboard, scope) { TextClipboard(clipboard, scope) }
}
