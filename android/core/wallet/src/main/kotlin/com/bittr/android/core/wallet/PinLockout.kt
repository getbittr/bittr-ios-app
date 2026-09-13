package com.bittr.android.core.wallet

/**
 * When a wrong PIN becomes a warning, and when it becomes a wiped wallet.
 *
 * The two numbers are the literals in `PinViewController.confirmPinButtonTapped` —
 * `== 3` for the warning and `>= 10` for the lockout — pulled out here because they
 * are the part of the PIN gate that can cost someone their coins, and a threshold
 * that only exists inside a composable can only be checked on an emulator.
 *
 * **Nothing here reads or writes state.** The count is [WalletService]'s, persisted
 * so it survives a force-quit; this object only says what a given count means. That
 * split is what lets the thresholds be tested without a wallet and the persistence be
 * tested without a UI.
 */
object PinLockout {

    /**
     * The wrong entry that earns the warning rather than the plain incorrect-PIN alert.
     *
     * Matched with `==`, not `>=`: iOS shows the warning once, on the third failure,
     * and goes back to the ordinary alert for 4–9. Re-showing a two-button alert on
     * every subsequent attempt would make the "Forgot PIN" button the thing standing
     * between the user and retrying, which is the opposite of what it is for.
     */
    const val WARN_AT = 3

    /** The failure count at which the wallet is erased from the device. */
    const val WIPE_AT = 10

    /**
     * True once the wallet is past saving by PIN entry.
     *
     * `>=`, not `==`, because the count is read back from storage at launch: a process
     * killed between the tenth failure and the wipe comes back with the counter at ten
     * and must still be locked out, and a count that somehow overshot must not wrap
     * round into a usable wallet.
     */
    fun isLockedOut(failures: Int): Boolean = failures >= WIPE_AT

    /** True on the one failure that shows the warning alert. */
    fun isWarning(failures: Int): Boolean = failures == WARN_AT

    /**
     * How many wrong entries are left before [WIPE_AT].
     *
     * Floored at zero so the warning copy can never read "-1 attempts left" if the
     * count is ever read back higher than the threshold.
     */
    fun attemptsLeft(failures: Int): Int = (WIPE_AT - failures).coerceAtLeast(0)
}
