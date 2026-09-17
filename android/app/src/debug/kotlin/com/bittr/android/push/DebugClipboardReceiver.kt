package com.bittr.android.push

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.util.Base64

/**
 * Debug builds only: the device clipboard for the Maestro flows — Android's `xcrun simctl pbcopy`.
 *
 * `adb shell` may not touch the clipboard on modern Android, so `clipboard_server.js`'s Android mode
 * sends it here. The text travels base64-encoded, so an invoice or address needs no shell quoting:
 *
 * ```
 * adb shell am broadcast -a com.bittr.android.DEBUG_CLIPBOARD_SET -p com.bittr.android.regtest \
 *   --es text_b64 <base64>
 * adb shell am broadcast -a com.bittr.android.DEBUG_CLIPBOARD_GET -p com.bittr.android.regtest
 * ```
 *
 * GET answers through the ordered broadcast's result data, base64-encoded (`data="…"` in `am`'s output).
 * Reading only works while the app is in front, which is when a flow asks.
 */
class DebugClipboardReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
        when (intent.action) {
            ACTION_SET -> {
                val encoded = intent.getStringExtra(EXTRA_TEXT_B64) ?: return
                val text = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
                clipboard.setPrimaryClip(ClipData.newPlainText("maestro", text))
                resultCode = RESULT_OK
                resultData = "ok"
            }
            ACTION_GET -> {
                val text = runCatching { clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString() }
                    .getOrNull().orEmpty()
                resultCode = RESULT_OK
                resultData = Base64.encodeToString(text.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            }
        }
    }

    companion object {
        const val ACTION_SET = "com.bittr.android.DEBUG_CLIPBOARD_SET"
        const val ACTION_GET = "com.bittr.android.DEBUG_CLIPBOARD_GET"
        const val EXTRA_TEXT_B64 = "text_b64"
        private const val RESULT_OK = -1
    }
}
