package com.bittr.android.feature.home

/**
 * Home's copy, ported verbatim from `ios/bittr/Language.swift`.
 *
 * Same arrangement as `SignupStrings` and `UnlockStrings` — Kotlin constants until
 * the shared string extraction exists, with the iOS dictionary id named on each so
 * the extraction is mechanical rather than a re-translation.
 */
internal object HomeStrings {

    /** `yourwallet`. Lower case in the dictionary, and drawn that way. */
    const val YOUR_WALLET = "your wallet"

    // The action row.
    const val SEND = "Send"
    const val RECEIVE = "Receive"
    const val BUY = "Buy"

    /**
     * `notransactions1` + `buy` + `notransactions2`.
     *
     * iOS assembles this from three dictionary entries so the middle one can be bold
     * — it builds an HTML string and hands it to `NSAttributedString`. Kept as three
     * parts here for the same reason, and because the split is what the extraction
     * has to carry.
     */
    const val NO_TRANSACTIONS_1 = "There are no transactions. Tap "
    const val NO_TRANSACTIONS_2 = " to get your first bitcoin."

    // `syncingwallet` / `syncingwallet2` — the guard iOS puts in front of every
    // action that needs the node. See HomeScreen.
    const val SYNCING_WALLET = "Syncing wallet"
    const val SYNCING_WALLET_2 = "Please wait a moment while we're syncing your wallet."

    const val OKAY = "Okay"

    // The transaction screen — `TransactionVCLanguage.swift`.
    /** `transaction`. */
    const val TRANSACTION = "transaction"
    const val AMOUNT = "Amount"
    const val TYPE = "Type"
    const val REGULAR = "Regular"
    const val INSTANT = "Instant"
    /** `feespaid`. */
    const val FEES_PAID = "Fees paid"
    const val CONFIRMATIONS = "Confirmations"
    const val UNCONFIRMED = "Unconfirmed"
    const val ID = "ID"
    /** `currentvalue`. */
    const val CURRENT_VALUE = "Current value"
    const val COPIED = "Copied"

    // The sync overlay — `SyncingStatus.swift`'s three rows.
    const val FETCH_CONVERSION_RATES = "Fetch conversion rates"
    const val START_LIGHTNING_NODE = "Start lightning node"
    const val FINAL_CALCULATIONS = "Final calculations"
    const val DESCRIPTION = "Description"
    const val NOTE = "Note"
    /** `addanote` — the button, the alert's title and its placeholder. */
    const val ADD_A_NOTE = "Add a note"
    const val SAVE = "Save"
    const val CANCEL = "Cancel"
    /** `channelclosuretransaction`. */
    const val CHANNEL_CLOSURE_TRANSACTION =
        "These are the funds from your closed lightning connection, returning to your regular wallet."

    // The balance screen — `MoveVCLanguage.swift` and `MoveViewController`'s alerts.
    const val BALANCE = "balance"
    /** `walletsubtitle`. */
    const val WALLET_SUBTITLE = "These are the funds in your bittr wallet and lightning connection."
    /** `total`. Lower case in the dictionary. */
    const val TOTAL = "total"
    const val CLOSE = "Close"
    /** `lightningchannel` / `lightningchannels`. */
    const val LIGHTNING_CONNECTIONS = "lightning connections"
    /** `lightningexplanation1`. */
    const val LIGHTNING_EXPLANATION_1 =
        "To send and receive instant bitcoin payments, you need to have at least one lightning connection.\n\n" +
            "To open a connection with bittr, buy bitcoin worth up to 100 CHF/EUR to receive a lightning connection. " +
            "Check your wallet's Buy section or getbittr.com for all information."
    const val INSTANT_PAYMENTS = "Instant payments"
    /** `questionvc13`. */
    const val QUESTION_VC_13 =
        "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning connection " +
            "(for instant payments).\n\nYou don't currently have a lightning connection.\n\nTo open a connection with " +
            "bittr, buy bitcoin worth between 20 and 100 €. Check your wallet's Buy section or getbittr.com for all information."
    const val CONNECTION_CLOSED = "Connection closed"
    const val PENDING_CLOSURE =
        "Your lightning connection was recently closed. These funds (<pendingfunds> satoshis) will be deposited into your regular wallet."
    const val VIEW_ACTIVE_CONNECTION = "View active connection"
    const val SWAP = "Swap"

    // The transaction screen's swap stack: `swapid`, `swapstatus`, `swapsucceeded`, `swappending`,
    // `swapfailed`, `onchainid`, `lightningid`, `refundid`, `expecting`.
    const val SWAP_ID = "Swap ID"
    const val SWAP_STATUS = "Swap status"
    const val SWAP_SUCCEEDED = "Complete"
    const val SWAP_PENDING = "Pending"
    const val SWAP_FAILED = "Failed and refunded"
    const val ONCHAIN_ID = "Onchain ID"
    const val LIGHTNING_ID = "Lightning ID"
    const val REFUND_ID = "Refund ID"
    const val EXPECTING = "Expecting"

    /** The Type row for a swap: `onchaintolightning`, `lightningtoonchain`. */
    const val ONCHAIN_TO_LIGHTNING = "Onchain to Lightning"
    const val LIGHTNING_TO_ONCHAIN = "Lightning to Onchain"

    /** What iOS shows for a swap whose Boltz id is not in the cache. */
    const val UNAVAILABLE = "Unavailable"

    /** Not iOS copy: swaps (`SwapViewController`) are not ported yet. */
    const val SWAP_NOT_ON_ANDROID = "Swapping between regular and instant isn't available on Android yet."
}
