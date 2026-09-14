package com.bittr.android.core.push

/**
 * What the app does about a [PushChannelStatus] — BIT-9 `api-contract` §4.3, and DoD row 8.
 *
 * Two things are being decided at once and they are deliberately separate fields on every
 * case, because conflating them is the bug §4.2 split `unavailable` out to prevent:
 *
 * - [retry] — is re-posting the token the right move, and with which token.
 * - [mayOfferOnchainDowngrade] — may the app show the customer the "continue without
 *   notifications" choice that ends in `PATCH /customer/payment-mode` with `"onchain"`.
 *
 * The second one is the irreversible half. The downgrade is customer-visible and customer-
 * chosen (§4.3: the backend reports, the client decides), but the *offer* is ours, and
 * offering it on a `push_channel: "none"` that only means "our FCM call timed out" hands the
 * customer a permanent `onchain` account on the strength of our own outage.
 */
sealed interface PushChannelAction {

    /** Which token, if any, a retry should carry. */
    val retry: Retry

    /**
     * Whether §4.3's invariant — **no token *sent* ⇒ `onchain`** — is satisfied, i.e. whether
     * this outcome proves no usable token reached the backend.
     *
     * False everywhere a token *was* sent, including every case where the verdict is unknown.
     * Rev 4 rewrote the invariant around the word *sent* for exactly this reason.
     */
    val mayOfferOnchainDowngrade: Boolean

    enum class Retry {
        /** Do not re-post. Either there is nothing wrong, or re-posting cannot help. */
        NONE,

        /** Re-post the same token — the backend never reached a verdict on it. */
        SAME_TOKEN,

        /**
         * Delete the FCM registration, obtain a new token, and post that.
         *
         * Distinct from [SAME_TOKEN] because it has to be: the backend has a verdict and the
         * verdict is that this token is dead. Re-posting it is guaranteed to fail, and doing
         * so on the §2.3 budget burns the attempts that the working recovery needed.
         */
        FRESH_TOKEN,
    }

    /**
     * A live route. [channel] is [PushChannel.FCM]; instant mode stands and nothing is shown.
     */
    data class Registered(val channel: PushChannel) : PushChannelAction {
        override val retry = Retry.NONE
        override val mayOfferOnchainDowngrade = false
    }

    /**
     * The backend established an **APNS** route for a registration this client sent as
     * `category: "android"`.
     *
     * Not a customer-facing state and not recoverable by retrying — it is a §5 dispatch bug,
     * and its symptom is that every push silently goes to a device the customer does not have.
     * It gets its own case so that it cannot be mistaken for [Registered] by a caller checking
     * only "is the channel `none`". No downgrade: a token was sent and was accepted.
     */
    data object RoutedToOtherPlatform : PushChannelAction {
        override val retry = Retry.NONE
        override val mayOfferOnchainDowngrade = false
    }

    /**
     * `unavailable` — FCM 5xx or timeout at the `validate_only` call (§4.2).
     *
     * The one `"none"` outcome where the token may be perfectly good. §2.3 rule 2 exists for
     * this path and §4.3's "sent" wording keeps it inside the invariant: retry within budget,
     * and **never** offer the downgrade on it.
     */
    data object Unavailable : PushChannelAction {
        override val retry = Retry.SAME_TOKEN
        override val mayOfferOnchainDowngrade = false
    }

    /**
     * `invalid`, `unregistered` or `unregistered_at_send` — the backend has a verdict and the
     * token is dead.
     *
     * A fresh FCM token is the recovery, so the downgrade is not offered *yet*; it becomes
     * available once [DeviceTokenRetryBudget] is spent, which is the caller's call and not a
     * property of this response.
     */
    data class TokenRejected(val reason: PushChannelReason) : PushChannelAction {
        override val retry = Retry.FRESH_TOKEN
        override val mayOfferOnchainDowngrade = false
    }

    /**
     * `missing` or `platform_mismatch` — no usable token reached the backend.
     *
     * This is the case §4.3's invariant names, and the only one where the downgrade may be
     * offered straight away. Both slugs mean the same thing to the customer and different
     * things to us: [PushChannelReason.MISSING] is the ordinary async-token race §2.1 blesses,
     * while [PushChannelReason.PLATFORM_MISMATCH] is a defect in our own request and should be
     * logged as one.
     */
    data class NoTokenSent(val reason: PushChannelReason) : PushChannelAction {
        override val retry = Retry.FRESH_TOKEN
        override val mayOfferOnchainDowngrade = true
    }

    /**
     * `push_channel: "none"` with a reason slug this build does not know, or with no reason at
     * all.
     *
     * Forward compatibility, and it fails safe in the direction §4.3 cares about: we cannot
     * prove a token was not sent, so the downgrade is not offered. A same-token retry is
     * allowed because it is harmless — the worst case is one wasted call against a budget that
     * exists to bound exactly that.
     */
    data class UnrecognisedReason(val rawReason: String?) : PushChannelAction {
        override val retry = Retry.SAME_TOKEN
        override val mayOfferOnchainDowngrade = false
    }

    /**
     * A `push_channel` value this build predates.
     *
     * A route exists and we cannot act on it. Explicitly not a downgrade trigger: see
     * [PushChannel.parse].
     */
    data class UnrecognisedChannel(val rawChannel: String?) : PushChannelAction {
        override val retry = Retry.NONE
        override val mayOfferOnchainDowngrade = false
    }
}

/**
 * Maps a [PushChannelStatus] onto the one thing the app should do about it.
 *
 * Pure, total and Android-free so that §4.3 — the section that decides whether a customer
 * keeps instant payouts — is provable as a table on the JVM rather than by registering a real
 * device against a backend that does not exist yet.
 */
object PushChannelPolicy {

    /**
     * @param status the pair read from the registration or token-refresh response.
     * @return what to do. Never throws; every unrecognised value has a case.
     */
    fun decide(status: PushChannelStatus): PushChannelAction = when (status.channel) {
        PushChannel.FCM -> PushChannelAction.Registered(PushChannel.FCM)

        PushChannel.APNS -> PushChannelAction.RoutedToOtherPlatform

        PushChannel.NONE -> when (status.reason) {
            PushChannelReason.UNAVAILABLE ->
                PushChannelAction.Unavailable

            PushChannelReason.INVALID,
            PushChannelReason.UNREGISTERED,
            PushChannelReason.UNREGISTERED_AT_SEND,
            ->
                PushChannelAction.TokenRejected(status.reason)

            PushChannelReason.MISSING,
            PushChannelReason.PLATFORM_MISMATCH,
            ->
                PushChannelAction.NoTokenSent(status.reason)

            // Includes a `"none"` carrying no reason at all, which the contract says cannot
            // happen. It is handled rather than asserted because the alternative is throwing
            // inside the signup response path over a field the customer cannot influence.
            null -> PushChannelAction.UnrecognisedReason(status.rawReason)
        }

        null -> PushChannelAction.UnrecognisedChannel(status.rawChannel)
    }

    /**
     * Whether `tokenregistrationfail` (`Language.swift:235`) should be shown.
     *
     * True for every non-live route, including the ones that do not permit a downgrade — the
     * customer is told either way, and the difference is what they are offered next. §4.3's
     * note is that Android has to wire this copy at **two** points: FCM registration failing
     * on the device, which mirrors iOS, and this one, which is new and has no iOS equivalent
     * because the shipping build cannot be recompiled to read the field.
     */
    fun showsRegistrationFailureCopy(action: PushChannelAction): Boolean =
        action !is PushChannelAction.Registered
}
