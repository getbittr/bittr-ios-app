package com.bittr.android.core.network

/**
 * Why a bittr API call did not produce a usable answer, and — the part that matters —
 * **what the client should do next about it.**
 *
 * ## Why this is a type rather than a status code at the call site
 *
 * `api-contract` §2.3 rules 3 and 4 are the only two rules in the document written as
 * requirements on the *backend's* error reporting, and both are there because the client's
 * correct behaviour is opposite either side of the distinction:
 *
 * - **Clock skew vs. bad signature.** Skew is retryable once the device clock is right; a bad
 *   signature never is. Rule 3 asks for distinct statuses for exactly that reason.
 * - **`no_such_customer` vs. bad signature.** A signed token refresh for a pubkey with no
 *   customer row is the ordinary race where token registration beats signup, and the right
 *   move is to retry after signup completes. Rule 4: *"collapsing both into 401 makes those two
 *   opposite behaviours indistinguishable, and the client will pick the wrong one."*
 *
 * Both of those are about a customer's payout route, so getting them wrong is not a log-line
 * bug — §4.3 makes the retry path the thing standing between the customer and a permanent
 * `onchain` downgrade.
 *
 * ## The wire values are not pinned, and this type is built for that
 *
 * The contract requires the backend to make these four cases *distinguishable*; it does not
 * name the status codes or the slugs, and it cannot — §8 q6 records that the backend repo is
 * not reachable from any workspace here, so there is nothing to read them off. Rather than
 * guess a table and hard-code it, the classifier is asymmetric:
 *
 * - **[Stop] is only ever reached from an explicitly recognised signal.** It is the one verdict
 *   that gives up on a customer's push route permanently, so it is never the default and never
 *   inferred from a bare status code.
 * - **Everything unrecognised falls to [Unclassified], which retries inside the §2.3 rule 2
 *   budget.** That budget — ≤3 per session, then ≤1 per foreground — is precisely the mechanism
 *   for bounding "we do not know", so an unknown rejection costs at most one call per app
 *   foreground and self-heals the day the backend starts answering.
 *
 * The practical consequence is worth stating plainly, because it is the state the client is in
 * today: `PATCH /customer/device-token` does not exist yet, so every call 404s. That lands in
 * [Unclassified] and costs one attempt per foreground until the endpoint ships, at which point
 * the same code starts succeeding with no release. The alternative reading — a bare 404 means
 * "no such customer, stop" — would have this client give up on the endpoint before it existed.
 *
 * BIT-142 is where this meets a real server and the recognised sets below get confirmed or
 * corrected against it.
 */
sealed interface ApiFailure {

    /** What the caller should do next. Never null — every failure has an answer. */
    val recovery: Recovery

    /** A short, loggable description. Never contains the device token or the signature. */
    val detail: String

    /**
     * The four behaviours §2.3 rules 2-4 distinguish between, named for *when* to try again
     * rather than for what went wrong.
     *
     * The naming is deliberate: a call site that switches on the failure's cause has to
     * re-derive the behaviour each time and will eventually derive a different one. A call site
     * that switches on this does not.
     */
    enum class Recovery {
        /**
         * Try again now, spending one unit of [com.bittr.android.core.push.DeviceTokenRetryBudget].
         *
         * The transport failed, or the rejection is one this build does not recognise. Either
         * way we have learned nothing about the token, so §4.3's invariant is untouched and the
         * `onchain` downgrade must not be offered.
         */
        RETRY_IN_BUDGET,

        /**
         * Try again once `POST /customer` has created the customer row.
         *
         * §2.3 rule 4's race: the FCM token arrived before signup finished. Retrying *now*
         * cannot work and would spend the budget that the real recovery needs.
         */
        RETRY_AFTER_REGISTRATION,

        /**
         * Try again on a later app foreground, without spending session budget now.
         *
         * Two causes, one behaviour. A rate-limit rejection (§2.3 rule 2 requires the limit to
         * sit above our ceiling, so hitting one means something is wrong on their side or ours)
         * and a timestamp outside §2.3 rule 3's ±300s window. The device clock is not ours to
         * set — Android has no API for it outside a device-owner app — so "sync the clock and
         * retry" is really "wait for the platform to correct it and retry later". Spinning on
         * either inside one session converts a transient fault into a spent budget.
         */
        RETRY_LATER,

        /**
         * Stop. Retrying cannot succeed, and continuing to try burns the budget that a real
         * recovery would need.
         *
         * Reached only from a recognised bad-signature signal. Not a downgrade trigger by
         * itself: a signature this client cannot get right is a defect in this client, not
         * evidence about the customer's token, and §4.3 keys the downgrade on no token having
         * been *sent*.
         */
        STOP,
    }

    /**
     * No response at all — DNS, connection refused, TLS, timeout. [HttpTransportException].
     *
     * Distinct from every status-code case for the same reason §4.2 splits `unavailable` out:
     * "we could not reach them" is not a verdict on the token.
     */
    data class Unreachable(override val detail: String) : ApiFailure {
        override val recovery = Recovery.RETRY_IN_BUDGET
    }

    /** §2.3 rule 2 — a rate-limit rejection. */
    data class RateLimited(override val detail: String) : ApiFailure {
        override val recovery = Recovery.RETRY_LATER
    }

    /** §2.3 rule 3 — the timestamp fell outside the ±300s skew window. */
    data class ClockSkew(override val detail: String) : ApiFailure {
        override val recovery = Recovery.RETRY_LATER
    }

    /** §2.3 rule 4 — signed for a pubkey that has no customer row yet. */
    data class NoSuchCustomer(override val detail: String) : ApiFailure {
        override val recovery = Recovery.RETRY_AFTER_REGISTRATION
    }

    /** §2.3 rule 3/4 — the signature did not verify. The only route to [Recovery.STOP]. */
    data class BadSignature(override val detail: String) : ApiFailure {
        override val recovery = Recovery.STOP
    }

    /**
     * A non-2xx this build cannot place, including a bare status code with no slug.
     *
     * [code] and [slug] are carried verbatim so that the first real backend response can be
     * read off a bug report rather than reproduced — which is the whole difficulty with a
     * contract whose error vocabulary is not pinned.
     */
    data class Unclassified(
        val code: Int,
        val slug: String?,
        override val detail: String,
    ) : ApiFailure {
        override val recovery = Recovery.RETRY_IN_BUDGET
    }

    /**
     * A 2xx whose body could not be read as the shape the endpoint promises.
     *
     * Retried in budget rather than stopped: the overwhelmingly likely cause is a proxy or a
     * captive portal returning an HTML page with a 200, which is transient and is not the
     * backend's answer at all.
     */
    data class Malformed(override val detail: String) : ApiFailure {
        override val recovery = Recovery.RETRY_IN_BUDGET
    }

    companion object {

        /**
         * Slugs read as "the signature did not verify".
         *
         * The only set that can produce [Recovery.STOP], so it is the only one where a wrong
         * guess is expensive — a false positive strands a customer with no push route for the
         * life of the install. Kept to the three spellings that unambiguously mean this and
         * nothing else; anything adjacent (`unauthorized`, `forbidden`, `invalid_request`)
         * is deliberately absent, because those are also what a misconfigured gateway says.
         */
        internal val BAD_SIGNATURE_SLUGS = setOf(
            "bad_signature",
            "invalid_signature",
            "signature_invalid",
        )

        /** Slugs read as §2.3 rule 3's skew rejection. */
        internal val CLOCK_SKEW_SLUGS = setOf(
            "timestamp_skew",
            "clock_skew",
            "stale_timestamp",
            "expired_timestamp",
            "timestamp_out_of_range",
        )

        /** Slugs read as §2.3 rule 4's "signed request, no customer row". */
        internal val NO_SUCH_CUSTOMER_SLUGS = setOf(
            "no_such_customer",
            "customer_not_found",
            "unknown_customer",
        )

        /**
         * Places a non-2xx response.
         *
         * @param response what came back.
         * @param slug the machine-readable error slug parsed out of the body, or null when the
         *   body carried none. [BittrEnvelope.errorSlug] is what produces it.
         */
        fun classify(response: HttpResponse, slug: String?): ApiFailure {
            val normalised = slug?.trim()?.lowercase()
            val where = "HTTP ${response.code}${normalised?.let { " $it" } ?: ""}"
            return when {
                normalised in BAD_SIGNATURE_SLUGS -> BadSignature(where)
                normalised in CLOCK_SKEW_SLUGS -> ClockSkew(where)
                normalised in NO_SUCH_CUSTOMER_SLUGS -> NoSuchCustomer(where)

                // 429 is the one status code read without a slug, because it has exactly one
                // meaning across every HTTP implementation there is and §2.3 rule 2 names the
                // behaviour directly. Every other code is ambiguous enough to be worth carrying
                // to [Unclassified] rather than guessing at.
                response.code == 429 -> RateLimited(where)

                else -> Unclassified(response.code, normalised, where)
            }
        }
    }
}
