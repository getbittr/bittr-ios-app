package com.bittr.android.feature.signup

/**
 * iOS's signup page numbers — the index of each page in `SignupViewController.embedViewIdentifiers`,
 * which is also its place in the strip the pages slide along ([com.bittr.android.core.designsystem.pageSlide]).
 * Restore runs leftwards from Signup1 and create rightwards, so the direction of every slide comes
 * out of these numbers the way it does on iOS.
 */
object SignupPage {
    /** `Restore3` — confirm the restored wallet's PIN. */
    const val RESTORE_PIN_CONFIRM = 0

    /** `Restore2` — set the restored wallet's PIN. */
    const val RESTORE_PIN_SET = 1

    /** `Restore` — enter the recovery phrase. */
    const val RESTORE = 2

    /** `Signup1` — create or restore. */
    const val START = 3

    /** `Signup2` — the statements. */
    const val CONFIRM = 4

    /** `Signup3` — the recovery phrase. */
    const val PHRASE = 5

    /** `Signup4` — the phrase check. */
    const val VERIFY = 6

    /** `Signup5` — set a PIN. */
    const val PIN_SET = 7

    /** `Signup6` — confirm the PIN. */
    const val PIN_CONFIRM = 8

    /** `Signup7` — the wallet is ready. */
    const val READY = 9

    /**
     * `Transfer1` — the bittr signup's IBAN page, a destination of its own here. The bittr
     * signup's later pages slide inside it, as `RegisterIbanViewController`'s do.
     */
    const val TRANSFER = 10
}

internal val CreateWalletStep.page: Int
    get() = when (this) {
        CreateWalletStep.Start -> SignupPage.START
        CreateWalletStep.Confirm -> SignupPage.CONFIRM
        CreateWalletStep.Phrase -> SignupPage.PHRASE
        CreateWalletStep.Verify -> SignupPage.VERIFY
        CreateWalletStep.PinSet -> SignupPage.PIN_SET
        CreateWalletStep.PinConfirm -> SignupPage.PIN_CONFIRM
        CreateWalletStep.Ready -> SignupPage.READY
    }

internal val RestoreWalletStep.page: Int
    get() = when (this) {
        RestoreWalletStep.Phrase -> SignupPage.RESTORE
        RestoreWalletStep.PinSet -> SignupPage.RESTORE_PIN_SET
        RestoreWalletStep.PinConfirm -> SignupPage.RESTORE_PIN_CONFIRM
    }
