package com.bittr.android.feature.signup

/**
 * The create-wallet arc's copy, ported verbatim from `ios/bittr/Language.swift`.
 *
 * **Kotlin constants rather than `strings.xml`, deliberately and temporarily.** iOS
 * keeps all 14 languages in one Swift dictionary keyed by the ids below; the port's
 * localisation story is a shared extraction into `shared/strings/` (today that
 * directory holds only a README). Putting English in `strings.xml` now would create
 * a second source of truth that the extraction would immediately have to reconcile.
 * The ids are kept as the property names so the eventual mapping is mechanical.
 *
 * Do not paraphrase these. They are the strings a bittr user has already read on
 * iOS, and the alert copy in particular was written to avoid revealing the correct
 * recovery words.
 */
internal object SignupStrings {

    // Signup1 — create or restore.
    const val WELCOME = "welcome"
    const val CREATE_YOUR_OWN_WALLET =
        "Create your own bittr wallet and buy bitcoin directly from your banking app."
    const val CREATE_WALLET = "Create wallet"
    const val RESTORE_WALLET = "Restore wallet"

    // Signup3 — the phrase.
    const val RECOVERY_PHRASE =
        "This is your 12-word recovery phrase. It's crucial that you store it safely " +
            "where no one can access it."
    const val RECOVERY_PHRASE_2 = "This is your only opportunity to see it and save it."

    // Signup4 — the check.
    const val CONFIRM_RECOVERY_PHRASE = "Enter these words to confirm your recovery phrase."
    const val ENTER_WORD = "Enter word"
    const val MISSING_WORDS = "Missing words"
    const val MISSING_WORDS_2 =
        "Please enter all 3 words to confirm your recovery phrase. This helps ensure you " +
            "have backed up your wallet correctly."
    const val INVALID_WORDS = "Invalid words"
    const val INVALID_WORDS_2 =
        "Some of the words you entered are not valid recovery phrase words. Please check " +
            "your backup and try again."
    const val INCORRECT_PHRASE = "Incorrect recovery phrase"
    const val INCORRECT_PHRASE_2 =
        "Some of the words you've entered are incorrect. Please double-check your recovery " +
            "phrase backup and try again.\n\nFor your security, we recommend taking a fresh " +
            "backup of your recovery phrase to ensure you have the correct words."

    // Signup5 / Signup6 — the PIN.
    const val SET_A_PIN = "Set a PIN for secure access to your wallet"
    const val CONFIRM_YOUR_PIN = "Confirm your PIN"
    const val ENTER_YOUR_PIN = "Enter your PIN"
    const val INCORRECT_PIN = "Incorrect PIN"
    const val REPEAT_NUMBER = "Repeat the same number."
    const val PIN_SHOULD_BE_4_TO_8 = "PIN should be between 4 and 8 digits"

    // Signup7 — done.
    const val WALLET_IS_READY = "Your wallet is ready!"

    // Storage failure — the abort-loudly path.
    const val ERROR = "Error"
    const val MNEMONIC_SAVE_FAIL =
        "Something went wrong securely saving your wallet. Please try again."

    // Shared.
    const val NEXT = "Next"
    const val CONFIRM = "Confirm"
    const val BACK = "Back"
    const val OKAY = "Okay"
    const val CONTINUE = "Continue"
    const val SKIP = "Skip"

    /**
     * Shown on the Ready screen while BIT-6 is outstanding.
     *
     * BIT-93 ships a real seed and no funds on purpose: the key handling has not yet
     * been reviewed by the Bitcoin Wallet Engineer, so the build must not show a
     * mainnet receive address or take a deposit. Saying so on screen is cheaper than
     * a user discovering it by sending money.
     */
    const val NO_FUNDS_YET =
        "This build can create and protect your recovery phrase. Receiving and buying " +
            "bitcoin are not switched on yet."
}
