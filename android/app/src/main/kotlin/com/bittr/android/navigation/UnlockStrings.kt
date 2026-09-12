package com.bittr.android.navigation

import com.bittr.android.core.wallet.PinLockout

/**
 * The PIN gate's copy, ported verbatim from `ios/bittr/Language.swift`.
 *
 * Same arrangement as `SignupStrings`, and for the same reasons — see that file. What
 * is here rather than there is the copy the gate owns: the lockout, the warning, and
 * the forgot-PIN path. The PIN pad's own titles come from `SignupStrings`, because
 * they are literally the same strings on the same screen.
 *
 * **[PIN_WARNING_2] in particular is not to be shortened.** It is the only place the
 * user is told, before it happens, that ten wrong entries erase a wallet that may hold
 * their money, and that the recovery phrase is the way out that keeps it. Every clause
 * in it is load-bearing.
 */
internal object UnlockStrings {

    // PinViewController, .core embedding.
    const val ENTER_YOUR_PIN = "Enter your PIN"
    const val INCORRECT_PIN = "Incorrect PIN"
    const val INCORRECT_PIN_2 =
        "Please enter your correct PIN. If you've forgotten it, please restore your wallet."

    // The three-strikes warning.
    const val PIN_WARNING = "Warning"
    const val PIN_WARNING_2 =
        "You've entered the wrong PIN several times. After ${PinLockout.WIPE_AT} failed " +
            "attempts this wallet will be erased from the device, and any Bitcoin or " +
            "Lightning funds it holds may be permanently lost.\n\nIf you still have your " +
            "12-word recovery phrase, tap \"Forgot PIN\" to reset your PIN instead — this " +
            "keeps your wallet and your funds.\n\nNever delete the app from your phone, as " +
            "this can also lead to loss of funds."

    // The lockout.
    const val RESTORE_WALLET = "Restore wallet"
    const val PIN_LOCK =
        "You've entered an incorrect PIN too many times. Please restore your wallet."
    const val REMOVE_WALLET = "Remove wallet"
    const val REMOVAL_FAILED =
        "Something went wrong removing your wallet, so it hasn't been removed — your " +
            "wallet and funds are safe.\n\nPlease reopen the app to try again. Do not " +
            "delete the app from your phone."

    // Forgot PIN.
    const val FORGOT_PIN = "Forgot PIN"
    const val FORGOT_PIN_2 = "Please enter your 12-word recovery phrase to reset your PIN."
    const val FORGOT_PIN_3 = "The recovery phrase is incorrect."
    const val RESET = "Reset"
    const val RESET_PIN = "Reset PIN"

    // Shared.
    const val OKAY = "Okay"
    const val CANCEL = "Cancel"

    /**
     * "You have 4 attempts left." — iOS's `pinattemptsleft`, with `pinattemptleft` as
     * the singular.
     *
     * iOS keeps two dictionary entries rather than interpolating "1", because the
     * sentence has to read correctly in fourteen languages and not all of them
     * pluralise by appending an s. The split is preserved here so the extraction into
     * `shared/strings/` has the same two ids to carry across.
     */
    fun attemptsLeft(failures: Int): String = when (PinLockout.attemptsLeft(failures)) {
        1 -> "You have 1 attempt left."
        else -> "You have ${PinLockout.attemptsLeft(failures)} attempts left."
    }
}
