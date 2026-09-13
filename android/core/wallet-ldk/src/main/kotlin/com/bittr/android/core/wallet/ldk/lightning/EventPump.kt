package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive

/**
 * Where the loop stopped, and whether that is a problem.
 *
 * iOS's listener has no equivalent: its `while !Task.isCancelled` ends by being
 * cancelled in `deinit`, and nothing observes why. On Android the loop runs in a
 * service that has to decide whether to restart it, so the reason is a value.
 */
enum class EventPumpStop {

    /** The scope was cancelled — a stop, a wipe, or the process going down. Expected. */
    Cancelled,

    /**
     * There is no node any more. `NodeLifecycle.current` returned null.
     *
     * iOS's `guard let node = self.ldkNode else { return }`
     * (`BitcoinManager.swift:709`). Expected too: a wipe nulls the node while the
     * loop is suspended inside `nextEventAsync`.
     */
    NodeGone,

    /**
     * Reading the next event threw.
     *
     * Not expected, and not recoverable from inside the loop: if
     * `nextEventAsync` is failing, spinning on it burns the CPU until the battery
     * does. The service restarts the pump when it restarts the node.
     */
    ReadFailed,
}

/** How [EventPump.run] ended. */
data class EventPumpOutcome(
    val stop: EventPumpStop,
    /** Set when [stop] is [EventPumpStop.ReadFailed]. */
    val cause: Throwable? = null,
    /** Events acknowledged to ldk-node during this run. The pump's unit of progress. */
    val acknowledged: Int = 0,
)

/**
 * The node's event queue, as the two calls the loop makes.
 *
 * @param E the event. `org.lightningdevkit.ldknode.Event` in production; nothing
 *   here may name it.
 */
interface EventPumpPort<E : Any> {

    /**
     * `node.nextEventAsync()`, or null when there is no node.
     *
     * Suspends until an event arrives. Implementations must re-read the live node
     * on every call rather than capture one — iOS binds it once *per iteration*
     * and says why at `BitcoinManager.swift:704–709`, and the null return is that
     * guard.
     */
    suspend fun nextEvent(): E?

    /**
     * `node.eventHandled()`.
     *
     * Tells ldk-node the event at the head of its queue has been dealt with and
     * may be dropped. **Until this returns, the event is still queued**, which is
     * the entire basis of the replay guarantee below.
     */
    fun eventHandled()
}

/**
 * What the app does with an event, and whether it finished doing it.
 *
 * `coreVC?.ldkEventReceived(event:)` on iOS, dispatched to the main actor
 * (`BitcoinManager.swift:712–714`). Suspending here because on Android the same
 * work — writing a payment to the cache, posting a notification — has to be
 * allowed to finish before the event is acknowledged.
 */
fun interface EventHandler<E : Any> {

    /**
     * Handle [event]. Throwing means *not handled*: the event will not be
     * acknowledged and ldk-node will deliver it again.
     */
    suspend fun handle(event: E)
}

/**
 * Events ldk-node has already delivered and the app has already shown.
 *
 * Port of `CacheManager.hasHandledEvent` / `didHandleEvent`
 * (`HandlePaymentNotification.swift:308–313`), which is a *second*
 * deduplication sitting on top of ldk-node's own queue. It exists because the
 * app has two readers: this loop, and the push-notification service extension
 * that wakes on a payment and reads the same queue. Either can see an event
 * first.
 *
 * The exemption is the interesting half. iOS dedups everything **except**
 * payment failures:
 *
 * ```swift
 * if CacheManager.hasHandledEvent(event: "\(event)"), !event.isPaymentFailed() { ... }
 * ```
 *
 * because a payment that fails, is retried, and fails again produces a byte-identical
 * description the second time, and suppressing it leaves the user staring at a
 * spinner for a payment that has already failed twice.
 */
interface EventLedger<E : Any> {

    /**
     * Whether this event has been shown before.
     *
     * Implementations key on the event's rendered description, as iOS does.
     * Returning false for a payment failure — always — is what preserves the
     * exemption above, and the ledger rather than the pump owns that rule because
     * the pump may not look inside `E`.
     */
    fun hasHandled(event: E): Boolean

    /** Record that this event has been shown. Called before [EventHandler.handle]. */
    fun recordHandled(event: E)
}

/**
 * The event listener, as a loop whose acknowledgement order is the point.
 *
 * Port of `listenForEvents()` (`BitcoinManager.swift:697–719`). iOS runs it as a
 * `Task` stored on `BitcoinManager` and cancelled in `deinit`
 * (`BitcoinManager.swift:46`, `:60–62`, `:721–724`).
 *
 * ## This is the part of BIT-125 with no iOS analogue
 *
 * An iOS app is suspended, not killed, and its `BitcoinManager` is a singleton
 * that outlives every screen. The loop therefore has exactly one interesting
 * lifetime event — `deinit` — and iOS handles it in three lines. On Android the
 * process is killed routinely and without warning, and the loop can be stopped
 * anywhere, including between the handler returning and `eventHandled()` being
 * called. So the ordering below is a durability contract rather than a style
 * choice:
 *
 * > **An event consumed but not acknowledged is replayed. An event acknowledged
 * > but not persisted is lost.**
 *
 * Everything in [run] follows from reading those two sentences as an instruction
 * about which way to fail:
 *
 * 1. **Acknowledge last.** `eventHandled()` is called only after
 *    [EventHandler.handle] has returned normally. Process death anywhere before
 *    that leaves the event at the head of ldk-node's queue and the next start
 *    delivers it again.
 *
 * 2. **A handler that throws is not an acknowledgement.** iOS writes
 *    `try? node.eventHandled()` *unconditionally* after the `MainActor.run`,
 *    which on that platform is nearly always reached — but the shape is wrong for
 *    a port, because the Android handler does real work that can fail (a
 *    notification, a cache write) and acknowledging it anyway is the "lost"
 *    branch of the contract. **This is a deliberate divergence from iOS**, flagged
 *    rather than absorbed: it makes Android replay where iOS drops. Replay is the
 *    recoverable direction — the duplicate is caught by [EventLedger] — and drop
 *    is not.
 *
 * 3. **The acknowledgement's own failure does not stop the loop.** `eventHandled()`
 *    throws when the node is going down, which is exactly when the loop is about
 *    to exit anyway. iOS's `try?` is right here and is kept. The consequence is a
 *    replay, which the contract permits.
 *
 * 4. **Record before handling, not after.** [EventLedger.recordHandled] runs
 *    *before* [EventHandler.handle], matching iOS's ordering
 *    (`HandlePaymentNotification.swift:313`, which writes the cache then enters
 *    the `switch`). It looks backwards and is not: the ledger's job is to stop the
 *    *user* being shown the same payment twice when two readers race for it, and a
 *    ledger written after a handler that posts a notification cannot do that. The
 *    replay guarantee is ldk-node's queue, not this cache, and conflating the two
 *    would break both.
 *
 * ## What is not decided here
 *
 * Which scope the loop runs in, and therefore whether it survives backgrounding,
 * is the host's — a foreground service on Android, nothing at all on iOS. The
 * pump takes the scope's cancellation as its stop signal and reports
 * [EventPumpStop.Cancelled]; choosing a scope that dies when an Activity does
 * would be a bug in the caller, not here. That wiring is BIT-123's.
 *
 * Proved by `EventPumpTest`.
 */
class EventPump<E : Any>(
    private val port: EventPumpPort<E>,
    private val ledger: EventLedger<E>,
    private val handler: EventHandler<E>,
    /**
     * Where a swallowed `eventHandled()` failure goes. iOS drops it on the floor
     * with `try?`; defaulted to a no-op so the pump has no logging dependency.
     */
    private val onAcknowledgeFailure: (Throwable) -> Unit = {},
) {

    /**
     * Read, handle and acknowledge events until the node goes, the scope is
     * cancelled, or a read fails.
     *
     * Never returns on its own while a node is present — this is the loop, not a
     * poll.
     */
    suspend fun run(): EventPumpOutcome {
        var acknowledged = 0

        while (currentCoroutineContext().isActive) {
            val event = try {
                port.nextEvent()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return EventPumpOutcome(EventPumpStop.ReadFailed, failure, acknowledged)
            } ?: return EventPumpOutcome(EventPumpStop.NodeGone, acknowledged = acknowledged)

            // iOS's `if Task.isCancelled { break }` between the await and the
            // handler. Cancellation here is a replay, which is allowed; running
            // the handler on a wallet that is being wiped is not.
            if (!currentCoroutineContext().isActive) break

            if (!ledger.hasHandled(event)) {
                // Point 4. Before the handler, as iOS orders it.
                ledger.recordHandled(event)
                // Point 2. A throw here propagates: the event is not
                // acknowledged, and whatever the handler failed at is not this
                // loop's to interpret.
                handler.handle(event)
            }

            // Point 1, then point 3.
            try {
                port.eventHandled()
                acknowledged++
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                onAcknowledgeFailure(failure)
            }
        }

        return EventPumpOutcome(EventPumpStop.Cancelled, acknowledged = acknowledged)
    }
}
