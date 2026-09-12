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

    // The guard in front of every node-backed row. `syncingwallet` / `syncingwallet2`.
    const val SYNCING_WALLET = "Syncing wallet"
    const val SYNCING_WALLET_2 = "Please wait a moment while we're syncing your wallet."

    // Shared.
    const val OKAY = "Okay"
    const val CANCEL = "Cancel"
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
