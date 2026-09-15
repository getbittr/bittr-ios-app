package com.bittr.android.push

import javax.inject.Inject
import javax.inject.Singleton

/**
 * The bittr payout whose Lightning payment is on its way — iOS's `lightningNotification`, which
 * `.paymentReceived` checks to tell a bittr payout (`checkPaymentWithBittr`, then the confetti
 * summary) from any other incoming payment.
 *
 * Set just before `POST /payout/lightning`, because bittr can pay the invoice before its answer
 * arrives; cleared when the call fails or once the payment has been checked with bittr. It expires
 * after [WINDOW_MILLIS], so a payout that never paid doesn't turn a later payment into a payout.
 */
@Singleton
class BittrPayoutTracker @Inject constructor() {

    private data class Expected(val notificationId: String, val sinceMillis: Long)

    @Volatile
    private var expected: Expected? = null

    fun expect(notificationId: String, nowMillis: Long) {
        expected = Expected(notificationId, nowMillis)
    }

    /** The payout's notification id, if one is expected and not stale. */
    fun awaiting(nowMillis: Long): String? =
        expected?.takeIf { nowMillis - it.sinceMillis <= WINDOW_MILLIS }?.notificationId

    fun clear() {
        expected = null
    }

    companion object {
        const val WINDOW_MILLIS = 10 * 60_000L
    }
}
