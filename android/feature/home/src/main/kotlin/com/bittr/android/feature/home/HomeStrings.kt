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
}
