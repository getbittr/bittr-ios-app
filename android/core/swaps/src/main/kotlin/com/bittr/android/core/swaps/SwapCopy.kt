package com.bittr.android.core.swaps

/** The swap copy, verbatim from `Language.swift` (English). */
object SwapCopy {
    const val SWAP_FUNDS_HEADER = "swap funds"
    const val SWAP_FUNDS = "Swap funds"
    const val SWAP_DIRECTION = "I'd like to move my funds from..."
    const val SUBTITLE = "Move satoshis between your bitcoin wallet and your bitcoin lightning connection."
    const val MOVE = "Move"
    const val NEXT = "Next"
    const val DONE = "Done"
    const val ONCHAIN_TO_LIGHTNING = "Onchain to Lightning"
    const val LIGHTNING_TO_ONCHAIN = "Lightning to Onchain"
    const val SATS_AT_A_TIME = "Move up to <amount> sats."
    const val ENTER_AMOUNT_OF_SATOSHIS = "Enter amount of satoshis"
    const val AMOUNT_EXCEEDED = "You can only move up to <amount> satoshis at a time. Please enter an amount within this limit."
    const val FEES_MESSAGE = "The expected fee to move <b><amount> satoshis</b> (<convertedamount>) is <b><feesamount> satoshis</b> (<convertedfees>)."
    const val FEES_MESSAGE_RANGE =
        "The expected fee to move <b><amount> satoshis</b> (<convertedamount>) is between <b><feesamountmin> and <feesamount> satoshis</b> (<convertedfees>)."
    const val ONCHAIN_TO_LIGHTNING_EXPLANATION =
        "\n\nIt may take around <b>10 minutes</b> to complete this swap. You may close the app in the meantime.\n\nIf the swap fails, some of the paid fees may not be refundable."
    const val WISH_TO_PROCEED = "Do you wish to proceed?"
    const val PROCEED = "Proceed"
    const val CANCEL = "Cancel"
    const val OKAY = "Okay"
    const val ERROR = "Error"
    const val OOPS = "Oops!"
    const val SYNCING = "Syncing"
    const val AWAITING_BDK_SYNC = "To send a regular transaction, please wait a moment while we sync your wallet."
    const val CANNOT_PROCEED = "We couldn't proceed to the next step"
    const val SWAP_ERROR_2 = "We encountered some issue while processing your swap. No funds have been swapped. Please try again."
    const val VALIDATION_FAILED = "We could not verify the swap details we received. No funds have been sent. Please try again."
    const val NOTIFICATIONS_REQUIRED = "Notifications Required"
    const val NOTIFICATIONS_REQUIRED_MESSAGE =
        "To process swaps, you need to be online. We'd like to notify you once your transaction is confirmed so that you can finalize the swap in the app. Please allow notification permissions."
    const val COULDNT_CONNECT = "We couldn't connect to bittr. Please try again."
    const val INVOICE_CREATE_FAIL = "We could not create an invoice. Please try again later."
    const val INSUFFICIENT_FUNDS = "Insufficient funds"
    const val ONCHAIN_INSUFFICIENT_FUNDS =
        "You don't have enough onchain funds to send this payment. Your available onchain balance is <b><amount> satoshis</b>."
    const val PAYMENT_FAILED = "Payment failed"
    const val PAYMENT_FAILED_2 =
        "Your Lightning payment didn't go through.<reason>\n\nLightning payments can fail when the receiver is offline or doesn't have the app open, when their wallet doesn't have enough receiving capacity, when there's no affordable route through the network, or when the invoice has expired. Try again later or ask the receiver to open their app."
    const val PAYMENT_FAILED_3 = "Unable to send bitcoin payment. Please sync your wallet and try again."
    const val DIRECTION = "Direction"
    const val AMOUNT = "Amount"
    const val FEES = "Fees"
    const val STATUS = "Status"
    const val CHECKING = "Checking"
    const val DOWNLOAD_DETAILS = "Download details"
    const val POWERED_BY = "Powered by"
    const val BOLTZ_EXPLANATION_TITLE = "Powered by Boltz"
    const val BOLTZ_EXPLANATION =
        "<b>Boltz.exchange</b> is a non-custodial bitcoin bridge. It enables you to swap funds between bitcoin layers, while staying in full control of your money."
    const val LIMIT_LIGHTNING = "why a limit for instant payments?"
    const val LIMIT_LIGHTNING_ANSWER =
        "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning connection (for instant payments).\n\nIf you've received satoshis into your lightning connection, you can use those to pay lightning invoices.\n\nYou cannot make instant payments that exceed the funds in your lightning connection."
    const val SWAP_AND_PAY = "Swap & Pay"
    const val SWAP_INSUFFICIENT_FUNDS =
        "However, you have enough regular bitcoin funds to swap and pay. Your available onchain balance is <b><amount> satoshis</b>."
    const val SWAP_INSUFFICIENT_FUNDS_LIGHTNING =
        "However, you have enough instant bitcoin funds to swap and pay. Your available instant balance is <b><amount> satoshis</b>."
    const val SWAP_QUESTION = "Swap status"

    const val STATUS_PREPARING = "Preparing"
    const val STATUS_AWAITING_CONFIRMATION = "Waiting to be mined"
    const val STATUS_AWAITING_PAYMENT = "Awaiting payment"
    const val STATUS_INVOICE_PENDING = "Awaiting swap payout"
    const val STATUS_COMPLETE = "Swap complete"
    const val STATUS_CLAIMING = "Claiming your bitcoin"
    const val STATUS_FAILED_TO_PAY = "Swap failed (couldn't pay invoice)"
    const val STATUS_EXPIRED = "Swap expired"
    const val STATUS_INCORRECT_AMOUNT = "Swap failed (incorrect amount)"
    const val STATUS_AWAITING_TRANSACTION = "Awaiting transaction"
    const val STATUS_INVOICE_EXPIRED = "Swap failed (invoice expired)"
    const val STATUS_FAILED = "Swap failed"

    const val Q_CREATED_0 = "We've initiated the swap of your funds from onchain to lightning, but no funds have been moved yet."
    const val Q_CREATED_1 = "We've initiated the swap of your funds from lightning to onchain, but no funds have been moved yet."
    private const val Q_STEPS =
        "In order to swap your funds from onchain to lightning, we (1) perform an onchain transaction, then (2) wait for that transaction to be confirmed on the blockchain, and then (3) receive the funds in your lightning connection."
    const val Q_MEMPOOL_0 = "$Q_STEPS\n\nWe're currently waiting for your onchain transaction to be confirmed on the blockchain."
    const val Q_CONFIRMED_0 = "$Q_STEPS\n\nThe onchain transaction has now been confirmed, we're waiting to receive the swapped funds into your lightning connection."
    const val Q_INVOICE_PENDING_0 = Q_CONFIRMED_0
    const val Q_FAILED_TO_PAY_0 =
        "The swap of your funds from onchain to lightning could not be completed.\n\n$Q_STEPS\n\nThe onchain transaction has been paid and confirmed. However, the lightning invoice could not be paid. We're refunding the funds back into your onchain wallet."
    const val Q_COMPLETE_0 = "The swap of your funds from onchain to lightning has been completed."
    const val Q_COMPLETE_1 = "The swap of your funds from lightning to onchain has been completed."
    const val Q_EXPIRED_0 = "The swap of your funds from onchain to lightning was not completed in time. If any funds were sent, they will be refunded into your onchain wallet."
    const val Q_EXPIRED_1 = "The swap of your funds from lightning to onchain was not completed in time. If any funds were sent, they will be refunded into your lightning connection."
    const val Q_GENERIC = "We're checking the current status of your swap."

    /** iOS renders `<b>` in alerts; Android alerts are plain text, so the tags are dropped. */
    fun plain(text: String): String = text.replace("<b>", "").replace("</b>", "")
}

/** Where a Boltz status leaves the swap. */
enum class SwapPhase { InProgress, Complete, Failed }

/** Boltz's status strings, as the app reads them — `userFriendlyStatus`, the "?" answers, the suggested marker. */
object BoltzStatus {

    private val completeStatuses = setOf("invoice.paid", "transaction.claim.pending", "transaction.claimed", "invoice.settled")
    private val failedStatuses = setOf(
        "invoice.failedToPay", "transaction.lockupFailed", "swap.expired", "invoice.expired", "transaction.failed", "transaction.refunded",
    )

    fun phase(status: String): SwapPhase = when (status) {
        in completeStatuses -> SwapPhase.Complete
        in failedStatuses -> SwapPhase.Failed
        else -> SwapPhase.InProgress
    }

    /** `syncSuggestedSwapMarker`: null leaves the marker as it is. */
    fun suggestedMarker(status: String): SuggestedSwapStatus? = when (phase(status)) {
        SwapPhase.Complete -> SuggestedSwapStatus.Succeeded
        SwapPhase.Failed -> SuggestedSwapStatus.Failed
        SwapPhase.InProgress -> null
    }

    /** Boltz failed to pay our invoice or the lockup was wrong: ask for a cooperative refund. */
    fun needsRefund(status: String): Boolean = status == "invoice.failedToPay" || status == "transaction.lockupFailed"

    /** `String.userFriendlyStatus(direction:)`; an unknown status is shown as it came. */
    fun userFriendly(status: String, direction: SwapDirection): String = when (status) {
        "swap.created", "invoice.set" -> SwapCopy.STATUS_PREPARING
        "transaction.mempool" -> SwapCopy.STATUS_AWAITING_CONFIRMATION
        "transaction.confirmed" ->
            if (direction == SwapDirection.OnchainToLightning) SwapCopy.STATUS_AWAITING_PAYMENT else SwapCopy.STATUS_CLAIMING
        "invoice.pending" -> SwapCopy.STATUS_INVOICE_PENDING
        "invoice.paid", "transaction.claim.pending", "transaction.claimed", "invoice.settled" -> SwapCopy.STATUS_COMPLETE
        "invoice.failedToPay" -> SwapCopy.STATUS_FAILED_TO_PAY
        "swap.expired" -> SwapCopy.STATUS_EXPIRED
        "transaction.lockupFailed" -> SwapCopy.STATUS_INCORRECT_AMOUNT
        "invoice.expired" -> SwapCopy.STATUS_INVOICE_EXPIRED
        "transaction.failed", "transaction.refunded" -> SwapCopy.STATUS_FAILED
        else -> status
    }

    /** The status "?" answer — `statusQuestionTapped`. */
    fun answer(status: String?, direction: SwapDirection): String {
        val onchainToLightning = direction == SwapDirection.OnchainToLightning
        return when (status) {
            "swap.created" -> if (onchainToLightning) SwapCopy.Q_CREATED_0 else SwapCopy.Q_CREATED_1
            "invoice.set" -> SwapCopy.Q_CREATED_0
            "transaction.mempool" -> if (onchainToLightning) SwapCopy.Q_MEMPOOL_0 else SwapCopy.Q_COMPLETE_1
            "transaction.confirmed" -> if (onchainToLightning) SwapCopy.Q_CONFIRMED_0 else SwapCopy.Q_COMPLETE_1
            "invoice.pending" -> SwapCopy.Q_INVOICE_PENDING_0
            "invoice.paid", "transaction.claim.pending", "transaction.claimed" -> SwapCopy.Q_COMPLETE_0
            "invoice.failedToPay" -> SwapCopy.Q_FAILED_TO_PAY_0
            "swap.expired", "transaction.lockupFailed" -> if (onchainToLightning) SwapCopy.Q_EXPIRED_0 else SwapCopy.Q_EXPIRED_1
            "invoice.settled" -> SwapCopy.Q_COMPLETE_1
            "invoice.expired", "transaction.failed", "transaction.refunded" -> SwapCopy.Q_EXPIRED_1
            else -> SwapCopy.Q_GENERIC
        }
    }
}
