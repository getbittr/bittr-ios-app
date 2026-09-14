package com.bittr.android.push

/** iOS `Language.swift` copy the push handlers show, by the iOS key each one ports. */
internal object PushStrings {

    // Loading cards.
    const val SYNCING_WALLET_3 = "syncing wallet"
    const val RECEIVING_PAYMENT = "receiving payment"

    // Titles.
    const val INCOMING_PAYMENT = "Incoming payment"
    const val BITTR_PAYOUT = "Bittr payout"
    const val INSUFFICIENT_FUNDS = "Insufficient funds"
    const val ERROR = "Error"
    const val ONCHAIN_PAYOUT_SCHEDULED = "Payment Scheduled"
    const val OOPS = "Oops!"
    const val HTLC_EXPIRED_TITLE = "Payment expired"

    // Messages.
    const val NEW_BITTR_PAYMENT =
        "You're receiving a new payment! Tap Okay to receive it now and continue what you're doing after."
    const val BITTR_PAYOUT_FAIL = "The notification did not contain the data needed to complete your payout."
    const val BITTR_PAYOUT_FAIL_2 =
        "Something went wrong processing the notification we sent to you.\n\nPlease wait for your wallet " +
            "to sync, and try again. Or go to Settings > Device details, and try again from there."
    const val HTLC_NO_HELD =
        "There's no incoming Lightning payment waiting for you anymore. Lightning payments need the app " +
            "open within a few minutes to go through, so this one likely expired — please ask the sender " +
            "to try again."
    const val BITTR_NOTIFICATION_FAIL =
        "Something went wrong processing the notification we sent to you. Please contact " +
            "support@getbittr.com if you have any questions."
    const val HTLC_EXPIRED_BODY =
        "When someone tries to pay you via Lightning, we send you a notification. You have about 5 " +
            "minutes to open the app so the payment can go through.\n\nWith Lightning, both you and the " +
            "sender need to have the app open. Regular bitcoin payments are different: you can receive " +
            "those even when you're offline."
    const val COULDNT_CONNECT = "We couldn't connect to bittr. Please try again."
    const val CHANNEL_FULL_SWAP_RECOMMENDATION =
        "Bittr recommends you to swap <amount> satoshis. Alternatively you can get this transaction paid " +
            "out to your regular balance. Would you like to receive this payment regularly (within 4-24 " +
            "hours) or swap and receive instantly?"
    const val ONCHAIN_PAYOUT_SCHEDULED_2 =
        "Your payment has been scheduled for on-chain delivery within 4-24 hours. You'll receive a " +
            "notification when it's completed."
    const val ONCHAIN_PAYOUT_FAIL = "Failed to schedule on-chain payment: <message>"
    const val WALLET_NOT_SYNCED = "Wallet has not been synced."

    /** Android-only: the swap screen is not ported, so "Swap & Instant Receive" cannot open it yet. */
    const val SWAP_UNAVAILABLE =
        "Swapping isn't available in the Android app yet. Tap Receive on-chain to get this payment paid " +
            "out to your regular balance instead."

    // Buttons.
    const val OKAY = "Okay"
    const val CLOSE = "Close"
    const val TRY_AGAIN = "Try again"
    const val RECEIVE_ONCHAIN = "Receive on-chain"
    const val SWAP_AND_RECEIVE_INSTANTLY = "Swap & Instant Receive"
}
