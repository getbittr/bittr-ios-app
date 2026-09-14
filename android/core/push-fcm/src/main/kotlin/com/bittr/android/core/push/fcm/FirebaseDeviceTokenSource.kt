package com.bittr.android.core.push.fcm

import com.bittr.android.core.network.DeviceTokenSource
import com.google.android.gms.tasks.Task
import com.google.firebase.messaging.FirebaseMessaging
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * [DeviceTokenSource] over FCM — BIT-41 item 3's half of item 5.
 *
 * ## It does not check `POST_NOTIFICATIONS`, and that is the point
 *
 * BIT-41 deliverable 3 states it and it is the single most load-bearing fact in this file:
 * *"the runtime permission does **not** gate data-message delivery — the silent payout path
 * works without it; only user-visible types need it."*
 *
 * A lightning payout arrives as an FCM **data message** (`api-contract` §3.3: data-only, no
 * `notification` block, because a message carrying one is handed to the system tray and the app
 * is not invoked while backgrounded). Data messages are delivered to
 * [BittrMessagingService.onMessageReceived] whether or not the customer ever granted
 * `POST_NOTIFICATIONS`. Only *posting a visible notification* needs the grant.
 *
 * So a client that waits for the permission before fetching a token would break the payout path
 * for every customer who declined a dialog about alerts — and it would do it silently, because
 * everything else still works. §4.3's invariant then converts that into a permanent `onchain`
 * downgrade: no token sent, no route, no instant payouts.
 *
 * `FirebaseMessagingGuardTest` in `:app` holds this shape: no permission check reaches this
 * module, `:core:push` or `:core:network` — the three modules on the payout path.
 *
 * ## Why `Task` is unwrapped by hand
 *
 * `kotlinx-coroutines-play-services` exists and provides `Task.await()`. It is one more artefact
 * on the graph of the one module allowed to reach Firebase, for twelve lines that are easier to
 * read than the dependency note explaining them. The cancellation semantics matter and are
 * spelled out below rather than inherited.
 */
class FirebaseDeviceTokenSource(
    /**
     * Resolved lazily and defensively, never at construction.
     *
     * `FirebaseMessaging.getInstance()` throws when no default `FirebaseApp` has been
     * initialised, and that is reachable in three places worth caring about: a build whose
     * `google-services.json` did not produce resources, a JVM/Robolectric test where the
     * auto-init `ContentProvider` never ran, and a device with no usable Play services. All
     * three should produce "no token", which every caller already handles as §2.1's ordinary
     * async race — not an exception thrown out of the app's `onStart`.
     */
    private val messaging: () -> FirebaseMessaging? = {
        runCatching { FirebaseMessaging.getInstance() }.getOrNull()
    },
) : DeviceTokenSource {

    /**
     * The current registration token, or null when it could not be obtained.
     *
     * Null covers Play services being absent or out of date, a device with no network at first
     * launch, and the ordinary case of retrieval simply not having finished — §2.1 blesses that
     * last one explicitly, which is why this returns null rather than throwing. A caller that
     * treated it as an error would spend the §2.3 rule 2 retry budget on the seconds after
     * launch.
     */
    @Suppress("DEPRECATION") // getToken(); see the note on [invalidate] and BIT-145.
    override suspend fun current(): String? = messaging()?.token?.awaitOrNull()

    /**
     * Deletes the registration so the next [current] mints a fresh token — the recovery for
     * §4.2's `invalid` and `unregistered`.
     *
     * Failure is swallowed on purpose. The caller's next move is to read [current] and compare
     * it against the token that was rejected; if the delete did not take, the token is unchanged
     * and `DeviceTokenLifecycle` declines to re-post it. That check is a better guard than this
     * call's return value, because it is true of the state rather than of the attempt.
     *
     * ## Both calls in this class are deprecated as of firebase-messaging 25.1.3
     *
     * `getToken()` and `deleteToken()` are superseded by `register()` / `unregister()`, which
     * return `Task<Void>` and deliver the token through `FirebaseMessagingService.onRegistered`
     * instead of returning it. That is a different shape, not a rename: the pull becomes a push,
     * so the app-start reconciliation stops being "read the token and compare" and becomes
     * "ask, then handle the callback".
     *
     * Not migrated here, for two reasons. BIT-41's deliverable 5 is written against `getToken()`
     * and the deprecated calls still work; and the migration cannot be verified from this
     * workspace — there is no device, no emulator running Play services, and no sender. Doing it
     * blind on the one path a customer's payouts depend on trades a warning for an untested
     * rewrite. Filed as **BIT-145**, to be done alongside BIT-142 where a real Firebase project
     * is in the loop. [BittrMessagingService] already implements `onRegistered`, so the receive
     * half is forward-compatible today.
     */
    @Suppress("DEPRECATION")
    override suspend fun invalidate() {
        messaging()?.deleteToken()?.awaitOrNull()
    }
}

/**
 * Suspends until [this] completes, yielding null on failure or cancellation.
 *
 * `invokeOnCancellation` is deliberately absent: a `Task` from Play services cannot be
 * cancelled, so registering a handler that cannot act would only suggest otherwise. The
 * continuation is resumed exactly once by [Task.addOnCompleteListener], which Play services
 * guarantees fires once — including for a task that has already completed, which is the case
 * this would otherwise deadlock on.
 */
private suspend fun <T> Task<T>.awaitOrNull(): T? = suspendCancellableCoroutine { continuation ->
    addOnCompleteListener { task ->
        continuation.resume(if (task.isSuccessful) task.result else null)
    }
}
