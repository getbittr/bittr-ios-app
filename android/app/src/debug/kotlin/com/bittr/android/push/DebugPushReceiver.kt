package com.bittr.android.push

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.bittr.android.core.push.PushEnvelopeDecoder
import com.bittr.android.core.push.fcm.PushHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Debug builds only: a push without Firebase, for the Maestro flows — Android's
 * `xcrun simctl push`.
 *
 * Extras are FCM's data map: one string extra per discriminator whose value is the JSON
 * object as a string, e.g.
 *
 * ```
 * adb shell am broadcast -a com.bittr.android.DEBUG_PUSH -p com.bittr.android.regtest \
 *   --es htlc_notification '{}'
 * ```
 *
 * No discriminator at all is an unknown push, as an APNs payload with only `aps` is.
 * It goes through the same decoder and the same [PushHost.pushDelivery] as a real push.
 */
class DebugPushReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val host = context.applicationContext as? PushHost ?: return
        val data = PushEnvelopeDecoder.DISCRIMINATORS
            .mapNotNull { key -> intent.getStringExtra(key)?.let { key to it } }
            .toMap()
        val result = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                host.pushDelivery.onPush(PushEnvelopeDecoder.decode(data))
            } finally {
                result.finish()
            }
        }
    }

    companion object {
        const val ACTION = "com.bittr.android.DEBUG_PUSH"
    }
}
