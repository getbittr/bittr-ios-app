package com.bittr.android.core.push.fcm

import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.push.PushEnvelopeDecoder
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * What the app does with a decoded push, and with a rotated token.
 *
 * The seam between this module and the rest of the app. It exists so that
 * [BittrMessagingService] contains no decisions at all — it receives bytes, calls
 * [PushEnvelopeDecoder], and hands the result over. Everything that could be wrong about
 * *behaviour* is then in `:core:push` and `:core:network`, where 99 JVM tests can reach it,
 * rather than in a class only a real device and a real Firebase project can instantiate.
 */
interface PushDelivery {

    /**
     * A decoded payload arrived. Called on a background dispatcher.
     *
     * [PushEnvelope.Unknown] is passed through rather than filtered, because the reason it was
     * unknown is the only signal that would explain a payout the customer never saw — and §3.2
     * describes at least one way the two transports can cross.
     */
    suspend fun onPush(envelope: PushEnvelope)

    /**
     * FCM minted a new registration token. Wired to
     * `DeviceTokenLifecycle.onNewToken` — `api-contract` §2.3.
     */
    suspend fun onNewToken(token: String)
}

/**
 * Implemented by the `Application` so [BittrMessagingService] can find its bindings.
 *
 * A `Service` is constructed by the framework, so it cannot take constructor arguments and has
 * to look its collaborators up. Two ways to do that: Hilt's `@AndroidEntryPoint`, which means
 * putting the Hilt plugin and KSP on the one module allowed to reach Firebase, or asking the
 * `Application` — which is already a process-wide singleton with a well-defined lifetime, and
 * which is where the object graph lives anyway.
 *
 * The second, because it keeps this module's dependency list to Firebase and the two `:core`
 * modules it bridges, and because a `null` from a wrong-typed application is a test assertion
 * rather than a generated-code failure.
 */
interface PushHost {
    val pushDelivery: PushDelivery

    /** The wallet's background wake — see [DataMessageWake] and BIT-146. */
    val dataMessageWake: DataMessageWake
}

/**
 * What the app does with a data message *before* it is decoded — the wallet's background wake
 * (BIT-133).
 *
 * A separate seam from [PushDelivery] because it is a different job on a different clock. The
 * wake has to promote the process to a foreground service synchronously, inside
 * `onMessageReceived`'s budget, and only a high-priority data message buys the exemption that
 * permits that from the background; the decode is allowed to take as long as its one local write
 * takes. Folding the wake into [PushDelivery.onPush] would put it behind the decode, which is the
 * wrong order for the one call that has a deadline.
 *
 * Why it lives here at all (BIT-146): FCM dispatches `com.google.firebase.MESSAGING_EVENT` to one
 * service. BIT-41 and BIT-133 each declared their own, and the manifest merger unions two
 * `<service>` entries rather than rejecting them — after which whichever resolves first receives
 * every message and the other silently never runs. So there is one service, in this module, and
 * both jobs reach it. This module stays free of the wallet: the app binds this to
 * `BackgroundWake`, which is in `:core:wallet-ldk`.
 */
fun interface DataMessageWake {

    /** Called on FCM's thread, before the payload is decoded. Must not wait for a node start. */
    fun onDataMessage(data: Map<String, String>)
}

/**
 * The FCM receiver — BIT-41 item 3.
 *
 * ## The three things it must get right, and nothing else
 *
 * **1. Decode through `:core:push`, never inline.** §3.2 makes an FCM `data` map `string ->
 * string` carrying exactly one key — the discriminator — whose value is the JSON-encoded object
 * APNS receives natively. [PushEnvelopeDecoder] implements that, together with the three BIT-30
 * decode rules the contract ratified at rev 4 (`amount_msats` is `int64`; `bitcoin_amount` is a
 * BTC decimal string parsed with `BigDecimal`; every field optional, unknown keys ignored). All
 * of it is covered by JVM tests. Re-reading `data` here would put an untestable second parser on
 * the money path.
 *
 * **2. Do the work before returning.** `onMessageReceived` runs on FCM's own executor and the
 * process may be killed once it returns — the app was likely started *by* this message. §3.3
 * requires `android.priority: "high"` so Doze does not defer a payout push; that buys delivery,
 * not lifetime. Handing the payload to a fire-and-forget scope would lose exactly the
 * background payouts this issue exists to make work, and would lose them invisibly, because the
 * foreground case (where the process survives) would test green.
 *
 * **3. Wake the wallet before decoding (BIT-146).** This is the only receiver for
 * `MESSAGING_EVENT` in the app, so it also carries BIT-133's background wake, through
 * [PushHost.dataMessageWake]. The wake goes first because it is the call with a deadline; the
 * decode follows even if the wake throws.
 *
 * ## What it deliberately does not do
 *
 * No notification is posted here, and no notification channel is created. The payout path is
 * silent by design — §3.3's data-only rule exists so the app is invoked while backgrounded — and
 * the user-visible types (`bittr_notification`, `htlc_notification`) carry approved copy that
 * belongs with the screens, not with a receiver. It also does not check `POST_NOTIFICATIONS`:
 * see [FirebaseDeviceTokenSource] for why that check would silently break the payout path.
 */
class BittrMessagingService : FirebaseMessagingService() {

    /**
     * For [onNewToken] only, which has no such constraint: `onNewToken` is a notification that
     * the token changed, the value is durable, and the reconciliation at app start
     * (`DeviceTokenLifecycle.syncOnAppStart`) is the backstop if this call does not finish.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val delivery: PushDelivery?
        get() = (application as? PushHost)?.pushDelivery

    /**
     * Blocks until the payload has been handled — see the class note on process lifetime.
     *
     * `runBlocking` on a framework callback is normally a mistake and here it is the
     * requirement. The thread is FCM's, the contract is that the message is handled before this
     * returns, and the alternative — a `goAsync`-style wakelock — is not available to a service
     * callback. The work itself is a decode plus at most one local write.
     */
    override fun onMessageReceived(message: RemoteMessage) {
        val host = application as? PushHost ?: return
        try {
            // Wake first: the promotion to a foreground service has a deadline and the decode
            // does not. See [DataMessageWake].
            host.dataMessageWake.onDataMessage(message.data)
        } finally {
            // And the decode regardless. A wake that throws must not cost the customer a payout
            // push; the exception still surfaces once the payload has been handed over.
            val envelope = PushEnvelopeDecoder.decode(message.data)
            runBlocking { host.pushDelivery.onPush(envelope) }
        }
    }

    /**
     * FCM rotated the token.
     *
     * Note what this callback cannot cover, and why `DeviceTokenLifecycle` has a second entry
     * point: a rotation that happens while the app is **not running** delivers this at most once,
     * to a process that may not exist. The launch reconciliation is not belt-and-braces — it is
     * the only thing that catches a token rotated during a restore.
     *
     * Deprecated in firebase-messaging 25.1.3 — see [onRegistered], which is the replacement and
     * is implemented beside it. Both are wired, deliberately: this one is what BIT-41's brief
     * specifies and what the SDK still calls, and the migration is BIT-145.
     */
    @Deprecated("Deprecated in firebase-messaging 25.1.3; see onRegistered and BIT-145.")
    @Suppress("DEPRECATION")
    override fun onNewToken(token: String) {
        deliver(token)
    }

    /**
     * The replacement for [onNewToken] in firebase-messaging 25.1.3, paired with
     * `FirebaseMessaging.register()`.
     *
     * Implemented now rather than after the migration, and it costs one line to do so. The SDK
     * decides which of the two callbacks it delivers a token through; if a future version stops
     * calling [onNewToken], a client that implemented only that one goes quiet — and it goes
     * quiet in the way this whole issue is about, with everything else still working and the
     * payout route dead. Routing both into the same place means the migration cannot break the
     * receive path, only tidy it.
     */
    override fun onRegistered(token: String) {
        deliver(token)
    }

    private fun deliver(token: String) {
        val handler = delivery ?: return
        scope.launch { handler.onNewToken(token) }
    }
}
