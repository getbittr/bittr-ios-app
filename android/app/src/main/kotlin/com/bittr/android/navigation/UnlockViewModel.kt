package com.bittr.android.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.PinLockout
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.WrongSeedException
import com.bittr.android.core.wallet.seed.PhraseEntry
import com.bittr.android.core.wallet.seed.SeedPhraseEntry
import com.bittr.android.core.wallet.seed.SeedWalletService
import com.bittr.android.feature.signup.SignupStrings
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Where the user is on the PIN gate. One entry per iOS screen. */
enum class UnlockStep {
    /** `PinViewController` in its `.core` embedding — the unlock pad. */
    Pin,

    /** `RestoreViewController` with `resettingPin` set — prove the phrase. */
    ResetPhrase,

    /** `Restore2ViewController` — choose the new PIN. */
    ResetPinSet,

    /** `Restore3ViewController` — type it again, then Home. */
    ResetPinConfirm,
}

/**
 * An alert the gate is showing.
 *
 * Modelled as a type rather than as a pair of strings because two of them have a
 * second button that *does* something, and "which button did they press" has to
 * survive the trip through the composable. The order of [dismissLabel] then
 * [confirmLabel] is the order iOS writes its `buttons:` array in, which is the order
 * `alert.button.0` / `alert.button.1` are numbered in — see `BittrAlertDialog`.
 */
sealed interface UnlockAlert {

    val title: String
    val message: String

    /** The right-hand button. On a one-button alert this is the only one, index 0. */
    val confirmLabel: String

    /** The left-hand, cancelling button at index 0, or null for a one-button alert. */
    val dismissLabel: String? get() = null

    /** `incorrectpin` — wrong entries 1, 2, and 4 through 9. */
    data class IncorrectPin(private val failures: Int) : UnlockAlert {
        override val title = UnlockStrings.INCORRECT_PIN
        override val message =
            UnlockStrings.INCORRECT_PIN_2 + "\n\n" + UnlockStrings.attemptsLeft(failures)
        override val confirmLabel = UnlockStrings.OKAY
    }

    /**
     * `pinwarning` — the third wrong entry, and the only alert on this screen with a
     * way out of it. Confirm is "Forgot PIN".
     */
    data class Warning(private val failures: Int) : UnlockAlert {
        override val title = UnlockStrings.PIN_WARNING
        override val message =
            UnlockStrings.PIN_WARNING_2 + "\n\n" + UnlockStrings.attemptsLeft(failures)
        override val dismissLabel = UnlockStrings.OKAY
        override val confirmLabel = UnlockStrings.FORGOT_PIN
    }

    /** `forgotpin2` — the [Cancel, Reset] confirmation behind the Forgot PIN button. */
    data object ConfirmReset : UnlockAlert {
        override val title = UnlockStrings.FORGOT_PIN
        override val message = UnlockStrings.FORGOT_PIN_2
        override val dismissLabel = UnlockStrings.CANCEL
        override val confirmLabel = UnlockStrings.RESET
    }

    /** `pinlock` — the wallet is gone. Okay leaves for signup. */
    data object Wiped : UnlockAlert {
        override val title = UnlockStrings.RESTORE_WALLET
        override val message = UnlockStrings.PIN_LOCK
        override val confirmLabel = UnlockStrings.OKAY
    }

    /** Anything that is just something to read: a wrong phrase, a failed write. */
    data class Message(override val title: String, override val message: String) : UnlockAlert {
        override val confirmLabel = UnlockStrings.OKAY
    }
}

data class UnlockUiState(
    val step: UnlockStep = UnlockStep.Pin,
    val alert: UnlockAlert? = null,
    val busy: Boolean = false,
)

/**
 * The PIN gate — `PinViewController` in its `.core` embedding, plus the two paths out
 * of it that are not "the PIN was right".
 *
 * ### The three-way branch, in iOS's order
 *
 * `confirmPinButtonTapped` checks the stored failure count *before* it checks the PIN,
 * and [submitPin] keeps that order, because the two are not interchangeable:
 *
 *  - A count already at [PinLockout.WIPE_AT] wipes without verifying. That is what
 *    resumes a wipe that was interrupted by the process dying, and it is why the
 *    counter is in secure storage rather than in this class.
 *  - Otherwise the PIN is checked, and a **correct tenth entry still unlocks** — the
 *    guard is above the wrong-PIN branch, not above the whole method. Someone who has
 *    got it wrong nine times and then remembers is not who the lockout is for.
 *  - A wrong entry increments first and decides afterwards, so the tenth wrong entry
 *    wipes rather than showing "you have 0 attempts left".
 *
 * ### The reset path is non-destructive, and that is the point
 *
 * Both routes into [UnlockStep.ResetPhrase] — the Forgot PIN button and the warning's
 * second button — lead to typing the recovery phrase, not to erasing anything. The
 * phrase is checked against the one already on the device
 * ([WalletService.holdsSeed]); a match buys a new PIN on the *same* wallet, with the
 * funds still in it. That is the outcome the warning copy is steering people towards,
 * and it is why the warning fires at three rather than at nine.
 *
 * The phrase is held for exactly as long as the two PIN steps take and never enters
 * [UnlockUiState] — same rule as `RestoreWalletViewModel`, for the same reason.
 */
@HiltViewModel
class UnlockViewModel @Inject constructor(
    private val wallet: WalletService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(UnlockUiState())
    val uiState: StateFlow<UnlockUiState> = _uiState.asStateFlow()

    /** Set once the wallet has actually been erased; the Okay on [UnlockAlert.Wiped]. */
    private var walletWasWiped = false

    private var provenSeed: Mnemonic? = null
    private var firstPin: String? = null

    /**
     * `CoreViewController.checkWalletRemoval` — run when the gate appears.
     *
     * A wipe that was already earned has to complete even if the app was killed
     * between the tenth wrong PIN and the erase. Without this, force-quitting at
     * exactly that moment is a way to keep a wallet that is already forfeit, and the
     * user is left with a counter that locks them out on the next attempt anyway.
     */
    fun checkLockout() {
        viewModelScope.launch {
            if (PinLockout.isLockedOut(wallet.failedUnlockAttempts())) wipeWallet()
        }
    }

    /** @param onUnlocked runs only after the PIN was right and the wallet is up. */
    fun submitPin(pin: String, onUnlocked: () -> Unit) {
        if (_uiState.value.busy) return
        _uiState.value = _uiState.value.copy(busy = true)
        viewModelScope.launch {
            if (PinLockout.isLockedOut(wallet.failedUnlockAttempts())) {
                wipeWallet()
                return@launch
            }

            if (wallet.unlock(pin)) {
                // No node to bring up until BIT-6 — start() is the stub's no-op today,
                // but calling it here means the lifecycle hook already exists when it
                // is not.
                wallet.start()
                _uiState.value = _uiState.value.copy(busy = false)
                onUnlocked()
                return@launch
            }

            val failures = wallet.failedUnlockAttempts()
            val alert = when {
                PinLockout.isLockedOut(failures) -> {
                    wipeWallet()
                    return@launch
                }
                PinLockout.isWarning(failures) -> UnlockAlert.Warning(failures)
                else -> UnlockAlert.IncorrectPin(failures)
            }
            _uiState.value = _uiState.value.copy(busy = false, alert = alert)
        }
    }

    /** The "Forgot PIN" button under the pad — `restoreButtonTapped`, `.core`. */
    fun forgotPin() {
        _uiState.value = _uiState.value.copy(alert = UnlockAlert.ConfirmReset)
    }

    /**
     * `startPinReset` — open the phrase fields.
     *
     * Reached two ways, and the difference is which alert was on screen: the Forgot
     * PIN button asks [UnlockAlert.ConfirmReset] first, the warning's second button
     * does not. That asymmetry is iOS's and `pin_warning.yaml` asserts it — someone
     * who has just been told they are three wrong entries from losing their wallet
     * should not have to get past another confirmation to save it.
     */
    fun startPinReset() {
        _uiState.value = UnlockUiState(step = UnlockStep.ResetPhrase)
    }

    /** Back out of the reset without having changed anything. */
    fun cancelPinReset() {
        provenSeed = null
        firstPin = null
        _uiState.value = UnlockUiState(step = UnlockStep.Pin)
    }

    /**
     * Check the twelve typed words against the phrase on the device.
     *
     * Two gates, and they say different things. [SeedPhraseEntry] decides whether this
     * is a phrase at all — the same verdicts and the same copy the restore arc shows,
     * because a mistyped word is a mistyped word on either screen. Only then is it
     * compared against the stored seed, which is the question this screen actually
     * asks, and a valid phrase that is not *this wallet's* gets `forgotpin3`.
     */
    fun submitResetPhrase(words: List<String>) {
        if (_uiState.value.busy) return

        val mnemonic = when (val entry = SeedPhraseEntry.check(words)) {
            is PhraseEntry.Accepted -> entry.mnemonic
            PhraseEntry.Incomplete -> {
                showAlert(SignupStrings.INCOMPLETE_PHRASE, SignupStrings.INCOMPLETE_PHRASE_2)
                return
            }
            PhraseEntry.NotInWordlist, PhraseEntry.ChecksumFailed -> {
                showAlert(SignupStrings.INVALID_PHRASE, SignupStrings.INVALID_PHRASE_2)
                return
            }
        }

        _uiState.value = _uiState.value.copy(busy = true)
        viewModelScope.launch {
            if (!wallet.holdsSeed(mnemonic)) {
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    alert = UnlockAlert.Message(
                        UnlockStrings.FORGOT_PIN,
                        UnlockStrings.FORGOT_PIN_3,
                    ),
                )
                return@launch
            }
            provenSeed = mnemonic
            _uiState.value = _uiState.value.copy(busy = false, step = UnlockStep.ResetPinSet)
        }
    }

    fun submitFirstPin(pin: String) {
        if (!SeedWalletService.isValidPin(pin)) {
            showAlert(SignupStrings.INCORRECT_PIN, SignupStrings.PIN_SHOULD_BE_4_TO_8)
            return
        }
        firstPin = pin
        _uiState.value = _uiState.value.copy(step = UnlockStep.ResetPinConfirm)
    }

    fun backToPinSet() {
        firstPin = null
        _uiState.value = _uiState.value.copy(step = UnlockStep.ResetPinSet)
    }

    /**
     * Confirm the new PIN, completing the reset.
     *
     * [onDone] runs only after [WalletService.resetPin] has succeeded, so the caller
     * never navigates to Home for a wallet that is still locked behind the old PIN.
     */
    fun submitConfirmationPin(pin: String, onDone: () -> Unit) {
        val expected = firstPin
        val mnemonic = provenSeed
        if (expected == null || mnemonic == null) {
            // Lost the arc's state — send the user back a step rather than reset a PIN
            // against a phrase nobody proved.
            backToPinSet()
            return
        }
        if (pin != expected) {
            showAlert(SignupStrings.INCORRECT_PIN, SignupStrings.REPEAT_NUMBER)
            return
        }
        if (_uiState.value.busy) return
        _uiState.value = _uiState.value.copy(busy = true)
        viewModelScope.launch {
            try {
                wallet.resetPin(mnemonic, pin)
                provenSeed = null
                firstPin = null
                _uiState.value = UnlockUiState()
                onDone()
            } catch (e: WrongSeedException) {
                // Belt and braces: holdsSeed already said yes. Reaching here means the
                // stored seed changed under us, so start the proof again.
                provenSeed = null
                firstPin = null
                _uiState.value = UnlockUiState(
                    step = UnlockStep.ResetPhrase,
                    alert = UnlockAlert.Message(
                        UnlockStrings.FORGOT_PIN,
                        UnlockStrings.FORGOT_PIN_3,
                    ),
                )
            } catch (e: WalletStorageException) {
                firstPin = null
                _uiState.value = UnlockUiState(
                    step = UnlockStep.ResetPinSet,
                    alert = UnlockAlert.Message(
                        SignupStrings.ERROR,
                        SignupStrings.MNEMONIC_SAVE_FAIL,
                    ),
                )
            }
        }
    }

    /**
     * Dismiss the alert, and tell the caller whether the wallet went with it.
     *
     * @return true when the alert that was showing was [UnlockAlert.Wiped], meaning
     *   there is no longer a wallet on this device and the caller must leave for
     *   signup. Returned rather than pushed through a callback so the one transition
     *   that cannot be undone is visible at the call site.
     */
    fun dismissAlert(): Boolean {
        val wasWiped = _uiState.value.alert is UnlockAlert.Wiped && walletWasWiped
        _uiState.value = _uiState.value.copy(alert = null)
        return wasWiped
    }

    /**
     * `removeWallet` — erase it, then say so.
     *
     * The alert goes up *after* the erase rather than before it, unlike iOS, which
     * shows it and wipes behind it. The copy tells the user their wallet is gone, and
     * on the failure path it is not: [WalletService.removeWallet] leaves an openable
     * wallet behind rather than a seed with no way in, and `removalfailed` is the
     * alert that says so. Ordering it this way means the app never claims a removal
     * that did not happen.
     */
    private suspend fun wipeWallet() {
        _uiState.value = _uiState.value.copy(busy = true)
        try {
            wallet.removeWallet()
            walletWasWiped = true
            _uiState.value = UnlockUiState(alert = UnlockAlert.Wiped)
        } catch (e: WalletStorageException) {
            _uiState.value = UnlockUiState(
                alert = UnlockAlert.Message(
                    UnlockStrings.REMOVE_WALLET,
                    UnlockStrings.REMOVAL_FAILED,
                ),
            )
        }
    }

    private fun showAlert(title: String, message: String) {
        _uiState.value = _uiState.value.copy(alert = UnlockAlert.Message(title, message))
    }
}
