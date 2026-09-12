package com.bittr.android.core.lnurl

/**
 * An LNURL-pay `payRequest` response, as received from the endpoint.
 *
 * Amounts are millisatoshis, matching the protocol and matching iOS's
 * `minSendable` / `maxSendable`. Converting to satoshis is presentation, done at
 * the edge in [LnurlPayConfirmation].
 */
data class LnurlPayRequest(
    val callbackUrl: String,
    val minSendableMsat: Long,
    val maxSendableMsat: Long,
    /** Raw LUD-06 metadata JSON. Parsed for display only, never trusted. */
    val metadata: String? = null,
)

/**
 * What the user is asked to approve before any invoice is fetched or paid.
 *
 * Every field on here is on the dialog. R-4 requires amount and destination
 * specifically, so neither is nullable.
 */
data class LnurlPayConfirmation(
    val amountSat: Long,
    /** Host of the callback URL — *the* thing the user needs in order to judge this. */
    val destinationHost: String,
    /** The callback origin in full, for a user who wants to read it. */
    val destinationUrl: String,
    /**
     * `text/plain` from the endpoint's metadata, if any. Remote text: display it
     * as untrusted, never as the destination.
     */
    val description: String?,
    /** Carried through so the dialog can say how this arrived. */
    val source: LnurlSource,
)

/** The next step in an LNURL-pay flow. There is no "pay now" case. */
sealed interface LnurlPayStep {

    /**
     * The source may not start a payment at all (R-5). Nothing was fetched and
     * nothing will be.
     */
    data class Blocked(val reason: String) : LnurlPayStep

    /** The endpoint's response was unusable — malformed range, bad callback (R-7). */
    data class Unusable(val reason: String) : LnurlPayStep

    /**
     * The endpoint accepts a range and the user has not picked an amount yet.
     * Amount entry comes first, then [Confirm] — never straight to paying.
     */
    data class NeedsAmount(
        val minSat: Long,
        val maxSat: Long,
        val destinationHost: String,
        val description: String?,
    ) : LnurlPayStep

    /**
     * Ready to ask. **Reaching this step is not authorisation to pay** — the
     * invoice is fetched only once the user accepts, which is [LnurlPayGate]'s
     * job, not this type's.
     */
    data class Confirm(val confirmation: LnurlPayConfirmation) : LnurlPayStep
}

/**
 * Turns a `payRequest` into the next step, and never into a payment (R-4).
 *
 * ### The case this exists for
 *
 * `ios/bittr/Move, Send, Receive/SendVC/SendLNURL.swift:243–247`:
 *
 * ```swift
 * if minSendable == maxSendable {
 *     self.sendPayRequest(callbackURL: …, amount: minSendable, …)
 * }
 * ```
 *
 * When the two are equal iOS goes straight to fetching and paying the invoice.
 * No amount entry, no confirmation, no destination shown — and the endpoint
 * chooses both values, so **any attacker-controlled LNURL takes that branch by
 * setting them equal.** The amount is bounded only by the wallet's balance.
 *
 * So `minSendable == maxSendable` is not the fast path here. It is the case with
 * no amount entry to interrupt it, which makes the confirmation the *only*
 * control on it. BIT-33 §Acceptance 6 is a test that this holds from every
 * source.
 */
object LnurlPay {

    private const val MSAT_PER_SAT = 1_000L

    /**
     * @param enteredAmountSat an amount the user has already chosen, if any. Only
     *   consulted when the endpoint offers a range; an endpoint that fixes the
     *   amount does not get to have the user's earlier typing double as consent
     *   to its number.
     */
    fun next(
        request: LnurlPayRequest,
        source: LnurlSource,
        enteredAmountSat: Long? = null,
    ): LnurlPayStep {
        when (val permission = LnurlSourcePolicy.permit(LnurlAction.Pay, source)) {
            is LnurlPermission.Denied -> return LnurlPayStep.Blocked(permission.reason)
            LnurlPermission.Allowed -> Unit
        }

        // The callback is a URL from a remote server that we are about to request,
        // so it gets the same R-7 treatment as the LNURL itself. iOS strips NULs
        // and control characters from it and asks no further questions.
        val endpoint = when (val check = LnurlEndpoint.validate(request.callbackUrl)) {
            is LnurlEndpointCheck.Rejected -> return LnurlPayStep.Unusable(check.reason)
            is LnurlEndpointCheck.Usable -> check
        }

        if (request.minSendableMsat <= 0 ||
            request.maxSendableMsat < request.minSendableMsat
        ) {
            return LnurlPayStep.Unusable("that payment request offers an impossible amount")
        }

        val description = descriptionFrom(request.metadata)

        if (request.minSendableMsat == request.maxSendableMsat) {
            return LnurlPayStep.Confirm(
                LnurlPayConfirmation(
                    amountSat = request.minSendableMsat / MSAT_PER_SAT,
                    destinationHost = endpoint.host,
                    destinationUrl = endpoint.url,
                    description = description,
                    source = source,
                ),
            )
        }

        val minSat = request.minSendableMsat / MSAT_PER_SAT
        val maxSat = request.maxSendableMsat / MSAT_PER_SAT

        val chosen = enteredAmountSat
            ?: return LnurlPayStep.NeedsAmount(minSat, maxSat, endpoint.host, description)

        if (chosen * MSAT_PER_SAT < request.minSendableMsat ||
            chosen * MSAT_PER_SAT > request.maxSendableMsat
        ) {
            return LnurlPayStep.NeedsAmount(minSat, maxSat, endpoint.host, description)
        }

        return LnurlPayStep.Confirm(
            LnurlPayConfirmation(
                amountSat = chosen,
                destinationHost = endpoint.host,
                destinationUrl = endpoint.url,
                description = description,
                source = source,
            ),
        )
    }

    /**
     * Pulls the `text/plain` entry out of LUD-06 metadata.
     *
     * Hand-rolled rather than a JSON dependency because this module is
     * deliberately dependency-free, and because the value is only ever shown as
     * a label — a parse failure means "no description", never a failed payment.
     * The result is remote text and is truncated: a description is allowed to
     * describe the payment, not to fill the dialog and push the amount off it.
     */
    private fun descriptionFrom(metadata: String?): String? {
        if (metadata.isNullOrBlank()) return null
        val marker = metadata.indexOf("\"text/plain\"")
        if (marker < 0) return null
        val opening = metadata.indexOf('"', metadata.indexOf(',', marker) + 1)
        if (opening < 0) return null

        val text = StringBuilder()
        var i = opening + 1
        while (i < metadata.length) {
            val c = metadata[i]
            when {
                c == '\\' && i + 1 < metadata.length -> {
                    text.append(metadata[i + 1]); i += 2
                }
                c == '"' -> return text.toString()
                    .filterNot { it.isISOControl() }
                    .trim()
                    .take(MAX_DESCRIPTION_LENGTH)
                    .ifEmpty { null }
                else -> {
                    text.append(c); i++
                }
            }
        }
        return null
    }

    private const val MAX_DESCRIPTION_LENGTH = 140
}
