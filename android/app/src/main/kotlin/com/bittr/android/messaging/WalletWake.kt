package com.bittr.android.messaging

import android.content.Context
import android.util.Log
import com.bittr.android.core.push.fcm.DataMessageWake
import com.bittr.android.core.wallet.ldk.host.BackgroundWake
import com.bittr.android.core.wallet.ldk.host.WakeOutcome
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent

/**
 * The client end of the background wake — **BIT-133** — as the app's binding of
 * [DataMessageWake].
 *
 * This used to be a `FirebaseMessagingService` of its own, in `:app`. BIT-41's
 * push client declared another in `:core:push-fcm`, and two services filtering
 * `com.google.firebase.MESSAGING_EVENT` is not a build error but a coin toss at
 * dispatch: one of the two jobs silently never runs. So since **BIT-146** the
 * one service is `:core:push-fcm`'s, it calls this before it decodes the
 * payload, and nothing in `:app` touches Firebase.
 *
 * Deliberately almost empty. Everything that decides anything is
 * [BackgroundWake] in `:core:wallet-ldk`, which runs on the JVM under
 * `BackgroundWakeTest`.
 *
 * ## Why it is in `:app` and not in `:core:wallet-ldk` or `:core:push-fcm`
 *
 * The wallet module owns the node and must not own the app's push identity, and
 * the push module must not own the wallet. This resolves its dependency out of
 * the *application's* Hilt graph, which is the one place the wallet
 * implementation is chosen (`di/WalletModule`).
 *
 * ## `EntryPointAccessors`, not injection
 *
 * Resolving from the application context at the moment of use keeps [deliver]
 * callable with nothing but a `Context`, which is what `FcmWakeTest` does on the
 * installed app — without persuading the platform to start a background service
 * for it, which API 26+ refuses a test.
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
 *   and does not put the app on the temporary allowlist that permits a
 *   foreground-service start from the background on Android 12+. The promotion
 *   in [BackgroundWake] would then be refused and the node would run
 *   unprotected — which is survivable, and is not what was asked for.
 * - **A `data` payload and no `notification` block.** A message carrying
 *   `notification` is handled by the system tray when the app is backgrounded
 *   and `onMessageReceived` is never called at all.
 *
 * `android/docs/wallet-node-device-tests.md` §1 is where those live, because
 * they are the half of this claim that no Android test can assert.
 */
class WalletWake(private val context: Context) : DataMessageWake {

    override fun onDataMessage(data: Map<String, String>) {
        deliver(context, data)
    }

    companion object {

        private const val TAG = "BittrMessaging"

        /**
         * Hand a data payload to the wallet, and say what happened.
         *
         * Public and `Context`-taking so the device test can drive the whole
         * decision path on the installed app. The half that remains untested by
         * that route is `FirebaseMessagingService`'s own dispatch, and that is
         * Google's code plus a manifest entry — `FcmWakeTest` asserts the
         * manifest entry separately, which is the part this repo can get wrong.
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
 * How the wake reaches the singleton graph.
 *
 * In `main` on purpose — see [WalletWake] on why declaring an `@EntryPoint` in
 * `androidTest` compiles, is not aggregated into the app's component, and throws
 * on the device.
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
