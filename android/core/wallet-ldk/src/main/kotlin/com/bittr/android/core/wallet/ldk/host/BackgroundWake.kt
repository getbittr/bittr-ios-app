package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * What a data message did, or why it did nothing.
 *
 * A sealed type rather than a boolean because four of the five answers below are
 * *reasons not to start a node*, and "the wake did nothing" is the outcome a
 * reader of a bug report needs told apart. It is also what
 * `FcmWakeTest` asserts on: a wake that reached `WalletService.start()` and a
 * wake that was dropped for want of a wallet are the same green if the only
 * evidence is that nothing crashed.
 */
sealed interface WakeOutcome {

    /**
     * The message carried no [BackgroundWake.WAKE_KEY], so it was not addressed
     * to the wallet.
     *
     * The normal outcome for every push that is *not* a wake, and the reason
     * this class refuses to start on anything it is handed — see
     * [BackgroundWake] on why any-message-wakes-the-node is the wrong default.
     *
     * @param keys the data keys that were present, for the log line. Keys only,
     *   never values: the payload comes from the network and the one thing a
     *   wake message might plausibly grow is a payment hash.
     */
    data class NotAWake(val keys: List<String>) : WakeOutcome

    /**
     * There is no wallet on this device — no seed, so nothing to start a node
     * against.
     *
     * Reached on a fresh install that has been through signup far enough to have
     * an FCM token and no further, and after a wipe. Starting here would build a
     * node against a vault that reads null, which surfaces as a node start
     * failure several layers down rather than as the one-line fact it is.
     */
    data object NoWallet : WakeOutcome

    /**
     * The process is held up and the start is running in the wallet's scope.
     *
     * This is what [BackgroundWake.onDataMessage] returns; it is not the end of
     * the story, and [Woken] or [WakeFailed] follows it on [BackgroundWake.last].
     */
    data class Waking(val reason: String) : WakeOutcome

    /** The start returned. Whether a node came *up* is [WalletNodeHost]'s answer. */
    data class Woken(val reason: String) : WakeOutcome

    /** The start threw. The foreground promotion has been released. */
    data class WakeFailed(val reason: String, val cause: Throwable) : WakeOutcome
}

/**
 * The wallet's half of a background wake: an FCM data message arrives, and the
 * node starts without anyone typing a PIN.
 *
 * **BIT-133.** `wallet-core-spec` §6's K2 wants a data message to reach
 * `Node.start()`. Until this class there was nothing on the client listening —
 * `verify-fcm-service-account.sh` checks a *backend* credential — so the claim
 * had no path to be true or false about. The Android entry point is
 * `com.bittr.android.messaging.BittrMessagingService`, which is twenty lines and
 * lives in `:app` because it needs the Hilt graph; everything that decides
 * anything is here, where it runs on the JVM.
 *
 * ## Why the seam is [start] and not `WalletNodeHost` directly
 *
 * BIT-133's own wording is "start the node the way `UnlockViewModel` does", and
 * the way `UnlockViewModel` does it is `WalletService.start()`. Binding to that
 * seam rather than to the host buys two things:
 *
 * - In a build with no `LdkEnvironment` — the normal state of a clone, and the
 *   APK CI installs — `WalletService` is `SeedWalletService` and `start()` is a
 *   no-op. The wake path still exists, still runs end to end, and still proves
 *   itself on a device; it simply has no node to bring up. A wake bound to
 *   `WalletNodeHost` would not exist at all in that build, and the on-device
 *   test of the wiring would have nothing to test.
 * - In a configured build it *is* `WalletNodeHost.start()`, through
 *   `NodeBackedWalletService`, so the foreground promotion, the start
 *   collapsing and the runner restart all come for free.
 *
 * ## The promotion is synchronous, and that is the whole trick
 *
 * `FirebaseMessagingService.onMessageReceived` runs on a worker thread and the
 * process may be frozen again shortly after it returns. A node start takes tens
 * of seconds. So the one thing that cannot be deferred is [presence]`.promote()`
 * — it is what stops the process being a cached process — and this class does it
 * *before* it launches anything, on the caller's thread, for the same reason
 * [WalletNodeHost.start] promotes before it starts rather than after.
 *
 * [WalletNodeHost] will promote again a moment later. That is not a redundancy
 * to remove: [ForegroundPresence] documents both methods as safe to call
 * repeatedly precisely so that "the node is up" and "the process is protected"
 * can be re-asserted by whoever notices first.
 *
 * **The promotion is allowed to fail, and on Android 12+ it routinely will.**
 * `ServiceForegroundPresence` swallows `ForegroundServiceStartNotAllowedException`
 * and the start continues unprotected — the state the process was already in.
 * What buys the exemption when it *is* granted is the message's priority: a
 * **high-priority** FCM data message puts the app on the temporary allowlist
 * that permits a foreground-service start from the background. A normal-priority
 * message does not, and will also be deferred by Doze. That is a property of
 * what the sender sets, not of anything in this file, and it is written down in
 * `android/docs/wallet-node-device-tests.md` §1 because it is the sender-side
 * requirement most easily lost.
 *
 * ## Why a keyed message and not every message
 *
 * Waking the node is expensive — a foreground service, a permanent notification,
 * a chain sync — and the FCM project this app is registered in also carries
 * ordinary user-facing pushes (iOS registers the device token at signup and the
 * backend sends payment notifications to it; see `shared/docs/privacy-disclosure.md`).
 * A receiver that started a node on any data message would turn every one of
 * those into a node start. So the ask is explicit: a data field named
 * [WAKE_KEY], whose value is a free-form [reason][WakeOutcome.Waking.reason]
 * recorded in the log and nowhere else.
 *
 * ## What this deliberately does not do
 *
 * **It does not deduplicate.** FCM redelivers, and two wakes arriving together
 * is the expected case, not the pathological one. [WalletNodeHost] already
 * collapses concurrent starts through `NodeLifecycle.startOnce` and answers the
 * second caller `AlreadyRunning`; a second mechanism here would be a second
 * answer to the same question, and the one that could get it wrong.
 *
 * **It does not stop the node afterwards.** A wake that started a node leaves it
 * running, held up by the foreground service, until something asks for it to
 * stop. Deciding when a woken node should go back down — and what that costs a
 * user's battery — is K8's measurement, which needs a device; see BIT-132.
 *
 * Proved by `BackgroundWakeTest`.
 */
class BackgroundWake(
    /**
     * The wallet's process-lifetime scope — the same one [WalletNodeHost] runs
     * its starts and runners in. Never a service's scope: the point of the wake
     * is to survive the message-handling callback returning.
     */
    private val scope: CoroutineScope,
    /**
     * What holds the process up. Promoted synchronously on a wake — see the
     * class comment. `ForegroundPresence.None` in a build with no node, which is
     * honest rather than degraded: there is nothing to protect.
     */
    private val presence: ForegroundPresence,
    /** Is there a wallet on this device at all. `WalletService.state`, as a question. */
    private val walletState: () -> WalletState,
    /** `WalletService::start` — `UnlockViewModel`'s seam, and the issue's wording. */
    private val start: suspend () -> Unit,
    /** Where every outcome goes for the log. Defaulted off so tests read [last]. */
    private val report: (WakeOutcome) -> Unit = {},
) {

    private val _last = MutableStateFlow<WakeOutcome?>(null)

    /**
     * The most recent outcome, latest phase wins.
     *
     * A field rather than only a callback because a wake happens with nobody
     * watching by definition, and after the fact the only evidence there is
     * would otherwise be a logcat line on a device that has since been rebooted.
     * `FcmWakeTest` is what reads it on the installed app; a diagnostics screen
     * is the obvious second reader and does not exist yet.
     */
    val last: StateFlow<WakeOutcome?> = _last.asStateFlow()

    /**
     * Handle one data message. Returns the outcome that was decided *here*,
     * synchronously; the start itself continues in [scope].
     *
     * @param data `RemoteMessage.getData()` — FCM's data payload, which is
     *   always a string-to-string map.
     */
    fun onDataMessage(data: Map<String, String>): WakeOutcome {
        val reason = data[WAKE_KEY]
            ?: return settle(WakeOutcome.NotAWake(data.keys.sorted()))

        // Asked before the promotion, not after: a device with no wallet must
        // not put up a foreground notification for a node it is not going to
        // start.
        if (walletState() == WalletState.Uninitialized) return settle(WakeOutcome.NoWallet)

        presence.promote()

        // Settled before the launch rather than after it, so that [last] moves
        // Waking -> Woken in that order on every dispatcher. Launching first and
        // settling afterwards reads the same and is not: on a dispatcher that
        // runs the child eagerly — an unconfined one in a test, and any
        // already-idle thread in production — the start completes inside
        // `launch` and `Woken` is then overwritten by the `Waking` that
        // preceded it. The observable state would settle on the earlier phase.
        val waking = settle(WakeOutcome.Waking(reason))

        scope.launch {
            try {
                start()
                settle(WakeOutcome.Woken(reason))
            } catch (cancellation: CancellationException) {
                // The scope is going down with the process. Nothing to release
                // and nothing to report — see WalletNodeHost.start, which makes
                // the same distinction for the same reason.
                throw cancellation
            } catch (failure: Throwable) {
                // Demote, and accept that this is occasionally redundant.
                // WalletNodeHost releases the presence itself on every definite
                // failure, so on that path this is a second `stopService` on a
                // service that is already stopped — documented as a no-op. The
                // path it exists for is the other one: a `start` that threw
                // before reaching the host at all would otherwise leave a
                // foreground notification up over nothing, permanently, with no
                // node behind it and no way for the user to dismiss it.
                presence.demote()
                settle(WakeOutcome.WakeFailed(reason, failure))
            }
        }

        return waking
    }

    private fun settle(outcome: WakeOutcome): WakeOutcome {
        _last.value = outcome
        report(outcome)
        return outcome
    }

    companion object {

        /**
         * The data field that asks for a node start.
         *
         * Namespaced, because the payload is shared with whatever else the
         * backend sends this app, and a key called `wake` in a map that also
         * carries a notification's fields is a collision waiting to happen. Its
         * value is a label for the log — `"payment"`, `"channel"` — not a
         * command; nothing branches on it and nothing should, because it arrives
         * from the network.
         */
        const val WAKE_KEY = "bittr_wake"
    }
}
