package com.bittr.android.feature.signup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.seed.PhraseEntry
import com.bittr.android.core.wallet.seed.SeedPhraseEntry
import com.bittr.android.core.wallet.seed.SeedWalletService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Where the user is in the restore arc. One entry per iOS view controller. */
enum class RestoreWalletStep {
    /** `RestoreViewController` — the twelve fields. */
    Phrase,

    /** `Restore2ViewController` — choose a PIN for the restored wallet. */
    PinSet,

    /** `Restore3ViewController` — type it again, then Home. */
    PinConfirm,
}

data class RestoreWalletUiState(
    val step: RestoreWalletStep = RestoreWalletStep.Phrase,
    val busy: Boolean = false,
    val alert: SignupAlert? = null,
)

/**
 * The restore arc — `RestoreViewController` → `Restore2` → `Restore3` → Home.
 *
 * Sibling of [CreateWalletViewModel], and it keeps the phrase out of navigation for
 * the same reason: Compose Navigation puts arguments in the saved-state `Bundle` and
 * the system writes that to disk on process death, so routing between the field
 * screen and the PIN screens would persist someone's seed in cleartext.
 *
 * This arc goes one further than the create arc and never holds the phrase at all.
 * It is read out of the fields, checked, handed to [WalletService.restoreWallet] and
 * dropped inside [submitPhrase] — nothing downstream needs it, so the window in which
 * it exists outside the Keystore is one function call rather than three screens. It
 * is deliberately not in [RestoreWalletUiState] either: UI state is the thing a
 * Compose tooling inspector will happily print.
 *
 * ### Three differences from the create arc, all of them deliberate
 *
 * **There is no consent step.** `Signup2`'s "if you lose your backup your bitcoin is
 * gone" is told to someone who is about to be given something to lose. A user
 * restoring already has it and has already been told.
 *
 * **There is no verify step.** Typing three words back proves you wrote down a phrase
 * you were just shown. Typing all twelve *is* the proof, and it has already happened.
 *
 * **There is no Ready screen.** iOS's `Restore3.nextButtonTapped` calls `hideSignup`
 * and Home appears — no `Signup7`. `restore_wallet.yaml` asserts `home.headerLabel`
 * straight after the PIN confirm, so adding a Ready step here would break the flow.
 */
@HiltViewModel
class RestoreWalletViewModel @Inject constructor(
    private val wallet: WalletService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(RestoreWalletUiState())
    val uiState: StateFlow<RestoreWalletUiState> = _uiState.asStateFlow()

    private var firstPin: String? = null

    /**
     * Check the twelve typed words and, if they are a phrase, store them.
     *
     * **Both invalid cases carry the same copy, on purpose.** iOS runs one gate here
     * (`BitcoinManager.isValidMnemonic`) and shows one alert, and a mistyped word and
     * a failed checksum both land on it. [SeedPhraseEntry] tells them apart so the
     * tests can, but splitting the message the user reads is a copy change and copy
     * belongs to the Designer — see the note on [SeedPhraseEntry].
     */
    fun submitPhrase(words: List<String>) {
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
            try {
                wallet.restoreWallet(mnemonic)
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    step = RestoreWalletStep.PinSet,
                )
            } catch (e: WalletStorageException) {
                // iOS's `mnemonicsavefail` catch: stay on the fields rather than walk
                // someone through setting a PIN for a seed that is not on the device.
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    step = RestoreWalletStep.Phrase,
                    alert = SignupAlert(
                        SignupStrings.ERROR,
                        SignupStrings.MNEMONIC_SAVE_FAIL,
                    ),
                )
            }
        }
    }

    fun submitFirstPin(pin: String) {
        if (!SeedWalletService.isValidPin(pin)) {
            showAlert(SignupStrings.INCORRECT_PIN, SignupStrings.PIN_SHOULD_BE_4_TO_8)
            return
        }
        firstPin = pin
        _uiState.value = _uiState.value.copy(step = RestoreWalletStep.PinConfirm)
    }

    fun backToPinSet() {
        firstPin = null
        _uiState.value = _uiState.value.copy(step = RestoreWalletStep.PinSet)
    }

    /**
     * Confirm the PIN, completing the restore.
     *
     * [onDone] rather than a `Done` step: the caller navigates to Home, matching
     * `Restore3.nextButtonTapped` calling `hideSignup`. It runs only after
     * [WalletService.setPin] has actually succeeded — before that the service still
     * reports `Uninitialized`, and landing on Home for a wallet the app does not
     * consider set up would put the user one relaunch away from signup again.
     */
    fun submitConfirmationPin(pin: String, onDone: () -> Unit) {
        val expected = firstPin
        if (expected == null) {
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
                wallet.setPin(pin)
                finish()
                onDone()
            } catch (e: WalletStorageException) {
                firstPin = null
                _uiState.value = _uiState.value.copy(
                    busy = false,
                    step = RestoreWalletStep.PinSet,
                    alert = SignupAlert(SignupStrings.ERROR, SignupStrings.MNEMONIC_SAVE_FAIL),
                )
            }
        }
    }

    /** Leave the arc. The caller navigates; this drops what the arc was holding. */
    fun finish() {
        firstPin = null
        _uiState.value = RestoreWalletUiState()
    }

    fun dismissAlert() {
        _uiState.value = _uiState.value.copy(alert = null)
    }

    private fun showAlert(title: String, message: String) {
        _uiState.value = _uiState.value.copy(alert = SignupAlert(title, message))
    }
}
