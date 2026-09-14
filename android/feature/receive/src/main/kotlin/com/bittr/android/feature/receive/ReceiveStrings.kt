package com.bittr.android.feature.receive

/**
 * Receive's copy, ported verbatim from `ios/bittr/Language.swift`.
 *
 * Same arrangement as `HomeStrings` and `SignupStrings` — Kotlin constants until the
 * shared string extraction exists, with the iOS dictionary id named on each. The three
 * card labels ("Renew", "Add amount", "More") are read off the iOS capture
 * `receive_onchain/02_onchain_address.png`.
 */
internal object ReceiveStrings {

    /** `receivebitcoin`. */
    const val RECEIVE_BITCOIN = "receive bitcoin"

    /** `address` — also the title for the Lightning address type, whose `url` word is the same. */
    const val ADDRESS = "Address"

    /** `invoice`. */
    const val INVOICE = "Invoice"

    /** `bitcoinqr`. */
    const val BITCOIN_QR = "Bitcoin QR"

    /** `unavailable`. */
    const val UNAVAILABLE = "Unavailable"

    // Cards.
    const val COPY = "Copy"
    const val RENEW = "Renew"
    const val ADD_AMOUNT = "Add amount"
    const val MORE = "More"

    // The question-mark alerts.
    /** `alertlnurl`. */
    const val LIGHTNING_ADDRESS = "Lightning address"

    /** `alertmessageonchain`. */
    const val ALERT_MESSAGE_ONCHAIN =
        "Share an address, to receive transactions into your wallet.\n\n" +
            "Tap Refresh to reveal additional addresses to your wallet.\n\n" +
            "The best practice is to do so only once the previous address has been used."

    /** `alertmessagelightning`. */
    const val ALERT_MESSAGE_LIGHTNING =
        "Create a lightning invoice, to receive instant payments into your lightning connection.\n\n" +
            "Optionally, you can add an amount and description to your invoice."

    /** `alertmessagebitcoinqr`. */
    const val ALERT_MESSAGE_BITCOIN_QR =
        "Share a bitcoin QR, a universal standard for sharing a regular address and lightning " +
            "invoice simultaneously.\n\n" +
            "Optionally, you can add an amount and description to your bitcoin QR."

    /** `alertmessagelnurl`. */
    const val ALERT_MESSAGE_LNURL =
        "Share your lightning address, to receive instant payments into your lightning connection.\n\n" +
            "This address has been created for you as part of your sign-up with bittr.\n\n" +
            "You can receive emails to your lightning address. These will be forwarded to your own " +
            "email address associated with your bittr account."

    // The type picker: `transactiontype` / `selecttransactiontype`, then
    // `getaddress`, `getbitcoinqr`, `createinvoice`, `showlnurl`.
    const val TRANSACTION_TYPE = "Transaction type"
    const val SELECT_TRANSACTION_TYPE = "Share a lightning address or invoice, a bitcoin QR or address."
    const val GET_ADDRESS = "Address"
    const val GET_BITCOIN_QR = "Bitcoin QR"
    const val CREATE_INVOICE = "Invoice"
    const val SHOW_LNURL = "Lightning address"

    // Renew: `newaddress` / `newaddress2`, and `noaddressavailable`.
    const val NEW_ADDRESS = "new address"
    const val NEW_ADDRESS_2 =
        "Are you sure you wish to reveal a new address?\n\n" +
            "The best practice is to only reveal a new address once the previous one has been used."
    const val NO_ADDRESS_AVAILABLE =
        "No new address is available at this time.\n\n" +
            "For proper performance, we reveal a maximum of ten unused addresses.\n\n" +
            "Make sure to use an address before revealing a new one."

    // Currency: `selectcurrency` / `selectcurrencymessage`. "Satoshis" and "Bitcoin" are
    // literals in `btcButtonTapped`, not dictionary words.
    const val SELECT_CURRENCY = "Currency"
    const val SELECT_CURRENCY_MESSAGE = "Choose your preferred currency."
    const val SATOSHIS = "Satoshis"
    const val BITCOIN = "Bitcoin"
    const val SATS_LABEL = "Sats"
    const val BTC_LABEL = "BTC"

    /** `amount`, as the amount field's placeholder. */
    const val AMOUNT = "Amount"

    /** `description`, as the description field's placeholder. */
    const val DESCRIPTION = "Description"

    /** The keyboard toolbar's button on iOS (`addDoneButton`); a visible button here. */
    const val DONE = "Done"

    /** `copied`. */
    const val COPIED = "Copied"

    // The QR's long-press menu. Literals on iOS too (`contextMenuInteraction`).
    const val MENU_COPY = "Copy"
    const val MENU_SHARE = "Share"

    const val OKAY = "Okay"
    const val CANCEL = "Cancel"
    const val CONFIRM = "Confirm"
}
