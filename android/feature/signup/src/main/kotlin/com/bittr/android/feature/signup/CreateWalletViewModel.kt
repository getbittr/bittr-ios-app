package com.bittr.android.feature.signup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.seed.SeedChallenge
import com.bittr.android.core.wallet.seed.SeedCheck
import com.bittr.android.core.wallet.seed.SeedWalletService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Where the user is in the create-wallet arc. One entry per iOS view controller. */
enum class CreateWalletStep {
    /** `Signup1ViewController` — create or restore. */
    Start,

    /**
     * `Signup2ViewController` — the two statements the user confirms.
     *
     * Before this step nothing irreversible has happened; after it a seed exists. It
     * is the last point at which "if you lose your backup your bitcoin is gone" can
     * be told to someone who has not yet been given anything to lose.
     */
    Confirm,

    /** `Signup3ViewController` — the twelve words. */
    Phrase,

    /** `Signup4ViewController` — type three of them back. */
    Verify,

    /** `Signup5ViewController` — choose a PIN. */
    PinSet,

    /** `Signup6ViewController` — type it again. */
    PinConfirm,

    /** `Signup7ViewController` — done. */
    Ready,
}

/** A message the screen shows and the user dismisses. Mirrors the iOS alerts. */
data class SignupAlert(val title: String, val message: String)

data class CreateWalletUiState(
    val step: CreateWalletStep = CreateWalletStep.Start,
    val busy: Boolean = false,
    val mnemonic: Mnemonic? = null,
    val challenge: SeedChallenge? = null,
    val alert: SignupAlert? = null,
)

/**
 * The create-wallet arc.
 *
 * **The phrase lives here and is never a navigation argument.** Compose Navigation
 * routes are strings and its arguments land in the saved-state `Bundle`, which the
 * system writes to disk when it stops the process — so routing the twelve words
 * between destinations would persist the seed in cleartext somewhere nobody chose.
 * Holding the arc in one destination, with the step in a ViewModel, keeps the phrase
 * in memory between the screen that shows it and the screen that checks it, which is
 * the whole window in which it exists outside the Keystore.
 *
 * That is also why [CreateWalletUiState] is cleared on [finish] rather than left for
 * the garbage collector to get to eventually.
 */
@HiltViewModel
class CreateWalletViewModel @Inject constructor(
    private val wallet: WalletService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CreateWalletUiState())
    val uiState: StateFlow<CreateWalletUiState> = _uiState.asStateFlow()

    private var firstPin: String? = null

    /**
     * Leave Start for the consent step. Nothing is generated yet.
     *
     * The generation deliberately does *not* happen here and run in the background
     * while the user reads: a seed that exists before consent is a seed that has to be
     * thrown away if they back out, and "we made you a wallet while you were reading"
     * is not what the screen says.
     */
    fun startCreate() {
        if (_uiState.value.busy) return
        _uiState.value = _uiState.value.copy(step = CreateWalletStep.Confirm)
    }

    /** Back out of the consent step. Nothing to clear — nothing has been made yet. */
    fun backToStart() {
        _uiState.value = _uiState.value.copy(step = CreateWalletStep.Start)
    }

    /**
     * Generate and persist the phrase, then show it.
     *
     * If it cannot be stored, stay on Start and say so — the iOS `Signup1` contract.
     * Advancing here would walk the user through backing up a phrase that is not on
     * the device.
     */
    fun createWallet() {
        if (_uiState.value.busy) return
        _uiState.value = _uiState.value.copy(busy = true)
        viewModelScope.launch {
            try {
                val mnemonic = wallet.createWallet()
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    mnemonic = mnemonic,
                    step = CreateWalletStep.Phrase,
                )
            } catch (e: WalletStorageException) {
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    step = CreateWalletStep.Start,
                    mnemonic = null,
                    alert = SignupAlert(
                        SignupStrings.ERROR,
                        SignupStrings.MNEMONIC_SAVE_FAIL,
                    ),
                )
            }
        }
    }

    /** Move from the phrase to the check, picking the three words to ask about. */
    fun confirmPhraseSeen() {
        val mnemonic = _uiState.value.mnemonic ?: return
        _uiState.value = _uiState.value.copy(
            step = CreateWalletStep.Verify,
            challenge = SeedChallenge.random(mnemonic),
        )
    }

    /**
     * Check the three typed words.
     *
     * Every rejection keeps the user on Verify. The three failure modes carry
     * different copy because they mean different things to the person typing.
     */
    fun submitVerification(answers: List<String>) {
        val challenge = _uiState.value.challenge ?: return
        val alert = when (challenge.check(answers)) {
            SeedCheck.Correct -> {
                _uiState.value = _uiState.value.copy(step = CreateWalletStep.PinSet)
                return
            }
            SeedCheck.Missing ->
                SignupAlert(SignupStrings.MISSING_WORDS, SignupStrings.MISSING_WORDS_2)
            SeedCheck.NotInWordlist ->
                SignupAlert(SignupStrings.INVALID_WORDS, SignupStrings.INVALID_WORDS_2)
            SeedCheck.Incorrect ->
                SignupAlert(SignupStrings.INCORRECT_PHRASE, SignupStrings.INCORRECT_PHRASE_2)
        }
        _uiState.value = _uiState.value.copy(alert = alert)
    }

    /** Back from the check to the phrase — `Signup4`'s back button. */
    fun backToPhrase() {
        _uiState.value = _uiState.value.copy(step = CreateWalletStep.Phrase, challenge = null)
    }

    fun submitFirstPin(pin: String) {
        if (!SeedWalletService.isValidPin(pin)) {
            _uiState.value = _uiState.value.copy(
                alert = SignupAlert(
                    SignupStrings.INCORRECT_PIN,
                    SignupStrings.PIN_SHOULD_BE_4_TO_8,
                ),
            )
            return
        }
        firstPin = pin
        _uiState.value = _uiState.value.copy(step = CreateWalletStep.PinConfirm)
    }

    fun backToPinSet() {
        firstPin = null
        _uiState.value = _uiState.value.copy(step = CreateWalletStep.PinSet)
    }

    /**
     * Confirm the PIN and complete setup.
     *
     * This is the point at which the wallet becomes real: before [WalletService.setPin]
     * succeeds the service still reports `Uninitialized`, so a user who quits mid-arc
     * restarts signup rather than facing a PIN screen for a phrase they never
     * finished writing down.
     */
    fun submitConfirmationPin(pin: String) {
        val expected = firstPin
        if (expected == null) {
            backToPinSet()
            return
        }
        if (pin != expected) {
            _uiState.value = _uiState.value.copy(
                alert = SignupAlert(SignupStrings.INCORRECT_PIN, SignupStrings.REPEAT_NUMBER),
            )
            return
        }
        viewModelScope.launch {
            try {
                wallet.setPin(pin)
                firstPin = null
                _uiState.value = _uiState.value.copy(
                    step = CreateWalletStep.Ready,
                    // The words have served their purpose; drop the reference here
                    // rather than carrying them into the Ready screen.
                    mnemonic = null,
                    challenge = null,
                )
            } catch (e: WalletStorageException) {
                firstPin = null
                _uiState.value = _uiState.value.copy(
                    step = CreateWalletStep.PinSet,
                    alert = SignupAlert(SignupStrings.ERROR, SignupStrings.MNEMONIC_SAVE_FAIL),
                )
            }
        }
    }

    /** Leave the arc. The caller navigates; this drops what the arc was holding. */
    fun finish() {
        firstPin = null
        _uiState.value = CreateWalletUiState()
    }

    fun dismissAlert() {
        _uiState.value = _uiState.value.copy(alert = null)
    }
}
