package com.bittr.android.feature.buy

/** English copy for Buy, the bittr signup and Profits, verbatim from iOS `Language.swift`. */
object BuyStrings {

    const val OKAY = "Okay"

    // `checkyourconnection` / `trytoconnect`.
    const val CHECK_YOUR_CONNECTION = "Check your connection"
    const val TRY_TO_CONNECT = "You don't seem to be connected to the internet. Please try to connect."
    const val CANCEL = "Cancel"
    const val CONTINUE = "Continue"

    /** The empty Buy screen's button — `Main.storyboard`'s "Check options". */
    const val CHECK_OPTIONS = "Check options"
    const val CONFIRM = "Confirm"
    const val DONE = "Done"
    const val OOPS = "Oops!"
    const val TRY_AGAIN = "Try again"
    const val COPIED = "Copied"

    // Buy.
    const val BUY_BITCOIN = "buy bitcoin"
    const val BUY_SUBTITLE =
        "To buy bitcoin, make a bank transfer to a partner and put your unique code in the transfer description field."
    const val BUY_EMPTY = "No order has been set up. Tap below to create your first one."
    const val YOUR_EMAIL = "Your email"
    const val YOUR_IBAN = "Your IBAN"
    const val OUR_IBAN = "Partner IBAN"
    const val OUR_NAME = "Partner"
    const val YOUR_CODE = "Your code"
    const val LIGHTNING = "Lightning"
    const val LIGHTNING_EXPLANATION =
        "Purchases up to 100 EUR/CHF go into your Lightning connection. Spend and receive instantly, with very low fees.\n\n" +
            "Turn this off to receive your bittr purchases on-chain instead, in the regular part of your wallet."
    const val UPDATE_DETAILS = "Update details"
    const val UPDATE_DETAILS_2 = "Your partner details have changed. The above details have been updated."
    const val LIGHTNING_NOT_READY = "Lightning not ready"
    const val SYNCING_WALLET_2 = "Please wait a moment while we're syncing your wallet."
    const val PAYMENT_MODE_UPDATE_ERROR = "Couldn't update payout mode"
    const val LIGHTNING_NEEDS_NOTIFICATIONS =
        "Lightning payouts are delivered via push notifications, so you must allow notifications to switch to lightning.\n\n" +
            "On your device, go to Settings > Notifications > bittr to authorize our notifications, then try again."

    // Signup7, from Buy.
    const val FIRST_BITCOIN = "Get your first bitcoin, hassle-free, here with one of our partners."
    const val NEXT = "Next"

    // Transfer1.
    const val BITTR_INSTRUCTIONS_4 = "Buy bitcoin whenever you want, simply by making a bank transfer."
    const val WHATS_YOUR_IBAN = "What's your IBAN (International Bank Account Number)?"
    const val WHATS_YOUR_EMAIL = "What's your email address?"
    const val ENTER_IBAN = "Enter IBAN"
    const val ENTER_EMAIL = "Enter email"
    const val VERIFY = "Verify"
    const val NO_IBAN = "I don't have an IBAN"
    const val TRANSFER_1_VC = "Please enter your IBAN and email in order to proceed."
    const val BITTR_SIGNUP_FAIL_4 = "Something went wrong verifying your email address. Please try again."
    const val INITIATIVE_TITLE = "Your own exclusive initiative"
    const val INITIATIVE_MESSAGE =
        "Bittr AG operates in compliance with Swiss regulations. The products and services offered by Bittr AG are " +
            "authorized for promotion and sale within Switzerland. Without express authorization from the regulatory " +
            "authority of a given country, Bittr AG is not permitted to actively promote its products and services in " +
            "that territory.\n\nIf you are located in the European Union, Bittr AG will not be authorized to provide " +
            "services to you unless you request the service on your exclusive initiative.\n\nBefore we can provide any " +
            "Services to you, we'll need you to confirm that your request is made solely on your own exclusive " +
            "initiative, without any encouragement or solicitation from us."
    const val INITIATIVE_CONFIRM =
        "I confirm my request is made solely on my own exclusive initiative, without any encouragement or solicitation from Bittr"
    const val WERE_SORRY = "We're sorry!"
    const val ONLY_IBAN =
        "Buying bitcoin with bittr is only available to IBAN holders.\n\nYou can still use your wallet to send and receive bitcoin."
    const val GO_TO_WALLET = "Go to wallet"

    // Transfer2.
    const val YOUVE_GOT_MAIL = "You've got mail! Please enter your verification code below."
    const val ENTER_CODE = "Enter code"
    const val RESEND_CODE = "Resend code"
    const val TRANSFER_15_VC = "Please enter the verification code in order to proceed."
    const val RECEIVE_NOTIFICATIONS = "Receive notifications"

    /** `tokenregistrationfail`. */
    const val TOKEN_REGISTRATION_FAIL =
        "We couldn't register this device for notifications. Please check your internet connection and try again, " +
            "or continue with regular payouts."
    const val RECEIVE_NOTIFICATIONS_2 =
        "To receive instant bitcoin payments, you must allow notifications.\n\n" +
            "Without them, your purchases are paid into the regular (on-chain) part of your wallet instead."
    const val RECEIVE_NOTIFICATIONS_3 =
        "To receive instant bitcoin payments, you must allow notifications.\n\n" +
            "On your device, go to Settings > Notifications > bittr to authorize our notifications.\n\n" +
            "You're free to continue without notifications, but then all your purchases will be paid into the regular " +
            "(on-chain) part of your wallet."
    const val VERIFICATION_FAIL = "Please enter the correct verification code."
    const val TRANSFER_15_VC_2 = "Something went wrong verifying your code. Please restart the app and try again. (Error: <error>)"
    const val BITTR_SIGNUP_FAIL = "Something went wrong creating your account. Please try again."
    const val BITTR_SIGNUP_FAIL_2 = "The IBAN you've entered appears to be invalid. Please enter a valid IBAN."
    const val BITTR_SIGNUP_FAIL_3 = "Something went wrong. Please try again later."
    const val EMAIL_RESENT = "We've resent our email!"
    const val EMAIL_RESENT_2 =
        "Check your Spam and Promotion folders to see if the code is there.\n\nPlease also check whether your address is correct:"
    const val CHANGE_EMAIL = "Change email"
    const val RESEND_CODE_2 = "Please wait 30 seconds before requesting another verification code."

    // Transfer3.
    const val READY_FOR_TRANSFER = "We're ready for your transfer!"
    const val PERSONAL_DETAILS =
        "These are your personal details. To buy bitcoin, make a bank transfer at any time and include your unique " +
            "code in the transfer description/memo field."
    const val SCREENSHOT = "Screenshot"
    const val SAVED = "Saved"
    const val SCREENSHOT_2 = "We've added the screenshot to your Photo Library."
    const val SCREENSHOT_3 = "We couldn't save your screenshot. Try taking a screenshot manually."
    const val FINAL_DETAILS = "Finish"

    // Transfer4.
    const val TRANSFER_3_AMOUNT = "Amount"
    const val TRANSFER_3_AMOUNT_LABEL = "You can buy up to 999 € worth of bitcoin per 30 days from bittr."
    const val TRANSFER_3_LIGHTNING = "Instant payments"
    const val TRANSFER_3_LIGHTNING_LABEL =
        "For purchases between 20 and 100 €, we create a lightning connection. With lightning, you can send and " +
            "receive instant payments against low fees.\n\nThe setup of this connection incurs a one-time fee of " +
            "10 000 satoshis. This fee covers the mining fees for opening and closing the connection, plus the " +
            "reservation of funds on our side of the connection."
    const val TRANSFER_3_CONNECTION = "Lightning connection"
    const val TRANSFER_3_CONNECTION_LABEL =
        "Lightning funds exist only on this device. Don't delete this app before closing your lightning connection."
    const val TRANSFER_3_DCA = "Dollar-cost-averaging"
    const val TRANSFER_3_DCA_LABEL =
        "Easily stack up on bitcoin by setting up a recurring bank transfer, e.g. 50 € every Monday."
    const val LETS_GO = "Let's go"
    const val BACK = "Back"
    const val BANKING_APP = "Open your banking app"
    const val BANKING_APP_2 =
        "Create your (recurring) transfer to<br><br><b><ouribannumber></b>\n<b><ourname></b>\n<b><youruniquecode></b>"

    // Profits.
    const val YOUR_PROFITS = "your profits"
    const val PROFIT_SUBTITLE = "Here's to financial independence! These are the results of your savings so far."
    const val TOTAL_INVESTMENT = "Total investment"
    const val CURRENT_VALUE = "Current value"
    const val TOTAL_PROFIT = "Total profit"

    /** `bankingapp2` with its placeholders filled. */
    fun bankingApp(ourIban: String, ourName: String, code: String): String = BANKING_APP_2
        .replace("<ouribannumber>", ourIban)
        .replace("<ourname>", ourName)
        .replace("<youruniquecode>", code)

    /** `transfer15vc2`. */
    fun codeError(error: String?): String = TRANSFER_15_VC_2.replace("<error>", error ?: "unavailable.")

    /** `emailresent2 <email>.` */
    fun emailResent(email: String): String = "$EMAIL_RESENT_2 $email."

    /** `bittrsignupfail3 (<message>.)` */
    fun signupFailed(message: String): String = "$BITTR_SIGNUP_FAIL_3 ($message.)"
}
