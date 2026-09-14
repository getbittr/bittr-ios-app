package com.bittr.android

import android.app.Application
import com.bittr.android.core.push.fcm.DataMessageWake
import com.bittr.android.core.push.fcm.PushDelivery
import com.bittr.android.core.push.fcm.PushHost
import com.bittr.android.messaging.WalletWake
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

/**
 * The application, and — since BIT-41 item 3 — the [PushHost] that
 * `BittrMessagingService` looks its collaborators up through.
 *
 * A `Service` is constructed by the framework and cannot take constructor arguments, so it has
 * to find them somewhere. Hilt's `@AndroidEntryPoint` would do it, at the cost of putting the
 * Hilt plugin and KSP on `:core:push-fcm` — the one module allowed to reach Firebase, whose
 * dependency list is the thing `FirebaseMessagingGuardTest` keeps short. Asking the
 * `Application` costs one interface and reaches the same graph, because [pushDelivery] is
 * injected here.
 *
 * [dataMessageWake] is the same lookup for BIT-133's background wake, which since BIT-146 rides
 * on that one service instead of declaring a second.
 */
@HiltAndroidApp
class BittrApplication : Application(), PushHost {

    @Inject
    lateinit var delivery: PushDelivery

    override val pushDelivery: PushDelivery get() = delivery

    override val dataMessageWake: DataMessageWake by lazy { WalletWake(this) }
}
