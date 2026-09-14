package com.bittr.android.messaging

import android.content.Context
import android.util.Log
import com.bittr.android.core.wallet.ldk.host.BackgroundWake
import com.bittr.android.core.wallet.ldk.host.WakeOutcome
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent

/**
 * The client end of the background wake — **BIT-133**, and the thing whose
 * absence made K2's FCM leg untestable rather than unproven.
 *
 * Deliberately almost empty. Everything that decides anything is
 * [BackgroundWake] in `:core:wallet-ldk`, which runs on the JVM under
 * `BackgroundWakeTest`; what is left here is the platform seam —
 * `FirebaseMessagingService`, which cannot be constructed off a device. Same
 * split as `WalletForegroundService` and `ForegroundPresence`, for the same
 * reason: a decision behind a `Service` subclass is a decision that can only be
 * checked by booting an emulator.
 *
 * ## Why it is in `:app` and not in `:core:wallet-ldk`
 *
 * The wallet module owns the node and must not own the app's push identity. This
 * service resolves its dependency out of the *application's* Hilt graph, which
 * is the one place the wallet implementation is chosen (`di/WalletModule`), and
 * it is the app that is registered with Firebase — `google-services.json` is
 * keyed by `applicationId`, which a library module does not have.
 *
 * ## `EntryPointAccessors`, not `@AndroidEntryPoint`
 *
 * `@AndroidEntryPoint` would work and is the usual answer. It is not used here
 * because it injects in `onCreate`, which means the injected field is the reason
 * this class cannot be exercised without the framework instantiating the
 * service — and instantiating a background service on API 26+ is exactly what
 * the platform refuses to let a test do. Resolving from the application context
 * at the moment of use keeps [deliver] callable with a `Context`, which is what
 * `FcmWakeTest` does on the installed app.
 *
 * The entry point is declared **in `main`, not in `androidTest`**. A
 * `@EntryPoint` declared in an instrumented test source set compiles, and is not
 * aggregated into the app's component, and throws at run time on the device —
 * green locally, red only after an emulator has booted.
 *
 * ## What the sender has to do, which is not visible from here
 *
 * Two things, and both are properties of the message rather than of this file:
 *
 * - **`priority: "high"`.** A normal-priority data message is deferred by Doze
 *   and, more to the point, does not put the app on the temporary allowlist that
 *   permits a foreground-service start from the background on Android 12+. The
 *   promotion in [BackgroundWake] would then be refused and the node would run
 *   unprotected — which is survivable, and is not what was asked for.
 * - **A `data` payload and no `notification` block.** A message carrying
 *   `notification` is handled by the system tray when the app is backgrounded
 *   and [onMessageReceived] is never called at all.
 *
 * `android/docs/wallet-node-device-tests.md` §1 is where those live, because
 * they are the half of this claim that no Android test can assert.
 */
class BittrMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        // `message.data`, not the whole RemoteMessage: the wake decision is a
        // question about a string map, and handing the wallet module an FCM type
        // would put Firebase on :core:wallet-ldk's classpath for no gain.
        deliver(applicationContext, message.data)
    }

    /**
     * A new registration token for this install.
     *
     * Nothing is done with it yet, and that is a gap rather than a decision:
     * iOS posts its APNs token to `POST /customer` at signup
     * (`Transfer2ViewController.swift:363`) and the backend addresses pushes to
     * it. Android has no backend client to post from — Settings → Device details
     * → Device token is still the "ask, and show nothing" half. **Until
     * something registers this token, no wake can be delivered to this install
     * in production**, which is worth being loud about because everything else
     * in this file would pass its tests regardless.
     *
     * The token is **not logged**. It is a per-install device identifier and
     * `shared/docs/privacy-disclosure.md` lists it as one; logcat is readable by
     * anything with an adb cable. Only the fact that one arrived is.
     */
    override fun onNewToken(token: String) {
        Log.i(TAG, "FCM registration token refreshed (${token.length} chars); nothing registers it yet.")
    }

    companion object {

        private const val TAG = "BittrMessaging"

        /**
         * Hand a data payload to the wallet, and say what happened.
         *
         * Public and `Context`-taking rather than a private method on the
         * service, so the device test can drive the whole decision path on the
         * installed app without persuading the platform to start a background
         * service for it. The half that remains untested by that route is
         * `FirebaseMessagingService`'s own dispatch, and that is Google's code
         * plus a manifest entry — `FcmWakeTest` asserts the manifest entry
         * separately, which is the part this repo can get wrong.
         */
        fun deliver(context: Context, data: Map<String, String>): WakeOutcome {
            val wake = EntryPointAccessors
                .fromApplication(context.applicationContext, WalletWakeEntryPoint::class.java)
                .backgroundWake()
            val outcome = wake.onDataMessage(data)
            Log.i(TAG, "Background wake: $outcome")
            return outcome
        }
    }
}

/**
 * How a `Service` reaches the singleton graph.
 *
 * In `main` on purpose — see [BittrMessagingService] on why declaring an
 * `@EntryPoint` in `androidTest` compiles, is not aggregated into the app's
 * component, and throws on the device.
 *
 * Separate from `WalletGraph`, which reaches the same [BackgroundWake] plus the
 * wallet and the payment surface, because this is the one a push message can
 * reach: an FCM data message is allowed to start the wallet and nothing else.
 * `WalletGraph.backgroundWake` says the same thing from the other side.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface WalletWakeEntryPoint {
    fun backgroundWake(): BackgroundWake
}
