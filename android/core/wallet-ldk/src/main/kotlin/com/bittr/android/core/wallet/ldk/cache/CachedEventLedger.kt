package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.lightning.EventLedger

/**
 * [EventLedger] over a [WalletCache] — the port of `CacheManager.hasHandledEvent`
 * / `didHandleEvent` (`HandlePaymentNotification.swift:308–313`).
 *
 * ## The payment-failure exemption is the whole reason this class has a branch
 *
 * ```swift
 * if CacheManager.hasHandledEvent(event: "\(event)"), !event.isPaymentFailed() { … }
 * ```
 *
 * A payment that fails, is retried, and fails again produces a byte-identical
 * description the second time. Suppressing the second one leaves the user
 * watching a spinner for a payment that has already failed twice — so
 * [hasHandled] answers false for a payment failure **before it looks at the
 * store**, which is what reproduces the `!event.isPaymentFailed()` clause.
 *
 * It lives here rather than in `EventPump` because the pump is generic over the
 * event type and may not look inside it; [isExemptFromDeduplication] is how the
 * adapter, which can, supplies the one fact needed. Note what that means for
 * [recordHandled]: it is still called for an exempt event, because iOS's `else`
 * branch calls `didHandleEvent` unconditionally and a failure that later
 * succeeds must not be re-shown from a *different* reader.
 *
 * ## The key is a rendering, and renderings are not free
 *
 * iOS keys on `"\(event)"`. Two properties are load-bearing and neither is
 * automatic on Kotlin: the rendering must be the same in every process — see
 * `LdkEventKey`, which fixes the one ldk-node type where it is not — and it must
 * survive a round trip through the store, which is why [FileWalletCache] encodes
 * entries rather than writing them as lines.
 *
 * An ldk-node upgrade that changes a `toString` invalidates the whole ledger at
 * once. The cost is bounded and one-off: every event still queued at that moment
 * may be shown twice. It is not worth a schema version to avoid, but it is worth
 * knowing before someone bumps the dependency and sees duplicate notifications.
 *
 * ## Bounded, where iOS is not
 *
 * `CacheManager.didHandleEvent` appends to a `UserDefaults` array with nothing
 * that ever removes an entry — for the life of the install. This keeps the most
 * recent [limit] and drops the oldest, which is a **deliberate divergence** and
 * the only one in the class.
 *
 * The unbounded version is not a leak that eventually matters; it is a file that
 * is read into memory on the first event of every process and rewritten on every
 * event after it, growing without limit for as long as the wallet is used. What
 * the bound costs is precise and small: an event evicted from the ledger and
 * then *replayed* is shown twice. Replays come from ldk-node's queue, which only
 * holds what has not been acknowledged, so the events at risk are the newest
 * ones — the ones a 500-entry window is certain to still hold.
 *
 * Proved by `CachedEventLedgerTest`.
 */
class CachedEventLedger<E : Any>(
    private val cache: WalletCache,
    /**
     * The event's rendered description — iOS's `"\(event)"`.
     *
     * Injected rather than defaulted to `toString()`: for ldk-node's `Event`
     * that default is *nearly* right, and the case where it is not is invisible.
     * `LdkEventKey.of` is the binding, and its comment is the one to read before
     * replacing this with `{ it.toString() }`.
     */
    private val describe: (E) -> String,
    /**
     * iOS's `event.isPaymentFailed()`.
     *
     * Named for what it does to this class rather than for the event it matches,
     * because the day a second event type needs the same treatment the change
     * should be at the binding and not here.
     */
    private val isExemptFromDeduplication: (E) -> Boolean,
    /** How many descriptions to remember. See the class comment. */
    private val limit: Int = DEFAULT_LIMIT,
    /**
     * Where a failed ledger write goes.
     *
     * Swallowed rather than propagated, and this is the one place in the event
     * path where that call is close. [recordHandled] runs *inside*
     * `EventPump`'s loop and before the handler, so a throw here would be a
     * handler that never runs and an event that is never acknowledged: a full
     * disk would turn into a pump replaying the same event until the node stops.
     * The cost of swallowing is that the event may be shown twice later, which
     * is the direction the whole pump errs in — `EventPump`'s point 2.
     */
    private val onFailure: (Throwable) -> Unit = {},
) : EventLedger<E> {

    override fun hasHandled(event: E): Boolean {
        if (isExemptFromDeduplication(event)) return false
        return describe(event) in cache.strings(KEY)
    }

    override fun recordHandled(event: E) {
        val description = describe(event)
        try {
            cache.update(KEY) { handled ->
                // Returning the list unchanged is how a duplicate avoids a
                // write — and it also keeps the *original* position, so
                // re-seeing an old event does not push a newer one out.
                if (description in handled) handled else (handled + description).takeLast(limit)
            }
        } catch (failure: Exception) {
            onFailure(failure)
        }
    }

    companion object {

        /** `CacheKeys.handledEvents`. */
        const val KEY = "handled_events"

        /**
         * 500 descriptions — roughly 100 kB of ldk-node renderings.
         *
         * Chosen against what the ledger is actually for: the race between this
         * loop and a second reader of the same queue, which is a window of
         * seconds. Anything that keeps a day of events keeps far more than the
         * job needs; anything that keeps a handful could evict inside the window.
         */
        const val DEFAULT_LIMIT = 500
    }
}
