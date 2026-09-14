package com.bittr.android.feature.receive

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
data class ReceiveAlert(val title: String, val message: String, val buttons: List<ReceiveAlertButton>)

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
 * then gather the address, amount and invoice and build the labels. A type change cancels
 * a load still in flight, so a slow invoice never overwrites the type the user moved to.
 */
class ReceiveController(
    private val source: ReceiveSource,
    private val scope: CoroutineScope,
) {

    private val _state = MutableStateFlow(ReceiveUiState(fiatCode = source.fiatCurrency().code))
    val state: StateFlow<ReceiveUiState> = _state.asStateFlow()

    private var loadJob: Job? = null

    /** `viewDidLoad`: open on the default type. */
    fun start() {
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
        loadJob?.cancel()
        loadJob = scope.launch {
            if (type.usesOnchainAddress && !newAddress && !source.addressesVerified.value) {
                // iOS waits for `onchainAddressesReady()` and gives up after eight seconds,
                // showing the best address it has.
                withTimeoutOrNull(ADDRESS_VERIFICATION_TIMEOUT_MS) { source.addressesVerified.first { it } }
            }
            load(type, newAddress)
        }
    }

    private suspend fun load(type: ReceiveType, newAddress: Boolean) {
        val snapshot = _state.value

        val next = if (type.usesOnchainAddress && newAddress) source.nextOnchainAddress() else null
        val noneLeft = type.usesOnchainAddress && newAddress && next == null
        val onchainAddress = if (type.usesOnchainAddress) {
            next ?: source.currentOnchainAddress() ?: ReceiveStrings.UNAVAILABLE
        } else {
            ""
        }

        val description = snapshot.descriptionText.trim()
        val price = if (snapshot.currency == ReceiveCurrency.Fiat) source.fiatPricePerBitcoin() else null
        val amountSats = parseAmountSats(snapshot.amountText, snapshot.currency, price)

        val invoice = if (type.usesInvoice) {
            val created = if (amountSats != null && amountSats > 0) {
                source.invoice(amountSats, description)
            } else {
                source.zeroAmountInvoice(description)
            }
            created ?: ReceiveStrings.UNAVAILABLE
        } else {
            ""
        }

        val display = receiveDisplay(
            type = type,
            onchainAddress = onchainAddress,
            invoice = invoice,
            lightningAddress = source.lightningAddress(),
            amountSats = amountSats,
            description = description,
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
     * `copyTapped`: raise the Copied alert and return what to put on the clipboard — the
     * clipboard itself is the screen's, since it needs a platform object.
     */
    fun onCopy(): String? {
        val text = _state.value.display?.copyText ?: return null
        raise(okayAlert(ReceiveStrings.COPIED, text))
        return text
    }

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

    /** `editTapped`: toggle the amount stack. Closing it clears both fields and does not reload. */
    fun onEdit() = _state.update {
        if (it.amountOpen) it.copy(amountOpen = false, amountText = "", descriptionText = "") else it.copy(amountOpen = true)
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

    fun onAmountChange(text: String) = _state.update { it.copy(amountText = text) }

    fun onDescriptionChange(text: String) = _state.update { it.copy(descriptionText = text) }

    /** `doneButtonTapped`: regenerate with what was entered. */
    fun onDone() = show(_state.value.type)

    /** A button on the current alert, by position. */
    fun onAlertButton(position: Int) {
        val button = _state.value.alert?.buttons?.getOrNull(position) ?: return
        _state.update { it.copy(alert = null) }
        when (val action = button.action) {
            ReceiveAction.Dismiss -> Unit
            is ReceiveAction.SelectType -> show(action.type)
            ReceiveAction.ConfirmNewAddress -> show(ReceiveType.Onchain, newAddress = true)
            is ReceiveAction.SelectCurrency -> _state.update { it.copy(currency = action.currency) }
        }
    }

    private fun raise(alert: ReceiveAlert) = _state.update { it.copy(alert = alert) }

    private fun okayAlert(title: String, message: String) =
        ReceiveAlert(title, message, listOf(ReceiveAlertButton(ReceiveStrings.OKAY, ReceiveAction.Dismiss)))

    companion object {
        /** `ReceiveViewController.swift:472` — `.now() + 8`. */
        const val ADDRESS_VERIFICATION_TIMEOUT_MS = 8_000L
    }
}
