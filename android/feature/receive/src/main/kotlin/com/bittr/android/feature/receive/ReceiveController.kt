package com.bittr.android.feature.receive

import com.bittr.android.core.designsystem.SYSTEM_CONFIRMS_COPY
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** What a button on a [ReceiveAlert] does once tapped. */
sealed interface ReceiveAction {
    data object Dismiss : ReceiveAction
    data class SelectType(val type: ReceiveType) : ReceiveAction
    data object ConfirmNewAddress : ReceiveAction
    data class SelectCurrency(val currency: ReceiveCurrency) : ReceiveAction
}

/** One alert button. Its position in [ReceiveAlert.buttons] is its `alert.button.N` id. */
data class ReceiveAlertButton(val label: String, val action: ReceiveAction)

/** An alert. The first button is always the way out, as on iOS. */
data class ReceiveAlert(
    val title: String,
    val message: String,
    val buttons: List<ReceiveAlertButton>,
    /** The message is a value (the copied invoice), not a sentence — see `BittrDialogValue`. */
    val messageIsValue: Boolean = false,
)

/**
 * Everything the Receive screen draws.
 *
 * @property loading `receive.qrSpinner` is on screen; the labels and QR are stale.
 */
data class ReceiveUiState(
    val type: ReceiveType = ReceiveType.Onchain,
    val loading: Boolean = true,
    val display: ReceiveDisplay? = null,
    val cards: ReceiveCards = ReceiveCards.forType(ReceiveType.Onchain, hasChannel = false),
    val amountOpen: Boolean = false,
    val amountText: String = "",
    val descriptionText: String = "",
    val currency: ReceiveCurrency = ReceiveCurrency.Satoshis,
    // No default: the code always comes from the user's chosen currency, and a euro
    // default is what CurrencyDefaultGuardTest exists to keep out of the port.
    val fiatCode: String,
    val alert: ReceiveAlert? = null,
) {

    /** `btcLabel` — `receive.currencyLabel`. */
    val currencyLabel: String
        get() = when (currency) {
            ReceiveCurrency.Satoshis -> ReceiveStrings.SATS_LABEL
            ReceiveCurrency.Bitcoin -> ReceiveStrings.BTC_LABEL
            ReceiveCurrency.Fiat -> fiatCode
        }

    /** The description field only belongs to types with an invoice (`showAmountStack`). */
    val showsDescription: Boolean get() = type != ReceiveType.Onchain
}

/**
 * `ReceiveViewController`'s behaviour, without UIKit.
 *
 * The sequence is iOS's `alertTapped(for:newAddress:)`: reset the labels behind a spinner,
 * wait for the address pool if the type needs an address and the pool is still verifying,
 * then gather the address, amount and invoice and build the labels. Every load cancels the
 * one still in flight, so a slow invoice never overwrites what the user moved on to.
 */
class ReceiveController(
    private val source: ReceiveSource,
    private val scope: CoroutineScope,
    /** See [SYSTEM_CONFIRMS_COPY]: below Android 13 the app says "Copied" itself. */
    private val confirmsCopyInApp: Boolean = !SYSTEM_CONFIRMS_COPY,
) {

    private val _state = MutableStateFlow(ReceiveUiState(fiatCode = source.fiatCurrency().code))
    val state: StateFlow<ReceiveUiState> = _state.asStateFlow()

    private var loadJob: Job? = null
    private var started = false

    /** What the shown code was made from, so that any change to it makes the code again. */
    private var codeInputs: ReceiveInputs? = null

    /**
     * `viewDidLoad`: open on the default type. Once: the controller outlives the screen's
     * composition, which runs this again when the app comes back to it.
     */
    fun start() {
        if (started) return
        started = true
        show(ReceiveType.default(source.lightningAvailable(), source.lightningAddress()))
    }

    /** `alertTapped(for:newAddress:)`. */
    fun show(type: ReceiveType, newAddress: Boolean = false) {
        val hasChannel = source.lightningAvailable()
        _state.update { current ->
            val typeChanged = type != current.type
            current.copy(
                type = type,
                loading = true,
                cards = ReceiveCards.forType(type, hasChannel),
                // `hideAmountStack()` on a type change, which also clears both fields.
                amountOpen = if (typeChanged) false else current.amountOpen,
                amountText = if (typeChanged) "" else current.amountText,
                descriptionText = if (typeChanged) "" else current.descriptionText,
            )
        }
        // Read once, here, so the code is made from exactly the inputs it is compared with later.
        val inputs = currentInputs()
        codeInputs = inputs
        loadJob?.cancel()
        loadJob = scope.launch {
            if (type.usesOnchainAddress && !newAddress && !source.addressesVerified.value) {
                // iOS waits for `onchainAddressesReady()` and gives up after eight seconds,
                // showing the best address it has, and stops waiting for good.
                val ready = withTimeoutOrNull(ADDRESS_VERIFICATION_TIMEOUT_MS) { source.addressesVerified.first { it } }
                if (ready == null) source.stopWaitingForAddresses()
            }
            load(type, newAddress, inputs)
        }
    }

    private suspend fun load(type: ReceiveType, newAddress: Boolean, inputs: ReceiveInputs) {
        val next = if (type.usesOnchainAddress && newAddress) source.nextOnchainAddress() else null
        val noneLeft = type.usesOnchainAddress && newAddress && next == null
        val onchainAddress = if (type.usesOnchainAddress) next ?: source.currentOnchainAddress() else null

        val description = inputs.description
        val price = if (inputs.currency == ReceiveCurrency.Fiat) source.fiatPricePerBitcoin() else null
        val amountSats = inputs.currency?.let { parseAmountSats(inputs.amount, it, price) }
        val amountInvalid = inputs.currency != null && amountSats == null

        val invoice = when {
            !type.usesInvoice || amountInvalid -> null
            amountSats != null && amountSats > 0 -> source.invoice(amountSats, description)
            else -> source.zeroAmountInvoice(description)
        }

        val display = receiveDisplay(
            type = type,
            onchainAddress = onchainAddress,
            invoice = invoice,
            lightningAddress = source.lightningAddress(),
            amountSats = amountSats,
            description = description,
            amountInvalid = amountInvalid,
        )

        _state.update {
            it.copy(
                loading = false,
                display = display,
                alert = if (noneLeft) okayAlert(ReceiveStrings.ADDRESS, ReceiveStrings.NO_ADDRESS_AVAILABLE) else it.alert,
            )
        }
    }

    /** `moreTapped`: Cancel, Address, Bitcoin QR, Invoice, Lightning address. */
    fun onMore() = raise(
        ReceiveAlert(
            title = ReceiveStrings.TRANSACTION_TYPE,
            message = ReceiveStrings.SELECT_TRANSACTION_TYPE,
            buttons = listOf(
                ReceiveAlertButton(ReceiveStrings.CANCEL, ReceiveAction.Dismiss),
                ReceiveAlertButton(ReceiveStrings.GET_ADDRESS, ReceiveAction.SelectType(ReceiveType.Onchain)),
                ReceiveAlertButton(ReceiveStrings.GET_BITCOIN_QR, ReceiveAction.SelectType(ReceiveType.BitcoinQr)),
                ReceiveAlertButton(ReceiveStrings.CREATE_INVOICE, ReceiveAction.SelectType(ReceiveType.Lightning)),
                ReceiveAlertButton(ReceiveStrings.SHOW_LNURL, ReceiveAction.SelectType(ReceiveType.Lnurl)),
            ),
        ),
    )

    /** `questionButtonTapped`. */
    fun onQuestion() {
        val (title, message) = when (_state.value.type) {
            ReceiveType.Onchain -> ReceiveStrings.ADDRESS to ReceiveStrings.ALERT_MESSAGE_ONCHAIN
            ReceiveType.Lightning -> ReceiveStrings.INVOICE to ReceiveStrings.ALERT_MESSAGE_LIGHTNING
            ReceiveType.BitcoinQr -> ReceiveStrings.BITCOIN_QR to ReceiveStrings.ALERT_MESSAGE_BITCOIN_QR
            ReceiveType.Lnurl -> ReceiveStrings.LIGHTNING_ADDRESS to ReceiveStrings.ALERT_MESSAGE_LNURL
        }
        raise(okayAlert(title, message))
    }

    /**
     * `copyTapped`: return what to put on the clipboard — the clipboard itself is the
     * screen's, since it needs a platform object — and say "Copied" where the system does
     * not ([confirmsCopyInApp]). Nothing while a new code loads.
     */
    fun onCopy(): String? {
        val text = onShare() ?: return null
        if (confirmsCopyInApp) raise(okayAlert(ReceiveStrings.COPIED, text).copy(messageIsValue = true))
        return text
    }

    /**
     * What the QR's Share hands to the share sheet: the copy text, and nothing while a new code loads
     * or while the fields hold an edit the code does not have yet.
     */
    fun onShare(): String? = _state.value.takeUnless { it.loading || currentInputs() != codeInputs }?.display?.copyText

    /** `refreshTapped`: confirm before revealing a new address. */
    fun onRefresh() = raise(
        ReceiveAlert(
            title = ReceiveStrings.NEW_ADDRESS,
            message = ReceiveStrings.NEW_ADDRESS_2,
            buttons = listOf(
                ReceiveAlertButton(ReceiveStrings.CANCEL, ReceiveAction.Dismiss),
                ReceiveAlertButton(ReceiveStrings.CONFIRM, ReceiveAction.ConfirmNewAddress),
            ),
        ),
    )

    /**
     * `editTapped`: toggle the amount stack. Closing it clears both fields, so a code made with an
     * amount or a description is made again without them.
     */
    fun onEdit() {
        val closing = _state.value.amountOpen
        _state.update {
            if (closing) it.copy(amountOpen = false, amountText = "", descriptionText = "") else it.copy(amountOpen = true)
        }
        if (closing) makeCodeAgainIfInputsChanged()
    }

    /** `btcButtonTapped`: Cancel, the fiat symbol, Satoshis, Bitcoin. */
    fun onCurrencyButton() = raise(
        ReceiveAlert(
            title = ReceiveStrings.SELECT_CURRENCY,
            message = ReceiveStrings.SELECT_CURRENCY_MESSAGE,
            buttons = listOf(
                ReceiveAlertButton(ReceiveStrings.CANCEL, ReceiveAction.Dismiss),
                ReceiveAlertButton(source.fiatCurrency().symbol, ReceiveAction.SelectCurrency(ReceiveCurrency.Fiat)),
                ReceiveAlertButton(ReceiveStrings.SATOSHIS, ReceiveAction.SelectCurrency(ReceiveCurrency.Satoshis)),
                ReceiveAlertButton(ReceiveStrings.BITCOIN, ReceiveAction.SelectCurrency(ReceiveCurrency.Bitcoin)),
            ),
        ),
    )

    /**
     * Spaces go; anything else stays — a separator in satoshis, which a paste or a hardware
     * keyboard can bring, a `-` or a second separator — for Done to refuse with an explanation.
     */
    fun onAmountChange(text: String) = _state.update { it.copy(amountText = text.filterNot(Char::isWhitespace)) }

    /** Counted in bytes, which is what the description costs in the Bitcoin QR, so that code always fits. */
    fun onDescriptionChange(text: String) {
        if (text.toByteArray(Charsets.UTF_8).size <= MAX_DESCRIPTION_BYTES) _state.update { it.copy(descriptionText = text) }
    }

    /** `doneButtonTapped`: make the code with what was entered, and say so when it is not an amount. */
    fun onDone() {
        if (!isWellFormedAmount(_state.value.amountText, _state.value.currency)) raise(okayAlert(ReceiveStrings.OOPS, ReceiveStrings.ENTER_VALID_AMOUNT))
        makeCodeAgainIfInputsChanged()
    }

    /** `textFieldDidEndEditing`: a field let go of the keyboard, however it happened. */
    fun onEditingEnded() = makeCodeAgainIfInputsChanged()

    private fun currentInputs(): ReceiveInputs = _state.value.let {
        val amount = it.amountText.trim()
        ReceiveInputs(amount = amount, description = it.descriptionText.trim(), currency = it.currency.takeIf { amount.isNotEmpty() })
    }

    private fun makeCodeAgainIfInputsChanged() {
        if (currentInputs() != codeInputs) show(_state.value.type)
    }

    /** A button on the current alert, by position. */
    fun onAlertButton(position: Int) {
        val button = _state.value.alert?.buttons?.getOrNull(position) ?: return
        _state.update { it.copy(alert = null) }
        when (val action = button.action) {
            ReceiveAction.Dismiss -> Unit
            is ReceiveAction.SelectType -> show(action.type)
            ReceiveAction.ConfirmNewAddress -> show(ReceiveType.Onchain, newAddress = true)
            is ReceiveAction.SelectCurrency -> {
                // The entered number keeps its digits and now counts in the new unit, as on Send.
                _state.update { it.copy(currency = action.currency) }
                makeCodeAgainIfInputsChanged()
            }
        }
    }

    private fun raise(alert: ReceiveAlert) = _state.update { it.copy(alert = alert) }

    private fun okayAlert(title: String, message: String) =
        ReceiveAlert(title, message, listOf(ReceiveAlertButton(ReceiveStrings.OKAY, ReceiveAction.Dismiss)))

    companion object {
        /** `ReceiveViewController.swift:472` — `.now() + 8`. */
        const val ADDRESS_VERIFICATION_TIMEOUT_MS = 8_000L

        /** The description field's limit on iOS. */
        const val MAX_DESCRIPTION_BYTES = 100
    }
}

/** The amount, description and, with an amount, currency a code was made from. */
private data class ReceiveInputs(val amount: String, val description: String, val currency: ReceiveCurrency?)
