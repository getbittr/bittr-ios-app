package com.bittr.android.core.push

/**
 * The retry ceiling for `PATCH /customer/device-token` — BIT-9 `api-contract` §2.3 rule 2:
 * **≤3 attempts in one app session, then ≤1 per app foreground.**
 *
 * ## Why this is a type and not a loop counter
 *
 * The thing being bounded is the recovery path for
 * [PushChannelAction.Unavailable][PushChannelAction.Unavailable] and
 * [PushChannelAction.TokenRejected][PushChannelAction.TokenRejected], and §4.3 makes that
 * retry the only thing standing between the customer and an `onchain` downgrade they did not
 * ask for. Two failure directions, not one:
 *
 * - Retry too little and an `unavailable` verdict — which may be a perfectly good token behind
 *   an FCM outage — becomes a permanent downgrade.
 * - Retry too much and we trip the backend's own rate limiter, which §2.3 rule 2 requires to
 *   sit *above* this ceiling. If it did not, our outage would become the customer's permanent
 *   downgrade by way of our own abuse protection.
 *
 * Both directions are silent, so the budget is written once, here, with the shape stated in
 * the contract rather than re-derived at each call site.
 *
 * ## Not persisted, deliberately
 *
 * "Session" is process lifetime. A fresh process gets a fresh three, which is correct: the two
 * situations a restart most often follows — a reinstall, a restore — are exactly the ones that
 * mint a new FCM token, and refusing to register it because a previous process spent its
 * budget would strand the customer with no route and no way back.
 */
class DeviceTokenRetryBudget(
    /** §2.3 rule 2's "≤3 attempts in one app session". */
    private val sessionAllowance: Int = SESSION_ALLOWANCE,
) {

    private val lock = Any()

    private var sessionAttempts = 0
    private var attemptsThisForeground = 0

    /** Attempts made since process start. */
    val attemptsInSession: Int
        get() = synchronized(lock) { sessionAttempts }

    /**
     * Call when the app comes to the foreground — `ON_START` on the process lifecycle owner.
     *
     * Resets only the per-foreground counter. The session total is never reset; once it is
     * spent, every subsequent foreground grants exactly one attempt, which is the "then ≤1 per
     * app foreground" half of the rule.
     */
    fun onAppForegrounded() {
        synchronized(lock) { attemptsThisForeground = 0 }
    }

    /**
     * Takes one attempt if the budget allows it.
     *
     * @return true if the caller may post the token now. False means stop — not "wait and try
     *   again", since nothing changes until the next foreground.
     *
     * Synchronised because the callers are not on one thread: `onNewToken` arrives on FCM's
     * own executor while the app-start reconciliation runs on whatever scope the registration
     * code uses, and the two can race at exactly the moment a rotation is detected at launch.
     */
    fun tryConsume(): Boolean = synchronized(lock) {
        val allowed = sessionAttempts < sessionAllowance || attemptsThisForeground == 0
        if (allowed) {
            sessionAttempts++
            attemptsThisForeground++
        }
        allowed
    }

    /**
     * Whether the session allowance is gone, i.e. the client is now on one attempt per
     * foreground.
     *
     * This is the point at which offering the customer the §4.3 `onchain` downgrade becomes
     * reasonable for a [PushChannelAction.TokenRejected][PushChannelAction.TokenRejected] — the
     * automatic recovery has had its run. It stays unreasonable for
     * [PushChannelAction.Unavailable][PushChannelAction.Unavailable] at any budget, because no
     * number of failed attempts against our own outage turns into evidence about the token.
     */
    fun isSessionAllowanceSpent(): Boolean = synchronized(lock) { sessionAttempts >= sessionAllowance }

    companion object {
        const val SESSION_ALLOWANCE: Int = 3
    }
}
