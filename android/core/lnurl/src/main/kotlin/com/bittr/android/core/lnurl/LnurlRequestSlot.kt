package com.bittr.android.core.lnurl

import java.util.concurrent.atomic.AtomicReference

/**
 * One in-flight LNURL request at a time, cancellable (R-10).
 *
 * ### What goes wrong without it
 *
 * On iOS the guard against concurrent LNURL handling is a bare
 * `isHandlingLnurlAuth` boolean on `WebsiteViewController` which is set on the
 * way in and never cleared, so the second LNURL a page offers is dropped for the
 * lifetime of the screen — including after the first one failed. The other half
 * is worse: nothing cancels an in-flight request when the screen goes away, so a
 * response can arrive to a dismissed controller.
 *
 * A generation counter fixes both. [begin] supersedes whatever was in flight,
 * [cancel] supersedes everything, and a completing request checks
 * [Ticket.isCurrent] before it is allowed to touch the UI or the wallet. A
 * superseded request cannot deliver a result, so a stale response can neither
 * open a dialog nor pay an invoice.
 *
 * Thread-safe, because responses land on whatever thread the HTTP client used.
 */
class LnurlRequestSlot {

    private val current = AtomicReference<Ticket?>(null)

    /** The in-flight request, if any. */
    val inFlight: Ticket?
        get() = current.get()

    /**
     * A claim on the slot.
     *
     * Compared by identity on purpose — two tickets are the same ticket only if
     * they are the same object, so [isCurrent] cannot be satisfied by an equal-
     * looking one.
     */
    inner class Ticket internal constructor(val describedAs: String) {

        /**
         * Whether this ticket still owns the slot. **Check this before delivering
         * any result.** False means the request was superseded or the screen was
         * dismissed, and the correct response is to drop the result silently.
         */
        val isCurrent: Boolean
            get() = current.get() === this

        /** Releases the slot, if this ticket still holds it. */
        fun finish() {
            current.compareAndSet(this, null)
        }
    }

    /**
     * Claims the slot, superseding any in-flight request.
     *
     * @param describedAs short description for logs — the host being contacted, or
     *   the action. Never the LNURL itself: for withdraw and auth that string is a
     *   bearer credential.
     */
    fun begin(describedAs: String): Ticket {
        val ticket = Ticket(describedAs)
        current.set(ticket)
        return ticket
    }

    /**
     * Cancels whatever is in flight. Call on navigation and on dismissal — both,
     * not either: a navigation leaves the screen alive, and a dismissal can happen
     * without one.
     *
     * @return true if something was actually in flight.
     */
    fun cancel(): Boolean = current.getAndSet(null) != null
}
