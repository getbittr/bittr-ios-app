package com.bittr.android.core.lnurl

/**
 * Fetches the invoice for an approved LNURL-pay and pays it.
 *
 * Split out as an interface so [LnurlPayGate] can be tested without a network or
 * a wallet, and so that the one place invoices are fetched from is named. It is
 * the boundary R-8 is about: nothing behind this interface may be called before
 * the user has accepted.
 */
interface LnurlInvoicePayer {

    /**
     * Requests an invoice from [confirmation]'s callback for its amount, then pays
     * it. Called at most once per accepted confirmation.
     */
    suspend fun fetchAndPay(confirmation: LnurlPayConfirmation): Result<Unit>
}

/** Where an LNURL-pay attempt ended up. */
sealed interface LnurlPayOutcome {
    data object Paid : LnurlPayOutcome
    data class Failed(val reason: String) : LnurlPayOutcome
    data object Cancelled : LnurlPayOutcome

    /** Nothing was pending — a stale accept, e.g. a double tap on Confirm. */
    data object NothingPending : LnurlPayOutcome
}

/**
 * Holds an LNURL-pay at the confirmation and releases it only on accept
 * (R-4, R-8).
 *
 * This is deliberately a tiny state machine rather than a callback passed into a
 * dialog. A dialog with the "pay" call in its accept handler is correct on the
 * day it is written and one refactor away from having a second caller that skips
 * it; a gate that owns the pending confirmation cannot be bypassed without
 * deleting it, and [LnurlInvoicePayer] has exactly one implementation site to
 * review.
 *
 * The property the tests assert (§Acceptance 6): between [present] and [accept],
 * `fetchAndPay` is called zero times — including when
 * `minSendable == maxSendable`, which is the case iOS pays without asking.
 *
 * Not thread-safe by design: this is confined to the main thread, like the UI it
 * drives. [LnurlRequestSlot] is what keeps concurrent *requests* to one.
 */
class LnurlPayGate(private val payer: LnurlInvoicePayer) {

    private var pending: LnurlPayConfirmation? = null

    /** The confirmation currently awaiting the user, if any. */
    val awaitingConfirmation: LnurlPayConfirmation?
        get() = pending

    /**
     * Records [confirmation] as awaiting the user. Makes no network call.
     *
     * Replacing an existing pending confirmation is allowed and drops the old one:
     * the alternative is a stuck gate, and the user only ever sees one dialog.
     */
    fun present(confirmation: LnurlPayConfirmation) {
        pending = confirmation
    }

    /**
     * The user accepted. This — and only this — fetches the invoice and pays.
     *
     * Clears `pending` *before* awaiting, so a second accept arriving while the
     * first is in flight finds nothing pending rather than paying twice.
     */
    suspend fun accept(): LnurlPayOutcome {
        val confirmation = pending ?: return LnurlPayOutcome.NothingPending
        pending = null

        return payer.fetchAndPay(confirmation).fold(
            onSuccess = { LnurlPayOutcome.Paid },
            onFailure = { LnurlPayOutcome.Failed(it.message ?: "that payment could not be sent") },
        )
    }

    /** The user dismissed the dialog, or the flow was torn down. Nothing is fetched. */
    fun cancel(): LnurlPayOutcome {
        val had = pending != null
        pending = null
        return if (had) LnurlPayOutcome.Cancelled else LnurlPayOutcome.NothingPending
    }
}
