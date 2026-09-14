package com.bittr.android.push

import android.content.Context
import com.bittr.android.core.network.BoltzWebhookCache
import com.bittr.android.core.network.DeviceTokenCache
import com.bittr.android.core.network.DeviceTokenLifecycle
import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.push.fcm.PushDelivery
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * The app's binding of [PushDelivery] — where a decoded push and a rotated token go.
 *
 * Both halves are one line, and that is the shape the module split was chosen for: the token
 * half is `DeviceTokenLifecycle`, which is 20 JVM tests in `:core:network`, and the payload half
 * is a decode that already happened in `:core:push`.
 *
 * ## What happens to a push
 *
 * It goes to [PushCoordinator], the one singleton that dedups it, holds it while the wallet is
 * locked or syncing, and shows what iOS shows. Handed over directly rather than collected from
 * [envelopes]: that flow replays its newest push to every new collector, which would handle a
 * push twice. The coordinator outlives every screen, so a data message that starts the process
 * is not dropped before the first composition.
 *
 * [envelopes] stays for anything that only wants to observe pushes. `extraBufferCapacity` keeps
 * [emit] from suspending, which matters because [onPush] is called inside the service's
 * `runBlocking`.
 */
@Singleton
class BittrPushDelivery @Inject constructor(
    private val lifecycle: DeviceTokenLifecycle,
    private val coordinator: PushCoordinator,
) : PushDelivery {

    private val _envelopes = MutableSharedFlow<PushEnvelope>(replay = 1, extraBufferCapacity = 16)

    /** Decoded pushes, newest replayed to a late collector. */
    val envelopes: SharedFlow<PushEnvelope> = _envelopes.asSharedFlow()

    override suspend fun onPush(envelope: PushEnvelope) {
        coordinator.receive(envelope)
        _envelopes.emit(envelope)
    }

    override suspend fun onNewToken(token: String) {
        lifecycle.onNewToken(token)
    }
}

/**
 * [DeviceTokenCache] over `SharedPreferences` — what the backend last acknowledged.
 *
 * `SharedPreferences` for the same reason `AppPreferences` gives: one string, read once at
 * launch, written rarely. The durability question is `apply` vs `commit`, and `apply` is right
 * here — a write lost to a process kill re-posts the token on the next launch, which is exactly
 * what the app-start reconciliation already does for every other reason.
 *
 * **Not backed up.** `allowBackup="false"` is set app-wide, so this never leaves the device. It
 * should not: a restored `acknowledgedToken` describes an FCM registration belonging to the old
 * install, and FCM mints a new token on restore. A cache that survived the restore would agree
 * with nothing and suppress the very reconciliation the restore requires.
 */
class PrefsDeviceTokenCache(context: Context) : DeviceTokenCache {

    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    override fun acknowledgedToken(): String? = prefs.getString(KEY_TOKEN, null)

    override fun recordAcknowledged(token: String) {
        prefs.edit().putString(KEY_TOKEN, token).apply()
    }

    override fun clearAcknowledged() {
        prefs.edit().remove(KEY_TOKEN).apply()
    }

    private companion object {
        const val FILE = "bittr_push"
        const val KEY_TOKEN = "acknowledged_device_token"
    }
}

/**
 * [BoltzWebhookCache] over `SharedPreferences` — `CacheManager.storeBoltzWebhook` on iOS.
 *
 * Stores the URL **and the token it was minted for**, because that pairing is the whole cache
 * key: `SwapManager.swift:43-48` reuses a cached URL only while it still matches the current
 * device token. A URL without its token is a URL that cannot be checked for staleness.
 */
class PrefsBoltzWebhookCache(context: Context) : BoltzWebhookCache {

    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** The cached URL, or null when it was minted for a token this device no longer holds. */
    fun urlFor(deviceToken: String): String? =
        prefs.getString(KEY_URL, null)?.takeIf { prefs.getString(KEY_TOKEN, null) == deviceToken }

    override fun store(url: String, deviceToken: String) {
        prefs.edit().putString(KEY_URL, url).putString(KEY_TOKEN, deviceToken).apply()
    }

    override fun clear() {
        prefs.edit().remove(KEY_URL).remove(KEY_TOKEN).apply()
    }

    private companion object {
        const val FILE = "bittr_push"
        const val KEY_URL = "boltz_webhook_url"
        const val KEY_TOKEN = "boltz_webhook_device_token"
    }
}
