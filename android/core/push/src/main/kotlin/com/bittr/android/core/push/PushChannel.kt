package com.bittr.android.core.push

/**
 * The route the backend says it actually established for this customer — BIT-9 `api-contract`
 * §2.1, read from the `push_channel` field inside `data` on the `POST /customer` and
 * `PATCH /customer/device-token` responses.
 *
 * The field exists because registration returning 2xx does **not** mean a push route exists.
 * §4.1 settled that deliberately: rejecting the registration with a 4xx would dead-end signup
 * with no customer record and no deposit code, so the backend creates the customer either way
 * and reports the route honestly in the body instead.
 */
enum class PushChannel {
    /** APNS. Never the right answer for an Android registration — see [PushChannelStatus]. */
    APNS,

    /** FCM. The only success value for this client. */
    FCM,

    /** No route was established. [PushChannelReason] says why. */
    NONE,

    ;

    companion object {
        /**
         * Parses the wire value, or null for a value this build predates.
         *
         * Null is not an error condition and must not be collapsed into [NONE]: a channel
         * name we do not recognise is a route the backend *did* establish, and §4.3's
         * invariant keys the `onchain` downgrade on no token having been **sent**. Reading
         * an unknown route as "no route" would downgrade a customer who has one.
         */
        fun parse(raw: String?): PushChannel? = when (raw?.trim()?.lowercase()) {
            "apns" -> APNS
            "fcm" -> FCM
            "none" -> NONE
            else -> null
        }
    }
}

/**
 * Why no route exists — `push_channel_reason`, §4.2. Present only when
 * [PushChannel.NONE]; null on every other channel.
 *
 * The six slugs are not interchangeable and the split is the point of §4.2: they divide into
 * "a token was sent and we have a verdict", "a token was sent and we have no verdict", and
 * "no usable token reached the backend at all", and §4.3's invariant applies only to the
 * third. [PushChannelPolicy] is where that division turns into behaviour.
 */
enum class PushChannelReason {
    /** The token field was absent or empty. §2.1 makes this an ordinary path, not an error. */
    MISSING,

    /** FCM `INVALID_ARGUMENT` — not a token for this Firebase project. */
    INVALID,

    /** FCM `UNREGISTERED` — well-formed but dead: reinstall, data clear, or restore. */
    UNREGISTERED,

    /**
     * FCM 5xx or timeout at the `validate_only` call. **The token may be perfectly good.**
     *
     * Split out from the other slugs in rev 2 and re-pinned in rev 4 precisely so this one
     * cannot be treated as proof of failure — see [PushChannelPolicy].
     */
    UNAVAILABLE,

    /**
     * The other platform's token field was populated and the one `category` names was not.
     *
     * On this client that is a bug in **our** request, not in the customer's device: an
     * Android registration sends `category: "android"` and must populate
     * `android_device_token`. Rev 4 pins §4.2's scope to the fields on the request itself,
     * never the stored row, so an existing iPhone customer installing this build cannot
     * produce it — which is what makes it a usable defect signal rather than noise.
     */
    PLATFORM_MISMATCH,

    /**
     * Written by §5's send-time invalidation, not by registration: a real send returned
     * `UNREGISTERED` or `INVALID_ARGUMENT` and the backend cleared the stored token.
     *
     * Reachable here through §9.2's stored `push_channel_reason` rather than through a
     * registration response, and handled the same way as [UNREGISTERED] because the cause is
     * the same — the token died, and only a fresh one recovers it.
     */
    UNREGISTERED_AT_SEND,

    ;

    companion object {
        /** Parses the wire slug, or null when absent or unrecognised. */
        fun parse(raw: String?): PushChannelReason? = when (raw?.trim()?.lowercase()) {
            "missing" -> MISSING
            "invalid" -> INVALID
            "unregistered" -> UNREGISTERED
            "unavailable" -> UNAVAILABLE
            "platform_mismatch" -> PLATFORM_MISMATCH
            "unregistered_at_send" -> UNREGISTERED_AT_SEND
            else -> null
        }
    }
}

/**
 * The `push_channel` / `push_channel_reason` pair as it arrived, before any decision is taken
 * on it.
 *
 * Keeps the raw strings alongside the parsed values so that a slug this build predates can be
 * logged as itself. That is worth the two fields: §4.2's reason set is the backend's to extend,
 * and a client that reports "unrecognised" without saying what it saw makes the next slug's
 * rollout an unreadable bug report.
 */
data class PushChannelStatus(
    val channel: PushChannel?,
    val reason: PushChannelReason?,
    val rawChannel: String?,
    val rawReason: String?,
) {
    companion object {
        /** Reads the two fields out of a decoded `data` object. */
        fun from(rawChannel: String?, rawReason: String?): PushChannelStatus = PushChannelStatus(
            channel = PushChannel.parse(rawChannel),
            reason = PushChannelReason.parse(rawReason),
            rawChannel = rawChannel,
            rawReason = rawReason,
        )
    }
}
