package com.bittr.android.feature.settings

/**
 * The Settings area's copy, ported verbatim from `ios/bittr/Language.swift`.
 *
 * Same arrangement as `SignupStrings`, `UnlockStrings` and `HomeStrings`, with the
 * iOS dictionary id named on each entry.
 *
 * Two of these are load-bearing for `features/settings.yaml` beyond being correct
 * copy: [ENGLISH] and the currency labels are tapped **by text** by the flow, because
 * the iOS pickers are native `UIAlertController`s with no accessibility identifiers.
 * Rewording them breaks the flow on Android while iOS stays green.
 */
internal object SettingsStrings {

    // SettingsViewController.
    const val SETTINGS = "Settings"
    const val GET_SUPPORT = "Get support"
    const val PRIVACY_POLICY = "Privacy Policy"
    const val TERMS_AND_CONDITIONS = "Terms & Conditions"
    const val DEVICE_DETAILS = "Device details"
    const val APP_VERSION = "App version"

    // DeviceViewController.
    const val ACCESS_DETAILS = "Access your device details in case you need our support."
    const val DARK_MODE = "Dark mode"
    const val LANGUAGE = "Language"
    const val CURRENCY = "Currency"
    const val DEVICE_TOKEN = "Device token"

    /**
     * Shown where iOS shows nothing: it only opens the token alert when a token arrives, so a
     * device with notifications denied gets no answer at all. `receivenotifications3`, the
     * approved wording for that state, is the same sentence the Buy flow uses.
     */
    const val DEVICE_TOKEN_UNAVAILABLE =
        "To receive instant bitcoin payments, you must allow notifications.\n\n" +
            "On your device, go to Settings > Notifications > bittr to authorize our " +
            "notifications.\n\nYou're free to continue without notifications, but then all " +
            "your purchases will be paid into the regular (on-chain) part of your wallet."
    const val PUBLIC_KEY = "Public key"
    const val BITTR_PEER = "Bittr peer"
    const val PENDING_PAYOUT = "Pending payout"
    const val LIGHTNING_CONNECTIONS = "Lightning connections"
    const val REMOVE_WALLET = "Remove wallet"

    /** The trailing action labels — `fetch` and `check`. */
    const val FETCH = "Fetch"
    const val CHECK = "Check"

    /**
     * `DeviceViewController.syncChannels()`'s value when `ldkNode` is nil. It is the
     * literal string iOS puts in the row, not a translated one — the dictionary has
     * no entry for it.
     */
    const val SYNCING = "Syncing"

    // The two pickers. The option labels are what settings.yaml taps by text.
    const val SELECT_LANGUAGE = "Language"
    const val SELECT_LANGUAGE_MESSAGE = "Choose your preferred language."
    const val ENGLISH_US = "English (US)"

    /** The value the language row shows for `en_US`. */
    const val ENGLISH = "English"

    const val SELECT_CURRENCY = "Currency"
    const val SELECT_CURRENCY_MESSAGE = "Choose your preferred currency."

    /**
     * The question card behind the Lightning-connections row.
     *
     * `checkChannels()` launches `QuestionViewController` with the header
     * `lightningchannels` and the body `lightningexplanation1`. With no active channel
     * the card shows exactly this text and no chart — which is the state every build
     * without a node is in, so it is the whole of what is ported here.
     */
    const val LIGHTNING_CONNECTIONS_TITLE = "lightning connections"
    const val LIGHTNING_EXPLANATION =
        "To send and receive instant bitcoin payments, you need to have at least one " +
            "lightning connection.\n\nTo open a connection with bittr, buy bitcoin worth up " +
            "to 100 CHF/EUR to receive a lightning connection. Check your wallet's Buy " +
            "section or getbittr.com for all information."

    // The channel chart, when there is an active channel. `questionvc7`, `total`, `reserve`;
    // the two titles are `Main.storyboard`'s labels.
    const val QUESTION_VC_7 =
        "As part of your bittr wallet, you have a <b>bitcoin wallet</b> (for regular payments) and a " +
            "<b>bitcoin lightning connection</b> (for instant payments).\n\nYour lightning balance is " +
            "<b><channelbalance> satoshis</b>. The connection needs to contain a minimum of " +
            "<b><channelreserve> sats</b>, so you can send up to <b><sendlimit> sats</b>."
    const val YOUR_BALANCE = "Your balance"
    const val RECEIVE_LIMIT = "Receive limit"
    const val TOTAL = "total"
    const val RESERVE = "reserve"

    // Send's limit card, `lightningsendable`: `limitlightning`, and with no channel `questionvc12` /
    // `questionvc13`, which replace both the header and the text on iOS.
    const val LIMIT_LIGHTNING = "why a limit for instant payments?"
    const val QUESTION_VC_12 = "why can't I receive instant payments?"
    const val QUESTION_VC_13 =
        "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning connection " +
            "(for instant payments).\n\nYou don't currently have a lightning connection.\n\nTo open a connection " +
            "with bittr, buy bitcoin worth between 20 and 100 €. Check your wallet's Buy section or getbittr.com " +
            "for all information."

    // The guard in front of every node-backed row. `syncingwallet` / `syncingwallet2`.
    const val SYNCING_WALLET = "Syncing wallet"
    const val SYNCING_WALLET_2 = "Please wait a moment while we're syncing your wallet."

    // The node-backed rows. `bittrpeer2`/`3`, `bittrpendingpayout2`/`3`.
    const val BITTR_PEER_2 = "You're connected to bittr."
    const val BITTR_PEER_3 = "You're not connected to bittr."
    const val PENDING_PAYOUT_2 =
        "There are no pending payouts available at this time. If you need our help, please contact support@getbittr.com."
    const val PENDING_PAYOUT_3 = "There's a pending payout available for handling. Would you like to do so now?"

    // Shared.
    const val OKAY = "Okay"
    const val CANCEL = "Cancel"
    const val CLOSE = "Close"
    const val COPY = "Copy"
    const val CONNECT = "Connect"
    const val CONFIRM = "Confirm"
}

/**
 * The three pages `SettingsViewController.settingsTapped` opens in a web view.
 *
 * The URLs are the ones hard-coded in that method. They are `getbittr.com` rather
 * than an environment-dependent host on iOS too — these are the public marketing and
 * legal pages, not the API — so BIT-32's base-URL switch does not apply to them.
 */
enum class WebsitePage(val url: String) {
    Support("https://getbittr.com/support"),
    Privacy("https://getbittr.com/privacy-policy"),
    Terms("https://getbittr.com/terms-and-conditions"),
}
