package com.bittr.android.feature.buy

import com.bittr.android.core.common.TestID
import com.bittr.android.core.network.IbanEntity
import com.bittr.android.core.network.PaymentMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The five pages of `RegisterIbanViewController`, in its order. */
enum class SignupPage { Ready, Start, Otp, Success, TransferInfo }

data class SignupUiState(
    val page: SignupPage = SignupPage.Ready,
    /** `currentIbanID` — the entity being registered, once the IBAN page has saved one. */
    val entityId: String? = null,
    val iban: String = "",
    val email: String = "",
    val code: String = "",
    /** The Next button's spinner. */
    val busy: Boolean = false,
    /** The exclusive-initiative confirmation sheet. */
    val showInitiative: Boolean = false,
)

data class BuyUiState(
    /** The entities with a deposit code — the Buy cards. Empty shows `buyempty`. */
    val cards: List<IbanEntity> = emptyList(),
    /** `updateDataSpinner`. */
    val refreshing: Boolean = false,
    /** Cards whose payout-mode switch is in flight, with the value it was flipped to. */
    val pendingModes: Map<String, Boolean> = emptyMap(),
    /** The signup container, or null when Buy itself is showing. */
    val signup: SignupUiState? = null,
    val alert: BuyAlert? = null,
) {
    /** The switch position: the in-flight value, else ON unless the mode is `onchain`. */
    fun lightningOn(entity: IbanEntity): Boolean =
        pendingModes[entity.id] ?: (entity.paymentMode != PaymentMode.ONCHAIN)
}

/** What an alert button does. Carried as a value so the screen stays free of logic. */
enum class BuyAction {
    Dismiss,
    GoToWallet,
    ChangeEmail,
    RequestNotifications,
    CancelLoading,
    ContinueWithoutNotifications,

    /** `tokenregistrationfail`'s "Try again" — `askForPushNotifications()` once more. */
    RetryDeviceToken,
    BackToStart,
    FinishSignup,
}

data class BuyAlertButton(val label: String, val action: BuyAction)

/**
 * An in-screen alert. [id] goes on the card, as iOS's `showAlert(id:)` does; its buttons are
 * `alert.button.N` in order.
 */
data class BuyAlert(
    val title: String,
    val message: String,
    val buttons: List<BuyAlertButton> = listOf(BuyAlertButton(BuyStrings.OKAY, BuyAction.Dismiss)),
    val id: String? = null,
)

sealed interface BuyEffect {
    /** Launch the system POST_NOTIFICATIONS request; answer with [BuyController.onNotificationPermissionResult]. */
    data object RequestNotificationPermission : BuyEffect
}

/**
 * Buy (`BuyViewController`) and the bittr signup it opens (`RegisterIbanViewController` and its
 * five pages), as one state holder.
 *
 * iOS spreads this over six view controllers talking through `coreVC`; here the pages are states
 * of one controller because they share one thing that matters — the entity being registered — and
 * because a page reached by Back with half its state gone is a page that registers the wrong IBAN.
 */
class BuyController(
    private val source: BuySource,
    private val scope: CoroutineScope,
) {

    private val _state = MutableStateFlow(BuyUiState(cards = cardsOf(source.entities.value)))
    val state: StateFlow<BuyUiState> = _state.asStateFlow()

    private val _effects = MutableSharedFlow<BuyEffect>(extraBufferCapacity = 4)
    val effects: SharedFlow<BuyEffect> = _effects.asSharedFlow()

    /** The initiative confirmation given in this session, before an entity existed to hold it. */
    private var sessionInitiativeAt: String? = null
    private var hasAutoTriggered = false
    private var notificationsDenied = false

    /** The push token the registration carries — iOS's cached `registrationToken`. */
    private var deviceToken: String? = null
    private var resendAvailableAt = 0L
    private var started = false

    /** `viewDidLoad` → `parseIbanEntities(uponPageLaunch: true)`. */
    fun start() {
        if (started) return
        started = true
        scope.launch {
            source.entities.collect { entities -> _state.update { it.copy(cards = cardsOf(entities)) } }
        }
        if (_state.value.cards.isNotEmpty()) refreshDepositCodes()
    }

    private fun refreshDepositCodes() {
        _state.update { it.copy(refreshing = true) }
        scope.launch {
            val result = source.refreshDepositCodes()
            _state.update { it.copy(refreshing = false) }
            if (result == DepositRefresh.DetailsChanged) {
                showAlert(BuyAlert(BuyStrings.UPDATE_DETAILS, BuyStrings.UPDATE_DETAILS_2))
            }
        }
    }

    // ---- Buy cards. ----

    fun onPaymentModeQuestion() = showAlert(
        BuyAlert(BuyStrings.LIGHTNING, BuyStrings.LIGHTNING_EXPLANATION, id = TestID.Alert.lightningExplanation),
    )

    fun showCopied(value: String) = showAlert(BuyAlert(BuyStrings.COPIED, value, id = TestID.Alert.copied))

    /** `didChangePaymentModeSwitch` → `setPaymentMode`. */
    fun onPaymentModeToggled(entity: IbanEntity, lightningOn: Boolean) {
        if (entity.id in _state.value.pendingModes) return
        val mode = if (lightningOn) PaymentMode.LIGHTNING else PaymentMode.ONCHAIN
        if (mode == PaymentMode.LIGHTNING && !source.notificationsAuthorized()) {
            showAlert(BuyAlert(BuyStrings.RECEIVE_NOTIFICATIONS, BuyStrings.LIGHTNING_NEEDS_NOTIFICATIONS))
            return
        }
        _state.update { it.copy(pendingModes = it.pendingModes + (entity.id to lightningOn)) }
        scope.launch {
            val result = source.setPaymentMode(entity.id, mode)
            _state.update { it.copy(pendingModes = it.pendingModes - entity.id) }
            when (result) {
                is PaymentModeResult.Confirmed -> Unit
                PaymentModeResult.NotReady ->
                    showAlert(BuyAlert(BuyStrings.LIGHTNING_NOT_READY, BuyStrings.SYNCING_WALLET_2))
                is PaymentModeResult.Error ->
                    showAlert(BuyAlert(BuyStrings.PAYMENT_MODE_UPDATE_ERROR, result.message))
            }
        }
    }

    // ---- Signup: page 0, wallet ready. ----

    /** `continueButtonTapped` → `BuyToRegister`. */
    fun onStartSignup() {
        sessionInitiativeAt = null
        notificationsDenied = false
        deviceToken = null
        hasAutoTriggered = false
        _state.update { it.copy(signup = SignupUiState()) }
    }

    /**
     * Onboarding's "Your wallet is ready" → Continue (`Signup7ViewController.nextButtonTapped`,
     * `signupVC.moveToPage(10)`): straight to the IBAN page, the Ready page having been shown by
     * the create-wallet arc itself.
     */
    fun onStartSignupAtIban() {
        onStartSignup()
        onReadyNext()
    }

    fun onReadyNext() = updateSignup { it.copy(page = SignupPage.Start) }

    /** Back out of the signup container. */
    fun onCloseSignup() = _state.update { it.copy(signup = null) }

    // ---- Page 1, IBAN and email. ----

    fun onIbanChange(value: String) = updateSignup { it.copy(iban = value) }

    fun onEmailChange(value: String) = updateSignup { it.copy(email = value) }

    /** `updateButtonColor` — the Verify button is black only when this is true. */
    fun canVerify(signup: SignupUiState): Boolean =
        signup.iban.trim().isNotEmpty() && isValidEmail(signup.email.trim())

    /** `nextButtonTapped`. */
    fun onVerify() {
        val signup = _state.value.signup ?: return
        if (signup.busy) return
        if (!canVerify(signup)) {
            showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.TRANSFER_1_VC))
            return
        }
        if (recordedInitiativeConfirmation(signup) == null) {
            updateSignup { it.copy(showInitiative = true) }
        } else {
            gatherIbanDetails()
        }
    }

    fun onInitiativeConfirm() {
        sessionInitiativeAt = source.nowIsoUtc()
        updateSignup { it.copy(showInitiative = false) }
        gatherIbanDetails()
    }

    fun onInitiativeCancel() = updateSignup { it.copy(showInitiative = false) }

    /** "I don't have an IBAN". */
    fun onSkip() = showAlert(
        BuyAlert(
            title = BuyStrings.WERE_SORRY,
            message = BuyStrings.ONLY_IBAN,
            buttons = listOf(
                BuyAlertButton(BuyStrings.GO_TO_WALLET, BuyAction.GoToWallet),
                BuyAlertButton(BuyStrings.CANCEL, BuyAction.Dismiss),
            ),
            id = TestID.Alert.onlyIban,
        ),
    )

    private fun recordedInitiativeConfirmation(signup: SignupUiState): String? =
        signup.entityId
            ?.let { id -> source.entities.value.firstOrNull { it.id == id }?.initiativeConfirmedAt }
            ?.takeIf { it.isNotEmpty() }
            ?: sessionInitiativeAt

    private fun gatherIbanDetails() {
        val signup = _state.value.signup ?: return
        val email = signup.email.trim()
        val iban = signup.iban.trim().replace(" ", "")
        val id = source.saveIbanDetails(signup.entityId, email, iban, recordedInitiativeConfirmation(signup))
        updateSignup { it.copy(entityId = id, busy = true) }
        scope.launch {
            val result = source.verifyEmail(email, iban)
            updateSignup { it.copy(busy = false) }
            when (result) {
                VerifyEmailResult.Accepted -> {
                    hasAutoTriggered = false
                    updateSignup { it.copy(page = SignupPage.Otp, code = "") }
                }
                is VerifyEmailResult.Rejected -> showAlert(BuyAlert(BuyStrings.OOPS, result.message))
                VerifyEmailResult.Unreachable -> showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.BITTR_SIGNUP_FAIL_4))
            }
        }
    }

    // ---- Page 2, the code. ----

    /** `shouldChangeCharactersIn` / `textFieldDidChangeSelection`: auto-submit once at six. */
    fun onCodeChange(value: String) {
        updateSignup { it.copy(code = value) }
        val trimmed = value.trim()
        if (trimmed.length < 6) {
            hasAutoTriggered = false
        } else if (!hasAutoTriggered && _state.value.signup?.busy == false && _state.value.alert == null) {
            hasAutoTriggered = true
            onConfirmCode()
        }
    }

    /** `nextButtonTapped` on the code page. */
    fun onConfirmCode() {
        val signup = _state.value.signup ?: return
        if (signup.busy) return
        if (signup.code.trim().length <= 5) {
            showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.TRANSFER_15_VC))
            return
        }
        updateSignup { it.copy(busy = true) }
        checkPushNotificationStatus()
    }

    /**
     * `checkPushNotificationStatus()`. Authorised is not enough on its own: like iOS, the code is
     * only sent once there is a push token to register with, or once the user has chosen on-chain
     * payouts instead.
     */
    private fun checkPushNotificationStatus() {
        when {
            source.notificationsAuthorized() -> awaitDeviceToken()
            !source.notificationPermissionRequested() -> showAlert(
                BuyAlert(
                    title = BuyStrings.RECEIVE_NOTIFICATIONS,
                    message = BuyStrings.RECEIVE_NOTIFICATIONS_2,
                    buttons = listOf(BuyAlertButton(BuyStrings.OKAY, BuyAction.RequestNotifications)),
                    id = TestID.Alert.receiveNotificationsPrompt,
                ),
            )
            else -> showDeniedAlert()
        }
    }

    private fun showDeniedAlert() = showAlert(
        BuyAlert(
            title = BuyStrings.RECEIVE_NOTIFICATIONS,
            message = BuyStrings.RECEIVE_NOTIFICATIONS_3,
            buttons = listOf(
                BuyAlertButton(BuyStrings.CANCEL, BuyAction.CancelLoading),
                BuyAlertButton(BuyStrings.CONTINUE, BuyAction.ContinueWithoutNotifications),
            ),
            id = TestID.Alert.receiveNotificationsDenied,
        ),
    )

    /** The system dialog's answer. */
    fun onNotificationPermissionResult(granted: Boolean) {
        source.markNotificationPermissionRequested()
        if (granted) awaitDeviceToken() else showDeniedAlert()
    }

    /**
     * `registerForRemoteNotifications()` + `startTokenRegistrationTimeout()`: wait for the push
     * token (bounded inside [BuySource.deviceToken]), then send the code. No token halts the
     * signup with `tokenregistrationfail` — [Try again, Continue], Continue meaning on-chain
     * payouts — exactly as `tokenRegistrationFailed()` does.
     */
    private fun awaitDeviceToken() {
        updateSignup { it.copy(busy = true) }
        scope.launch {
            val token = source.deviceToken()
            if (token == null) {
                updateSignup { it.copy(busy = false) }
                showAlert(
                    BuyAlert(
                        title = BuyStrings.RECEIVE_NOTIFICATIONS,
                        message = BuyStrings.TOKEN_REGISTRATION_FAIL,
                        buttons = listOf(
                            BuyAlertButton(BuyStrings.TRY_AGAIN, BuyAction.RetryDeviceToken),
                            BuyAlertButton(BuyStrings.CONTINUE, BuyAction.ContinueWithoutNotifications),
                        ),
                    ),
                )
            } else {
                deviceToken = token
                sendCodeToBittr()
            }
        }
    }

    private fun sendCodeToBittr() {
        val signup = _state.value.signup ?: return
        val entityId = signup.entityId ?: return
        updateSignup { it.copy(busy = true) }
        scope.launch {
            when (val checked = source.checkCode(entityId, signup.code)) {
                is CheckCodeResult.Verified -> register(entityId, checked)
                CheckCodeResult.InvalidCode -> failCode(BuyStrings.VERIFICATION_FAIL)
                is CheckCodeResult.Error -> failCode(BuyStrings.codeError(checked.message))
                CheckCodeResult.Unreachable -> failCode(BuyStrings.VERIFICATION_FAIL)
            }
        }
    }

    private fun failCode(message: String) {
        updateSignup { it.copy(busy = false) }
        showAlert(BuyAlert(BuyStrings.OOPS, message))
    }

    private suspend fun register(entityId: String, verified: CheckCodeResult.Verified) {
        val result = source.register(
            entityId = entityId,
            notificationsDenied = notificationsDenied,
            deviceToken = deviceToken.takeUnless { notificationsDenied },
            restoreDepositCode = verified.restoreDepositCode,
            restoreMessage = verified.restoreMessage,
        )
        hasAutoTriggered = false
        // `codeTextField.text = nil` — createBittrAccount clears the code whatever the answer.
        updateSignup { it.copy(busy = false, code = "") }
        val backToStart = listOf(BuyAlertButton(BuyStrings.OKAY, BuyAction.BackToStart))
        when (result) {
            RegisterResult.Created -> updateSignup { it.copy(page = SignupPage.Success) }
            RegisterResult.InvalidIban ->
                showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.BITTR_SIGNUP_FAIL_2, backToStart))
            is RegisterResult.Message ->
                showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.signupFailed(result.message), backToStart))
            RegisterResult.WalletNotReady -> showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.SYNCING_WALLET_2))
            RegisterResult.SigningFailed -> showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.VERIFICATION_FAIL))
            RegisterResult.Unreachable -> showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.BITTR_SIGNUP_FAIL))
            RegisterResult.Unrecognised -> Unit
        }
    }

    /** `resendCodeButtonTapped` — at most one resend per 30 seconds. */
    fun onResendCode() {
        val signup = _state.value.signup ?: return
        val entity = signup.entityId?.let { id -> source.entities.value.firstOrNull { it.id == id } } ?: return
        val changeEmail = BuyAlertButton(BuyStrings.CHANGE_EMAIL, BuyAction.ChangeEmail)
        if (source.nowMillis() < resendAvailableAt) {
            showAlert(
                BuyAlert(
                    title = "",
                    message = BuyStrings.RESEND_CODE_2,
                    buttons = listOf(BuyAlertButton(BuyStrings.OKAY, BuyAction.Dismiss), changeEmail),
                    id = TestID.Alert.resendCode,
                ),
            )
            return
        }
        scope.launch {
            when (val result = source.verifyEmail(entity.yourEmail, entity.yourIbanNumber)) {
                VerifyEmailResult.Accepted -> {
                    resendAvailableAt = source.nowMillis() + RESEND_COOLDOWN_MS
                    showAlert(
                        BuyAlert(
                            title = BuyStrings.EMAIL_RESENT,
                            message = BuyStrings.emailResent(entity.yourEmail),
                            buttons = listOf(BuyAlertButton(BuyStrings.OKAY, BuyAction.Dismiss), changeEmail),
                        ),
                    )
                }
                is VerifyEmailResult.Rejected -> showAlert(BuyAlert(BuyStrings.OOPS, result.message))
                VerifyEmailResult.Unreachable -> showAlert(BuyAlert(BuyStrings.OOPS, BuyStrings.BITTR_SIGNUP_FAIL_4))
            }
        }
    }

    // ---- Pages 3 and 4. ----

    /** The entity being registered, for the success page's partner details. */
    fun signupEntity(): IbanEntity? =
        _state.value.signup?.entityId?.let { id -> source.entities.value.firstOrNull { it.id == id } }

    fun onSuccessNext() = updateSignup { it.copy(page = SignupPage.TransferInfo) }

    fun onTransferInfoBack() = updateSignup { it.copy(page = SignupPage.Success) }

    fun onScreenshotResult(saved: Boolean) = showAlert(
        if (saved) BuyAlert(BuyStrings.SAVED, BuyStrings.SCREENSHOT_2) else BuyAlert(BuyStrings.OOPS, BuyStrings.SCREENSHOT_3),
    )

    /** "Let's go" — `bankingapp`, whose Done closes the signup. */
    fun onLetsGo() {
        val entity = signupEntity() ?: return
        showAlert(
            BuyAlert(
                title = BuyStrings.BANKING_APP,
                message = BuyStrings.bankingApp(entity.ourIbanNumber, entity.ourName, entity.yourUniqueCode),
                buttons = listOf(BuyAlertButton(BuyStrings.DONE, BuyAction.FinishSignup)),
            ),
        )
    }

    // ---- Alerts. ----

    fun onAlertAction(action: BuyAction) {
        _state.update { it.copy(alert = null) }
        when (action) {
            BuyAction.Dismiss -> Unit
            BuyAction.GoToWallet, BuyAction.FinishSignup -> onCloseSignup()
            BuyAction.ChangeEmail, BuyAction.BackToStart -> updateSignup { it.copy(page = SignupPage.Start, busy = false) }
            BuyAction.RequestNotifications -> _effects.tryEmit(BuyEffect.RequestNotificationPermission)
            BuyAction.CancelLoading -> updateSignup { it.copy(busy = false) }
            BuyAction.ContinueWithoutNotifications -> {
                notificationsDenied = true
                deviceToken = null
                sendCodeToBittr()
            }
            BuyAction.RetryDeviceToken -> {
                updateSignup { it.copy(busy = true) }
                checkPushNotificationStatus()
            }
        }
    }

    private fun showAlert(alert: BuyAlert) = _state.update { it.copy(alert = alert) }

    private fun updateSignup(transform: (SignupUiState) -> SignupUiState) =
        _state.update { state -> state.signup?.let { state.copy(signup = transform(it)) } ?: state }

    companion object {
        const val RESEND_COOLDOWN_MS = 30_000L

        private val EMAIL = Regex("[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")

        /** `String.isValidEmail()` — the same pattern, matched against the whole string. */
        fun isValidEmail(value: String): Boolean = EMAIL.matches(value)

        private fun cardsOf(entities: List<IbanEntity>) = entities.filter { it.hasDepositCode }
    }
}
