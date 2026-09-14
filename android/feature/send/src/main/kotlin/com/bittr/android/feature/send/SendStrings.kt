package com.bittr.android.feature.send

/**
 * Send's copy, ported verbatim from `ios/bittr/Language.swift` — the dictionary id is the
 * constant's name in lower case unless noted. Same arrangement as `ReceiveStrings`.
 */
internal object SendStrings {

    /** `sendbitcoin`. */
    const val SEND_BITCOIN = "send bitcoin"
    const val YOU_CAN_SEND = "You can send <amount> satoshis."
    const val ADDRESS_AND_AMOUNT = "Address and amount"
    const val INVOICE_AND_AMOUNT = "Invoice and amount"
    const val ENTER_BITCOIN_ADDRESS = "Enter bitcoin address"
    const val ENTER_INVOICE = "Enter lightning address or invoice"
    const val ENTER_AMOUNT = "Enter amount"
    /** `sendvcscan`. */
    const val SCAN = "Scan"
    /** `sendvcpaste`. */
    const val PASTE = "Paste"
    const val REGULAR = "Regular"
    const val INSTANT = "Instant"
    const val NEXT = "Next"
    const val DONE = "Done"
    const val SATS = "sats"
    const val SATS_LABEL = "Sats"
    const val BTC_LABEL = "BTC"
    const val BITCOIN = "Bitcoin"
    const val SATOSHIS = "Satoshis"

    // Confirm.
    const val CHECK_DETAILS = "Make sure these details are correct."
    const val ADDRESS = "Address"
    const val INVOICE = "Invoice"
    const val AMOUNT = "Amount"
    const val ESTIMATED_FEES = "Estimated fees"
    /** `feerate`. */
    const val FEE_RATE = "Select your preferred fee rate."
    /** `10mins`. */
    const val TEN_MINS = "10 mins"
    /** `1hour`. */
    const val ONE_HOUR = "1 hour"
    /** `1day`. */
    const val ONE_DAY = "1 day"
    const val SLOW = "Slow"
    const val SEND = "Send"

    // Alerts.
    const val OKAY = "Okay"
    const val CANCEL = "Cancel"
    const val CONFIRM = "Confirm"
    const val CLOSE = "Close"
    const val CONTINUE = "Continue"
    const val OOPS = "Oops!"
    const val SELECT_CURRENCY = "Currency"
    const val SELECT_CURRENCY_MESSAGE = "Choose your preferred currency."
    const val TRANSACTION_TYPE = "Transaction type"
    const val TRANSACTION_TYPE_3 =
        "<b>Regular</b>\nEnter a bitcoin address, to send regular on-chain transactions.\n\n" +
            "<b>Instant</b>\nEnter an invoice or lightning address, to make instant lightning payments."
    const val MAXIMUM_ONCHAIN =
        "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning connection " +
            "(for instant payments).\n\nThe maximum amount you can send for regular payments, is your full regular " +
            "balance minus the minimum required transaction fees."
    const val LIMIT_LIGHTNING = "why a limit for instant payments?"
    const val LIMIT_LIGHTNING_ANSWER =
        "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning connection " +
            "(for instant payments).\n\nIf you've received satoshis into your lightning connection, you can use those " +
            "to pay lightning invoices.\n\nYou cannot make instant payments that exceed the funds in your lightning connection."
    const val NO_BITCOIN_ADDRESS_FOUND = "No bitcoin address found."
    const val PLEASE_SCAN = "Please scan a bitcoin or lightning address QR code or input the address manually."
    const val SYNCING = "Syncing"
    const val AWAITING_BDK_SYNC = "To send a regular transaction, please wait a moment while we sync your wallet."
    /** `onchainsyncfailedtitle`. */
    const val ONCHAIN_SYNC_FAILED_TITLE = "Syncing issue"
    const val ONCHAIN_SYNC_FAILED = "We ran into an issue syncing the on-chain part of your wallet. Please try again later."
    const val SPENDABLE_BALANCE = "Make sure the amount of BTC you wish to send is within your spendable balance."
    const val CANNOT_PROCEED = "We couldn't proceed to the next step"
    const val AMOUNT_MISSING = "Please enter the amount of satoshis you'd like to send."
    const val BOLT12_NOT_SUPPORTED =
        "This type of lightning payment isn't supported yet. Please use a lightning invoice or address instead."
    const val INVALID_INVOICE_2 = "The following is not a valid invoice.\n\n<invoice>"
    const val INSUFFICIENT_FUNDS = "Insufficient funds"
    const val LIGHTNING_INSUFFICIENT_FUNDS =
        "You don't have enough instant bitcoin funds to send this payment. Your available balance is <b><amount> satoshis</b>."
    /** `balance2`. */
    const val BALANCE_2 = "Balance"
    const val INSUFFICIENT_ONCHAIN_BALANCE = "Your available balance (<fee>) is insufficient to cover this fee."
    const val UPDATE_AMOUNT = "Update amount"
    const val HIGH_FEE_RATE = "High fee rate"
    const val HIGH_FEE_RATE_2 =
        "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended."
    const val LOW_FEE = "Low fee"
    const val LOW_FEE_2 = "The fee you've selected is very low. Your transaction may take long to (or never) be confirmed."
    const val CHANGE_FEE = "Change fee"
    const val ALERT_LIGHTNING_FEES = "Lightning fees"
    const val ALERT_LIGHTNING_FEES_2 =
        "The fees for this instant payment depend on the length of the route between your and the recipient's lightning " +
            "connections - and the fees charged by intermediaries on that route."
    const val SEND_TRANSACTION = "Send transaction"
    const val SEND_CONFIRMATION =
        "Are you sure you want to send <b><amount> satoshis</b>, with a fee of <b><fees> satoshis</b>, to <b><address></b>?"
    const val ERROR = "Error"
    const val TRANSACTION_ERROR = "We're unable to complete your transaction. We're receiving the following error message"
    const val UNEXPECTED_ERROR = "Unexpected error"
    const val FAILED_INVOICE_PAYMENT_1 = "This invoice could not be paid, due to the following error:\n\n<message>"
    const val SUCCESS = "Success"
    const val TRANSACTION_SUCCESS = "Your transaction has been sent and will show up in your wallet shortly."

    // LNURL — `SendLNURL.swift`.
    const val HANDLING_LNURL = "Handling lightning request"
    /** `lnurl`. */
    const val LNURL_STATUS = "LNURL status"
    const val LNURL_FAIL_1 = "We could not complete this withdraw request. Error:"
    const val LNURL_FAIL_2 = "We could not complete your pay request. Error:"
    const val LNURL_FAIL_3 = "We've received an error while handling this request. Please try again."
    const val LNURL_FAIL_4 = "We currently only support lightning pay and withdraw requests."
    const val PAY_REQUEST = "Pay request"
    const val PAY_REQUEST_1 = "Are you sure you'd like to pay <payable> satoshis?"
    const val WITHDRAW_REQUEST = "Withdraw request"
    const val WITHDRAW_REQUEST_1 =
        "You can withdraw between <minwithdrawable> and <maxwithdrawable> satoshis. How many satoshis would you like to withdraw?"
    const val WITHDRAW_REQUEST_3 = "Are you sure you'd like to withdraw <withdrawable> satoshis?"
    const val WITHDRAW_OUT_OF_RANGE = "Please enter an amount within the range shown."
    const val AMOUNT_IN_SATOSHIS = "Amount"
    const val LNURL_BETWEEN = "Amount must be between <min> and <max> satoshis."
    const val INVOICE_CREATE_FAIL = "We could not create an invoice. Please try again later."
    const val LNAUTH_1 =
        "<domain> wants to <action> with your lightning wallet. No bitcoin will be sent. Would you like to proceed?"
    const val LNAUTH_2 = "You've been successfully signed in."
    const val LNAUTH_3 = "We could not sign you in. Please try again."

    /**
     * Not iOS copy: iOS pays whatever invoice the pay callback returns. Android checks it is for
     * the amount the user confirmed, on this network, first.
     */
    const val LNURL_INVOICE_MISMATCH = "The invoice we received doesn't match the requested amount."
}
