package com.bittr.android.feature.send

import com.bittr.android.core.common.TestID
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.common.destination.DestinationParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One alert button. Its position is its `alert.button.N` id; the first is the way out. */
data class SendAlertButton(val label: String, val onTap: () -> Unit = {})

/** @property tag the alert's own test id (`alert.amountMissing`, …) where iOS gives it one. */
data class SendAlert(
    val title: String,
    val message: String,
    val buttons: List<SendAlertButton>,
    val tag: String? = null,
)

/** Something the screen does outside itself. */
sealed interface SendEffect {
    data class OpenTransaction(val id: String) : SendEffect
    data object OpenLightningQuestion : SendEffect

    /** Swap & Pay: Lightning cannot cover [invoice], the on-chain balance can (`swapAndPayLightning`). */
    data class SwapAndPayInvoice(val invoice: String, val amountSats: Long) : SendEffect

    /** Swap & Pay: the on-chain balance cannot cover the payment, Lightning can (`swapAndPayOnchain`). */
    data class SwapAndPayAddress(val address: String, val amountSats: Long) : SendEffect
}

/**
 * The confirm page — `ConfirmSendViewController`'s values.
 *
 * @property vsize zero for Lightning, which has no fee tiers.
 * @property invoiceHasAmount a Lightning invoice that carries its own amount is paid as is.
 */
data class ConfirmState(
    val mode: SendMode,
    val addressOrInvoice: String,
    val displayedAddress: String,
    val amountSats: Long,
    val amountFiat: String?,
    val pricePerBitcoin: Double?,
    val fiatSymbol: String,
    val lightningFeesSats: Long? = null,
    val invoiceHasAmount: Boolean = false,
    val vsize: Long = 0,
    val fees: FeeEstimates? = null,
    val sendingMaximum: Boolean = false,
    val drainTotalSats: Long? = null,
    val selectedFee: FeeTier = FeeTier.Medium,
    val maxAvailableFeePerVb: Double? = null,
    val sending: Boolean = false,
) {
    /** `selectedFeeRatePerVb()`. */
    val selectedRate: Double
        get() {
            val estimates = fees ?: return 1.0
            return when (selectedFee) {
                FeeTier.High -> estimates.fastest
                FeeTier.Medium -> estimates.hour
                FeeTier.Low -> maxAvailableFeePerVb ?: estimates.economy
            }
        }

    fun feeFor(tier: FeeTier): Long {
        val estimates = fees ?: return 0
        val rate = when (tier) {
            FeeTier.High -> estimates.fastest
            FeeTier.Medium -> estimates.hour
            FeeTier.Low -> maxAvailableFeePerVb ?: estimates.economy
        }
        return SendMath.feeSats(rate, vsize)
    }
}

/** Everything the Send screen draws. */
data class SendUiState(
    val mode: SendMode = SendMode.Lightning,
    val toText: String = "",
    val amountText: String = "",
    val currency: AmountCurrency = AmountCurrency.Satoshis,
    val fiatCode: String,
    val available: String = SendMath.availableLabel(0),
    val availableLoading: Boolean = false,
    val nextLoading: Boolean = false,
    val confirm: ConfirmState? = null,
    val alert: SendAlert? = null,
) {
    /** `btcLabel`. */
    val currencyLabel: String
        get() = when (currency) {
            AmountCurrency.Satoshis -> SendStrings.SATS_LABEL
            AmountCurrency.Bitcoin -> SendStrings.BTC_LABEL
            AmountCurrency.Fiat -> fiatCode
        }

    /** `toLabel`: "Address and amount" or "Invoice and amount". */
    val toLabel: String get() = if (mode == SendMode.Onchain) SendStrings.ADDRESS_AND_AMOUNT else SendStrings.INVOICE_AND_AMOUNT

    val toPlaceholder: String get() = if (mode == SendMode.Onchain) SendStrings.ENTER_BITCOIN_ADDRESS else SendStrings.ENTER_INVOICE
}

/**
 * `SendViewController` and `ConfirmSendViewController`'s behaviour, without UIKit.
 *
 * Send opens on Instant. Switching to Regular quotes the most that can be sent on-chain
 * — waiting for the BDK scan first, behind the "Syncing" alert, if it has not finished.
 * Next validates the address and amount and moves to the confirm page; Send there
 * broadcasts and opens the new transaction, or shows the success alert if the wallet
 * has not seen it yet.
 *
 * Not ported yet, and said so rather than faked: LNURL / Lightning-address payments, and
 * the swap offered when one balance is short but the other would cover it.
 */
class SendController(
    private val source: SendSource,
    private val scope: CoroutineScope,
) {

    private val _state = MutableStateFlow(SendUiState(fiatCode = source.fiatCurrency().code))
    val state: StateFlow<SendUiState> = _state.asStateFlow()

    private val _effects = MutableSharedFlow<SendEffect>(extraBufferCapacity = 8)
    val effects: SharedFlow<SendEffect> = _effects.asSharedFlow()

    private var maxSendableOnchainSats: Long? = null
    private var didTapAvailable = false
    private var bitcoinQr = ""
    private var fees: FeeEstimates? = null
    private var availableJob: Job? = null
    private var readinessJob: Job? = null

    /** `viewDidLoad`: the label for the default type, and a refresh whenever balances move. */
    fun start() {
        refreshAvailable(quiet = true)
        scope.launch {
            source.walletUpdates.drop(1).collect {
                if (_state.value.confirm == null) refreshAvailable(quiet = true)
            }
        }
    }

    // ---- The send page. ----

    /** `switchTapped`. */
    fun onModeSelected(mode: SendMode) {
        if (mode == SendMode.Onchain && bitcoinQr.isNotEmpty()) {
            val address = bitcoinQr
            bitcoinQr = ""
            _state.update { it.copy(toText = address) }
        } else {
            resetFields()
        }
        _state.update { it.copy(mode = mode) }
        refreshAvailable()
    }

    fun onToChange(text: String) = _state.update { it.copy(toText = text) }

    fun onAmountChange(text: String) {
        didTapAvailable = false
        _state.update { it.copy(amountText = text) }
    }

    /**
     * `textFieldShouldReturn` for the address field: an invoice with an amount or an LNURL
     * goes straight on; anything else moves to the amount. Returns whether to focus the amount.
     */
    fun onToReturn(): Boolean {
        val entered = _state.value.toText.trim()
        val destination = DestinationParser.parse(entered, source.network)
        if (destination is Destination.Lnurl || SendMath.isLnurl(entered)) {
            _state.update { it.copy(mode = SendMode.Lightning) }
            refreshAvailable()
            checkLightning()
            return false
        }
        if (destination is Destination.Lightning && destination.amountSats != null) {
            _state.update { it.copy(mode = SendMode.Lightning) }
            refreshAvailable()
            checkLightning()
            return false
        }
        return true
    }

    /** `availableButtonTapped`: fill in the most that can be sent. */
    fun onAvailableTapped() {
        val current = _state.value
        val sats = if (current.mode == SendMode.Onchain) {
            didTapAvailable = true
            maxSendableOnchainSats ?: maxOf(source.onchainSpendableSats(), 0L)
        } else {
            source.lightningSendableSats()
        }
        _state.update { it.copy(currency = AmountCurrency.Satoshis, amountText = sats.toString()) }
    }

    /** `btcButtonTapped`: Cancel, Bitcoin, Satoshis, the fiat symbol. */
    fun onCurrencyButton() = raise(
        SendAlert(
            title = SendStrings.SELECT_CURRENCY,
            message = SendStrings.SELECT_CURRENCY_MESSAGE,
            buttons = listOf(
                SendAlertButton(SendStrings.CANCEL),
                SendAlertButton(SendStrings.BITCOIN) { selectCurrency(AmountCurrency.Bitcoin) },
                SendAlertButton(SendStrings.SATOSHIS) { selectCurrency(AmountCurrency.Satoshis) },
                SendAlertButton(source.fiatCurrency().symbol) { selectCurrency(AmountCurrency.Fiat) },
            ),
        ),
    )

    /** `switchQuestionTapped`. */
    fun onSwitchQuestion() = raise(okay(SendStrings.TRANSACTION_TYPE, SendMath.plain(SendStrings.TRANSACTION_TYPE_3)))

    /** `availableQuestionTapped`. */
    fun onAvailableQuestion() {
        if (_state.value.mode == SendMode.Lightning) {
            _effects.tryEmit(SendEffect.OpenLightningQuestion)
        } else {
            raise(okay(SendStrings.SEND_BITCOIN, SendStrings.MAXIMUM_ONCHAIN))
        }
    }

    /** `toPasteButtonTapped`. */
    fun onPaste(text: String?) {
        if (text != null) onDestination(DestinationParser.parse(text, source.network), text.trim())
    }

    /** `handleScannedOrPastedString`, fed by the scanner or by [onPaste]. */
    fun onDestination(destination: Destination, raw: String = "") {
        when (destination) {
            is Destination.Lnurl -> _state.update { it.copy(toText = destination.raw, mode = SendMode.Lightning) }
            is Destination.Lightning -> {
                val amount = destination.amountSats
                val fallback = destination.onChainFallback
                if (amount != null && amount > source.lightningSendableSats() && fallback != null) {
                    onDestination(fallback)
                    return
                }
                _state.update {
                    it.copy(
                        toText = destination.invoice,
                        mode = SendMode.Lightning,
                        amountText = amount?.toString() ?: it.amountText,
                        currency = if (amount != null) AmountCurrency.Satoshis else it.currency,
                    )
                }
                if (fallback != null) bitcoinQr = fallback.address
            }
            is Destination.OnChain -> _state.update {
                val amount = destination.amountSats?.takeIf { sats -> sats != 0L }
                it.copy(
                    toText = destination.address,
                    mode = SendMode.Onchain,
                    amountText = amount?.toString() ?: it.amountText,
                    currency = if (amount != null) AmountCurrency.Satoshis else it.currency,
                )
            }
            Destination.Unrecognised -> {
                _state.update { it.copy(toText = "", amountText = "") }
                raise(okay(SendStrings.NO_BITCOIN_ADDRESS_FOUND, SendStrings.PLEASE_SCAN))
                return
            }
        }
        refreshAvailable()
    }

    /** `nextButtonTapped`, and the amount field's Done. */
    fun onNext() {
        if (_state.value.nextLoading) return
        if (_state.value.mode == SendMode.Onchain) {
            if (!source.onchainReady()) onchainUnavailable(quiet = false) else checkOnchain()
        } else {
            checkLightning()
        }
    }

    // ---- The confirm page. ----

    /** `backButtonTapped`. */
    fun onBack() = _state.update { it.copy(confirm = null) }

    /** `feeButtonTapped` → `switchToFee`. */
    fun onFee(tier: FeeTier) {
        val confirm = _state.value.confirm ?: return
        if (confirm.sending || confirm.vsize <= 0) return
        switchToFee(confirm, tier)
    }

    /** `confirmButtonTapped`. */
    fun onConfirm() {
        val confirm = _state.value.confirm ?: return
        if (confirm.sending) return
        if (confirm.mode == SendMode.Lightning) {
            payLightning(confirm)
        } else if (confirm.maxAvailableFeePerVb != null && confirm.selectedFee == FeeTier.Low) {
            raise(
                SendAlert(
                    title = SendStrings.LOW_FEE,
                    message = SendStrings.LOW_FEE_2,
                    buttons = listOf(SendAlertButton(SendStrings.CHANGE_FEE), SendAlertButton(SendStrings.CONTINUE) { confirmOnchain() }),
                    tag = TestID.Alert.lowFee,
                ),
            )
        } else {
            confirmOnchain()
        }
    }

    /** `lightningFeesTapped`. */
    fun onLightningFeesQuestion() = raise(okay(SendStrings.ALERT_LIGHTNING_FEES, SendStrings.ALERT_LIGHTNING_FEES_2))

    /** A button on the current alert, by position. */
    fun onAlertButton(position: Int) {
        val button = _state.value.alert?.buttons?.getOrNull(position) ?: return
        _state.update { it.copy(alert = null) }
        button.onTap()
    }

    // ---- Internals. ----

    private fun selectCurrency(currency: AmountCurrency) = _state.update { it.copy(currency = currency) }

    /** `resetFields`. */
    private fun resetFields() {
        didTapAvailable = false
        _state.update { it.copy(toText = "", amountText = "") }
    }

    /** `setSendAllLabel`. */
    private fun refreshAvailable(quiet: Boolean = false) {
        if (_state.value.mode == SendMode.Lightning) {
            availableJob?.cancel()
            _state.update { it.copy(available = SendMath.availableLabel(source.lightningSendableSats()), availableLoading = false) }
            return
        }
        if (!source.onchainReady()) {
            onchainUnavailable(quiet)
            return
        }
        _state.update { it.copy(availableLoading = true) }
        availableJob?.cancel()
        availableJob = scope.launch {
            val estimates = fees ?: source.feeEstimates()?.also { fees = it }
            val spendable = maxOf(source.onchainSpendableSats(), 0L)
            val sendable = if (estimates == null) {
                spendable
            } else {
                (source.drainQuote(null, SendMath.wholeSatPerVb(estimates.hour))?.sendableSats ?: spendable)
                    .also { maxSendableOnchainSats = it }
            }
            _state.update { it.copy(available = SendMath.availableLabel(sendable), availableLoading = false) }
        }
    }

    /** `bdkWalletUnavailable`: the syncing alert, and a wait for the scan. */
    private fun onchainUnavailable(quiet: Boolean) {
        _state.update {
            it.copy(
                available = SendMath.availableLabel(0),
                availableLoading = true,
                alert = if (quiet) it.alert else okay(SendStrings.SYNCING, SendStrings.AWAITING_BDK_SYNC),
            )
        }
        if (readinessJob?.isActive == true) return
        readinessJob = scope.launch {
            if (source.awaitOnchainReady()) {
                if (_state.value.mode == SendMode.Onchain) refreshAvailable(quiet = true)
            } else {
                _state.update {
                    it.copy(availableLoading = false, alert = okay(SendStrings.ONCHAIN_SYNC_FAILED_TITLE, SendStrings.ONCHAIN_SYNC_FAILED))
                }
            }
        }
    }

    /** `checkSendOnchain`. */
    private fun checkOnchain() {
        val snapshot = _state.value
        val address = snapshot.toText.trim()
        if (address.isEmpty()) return raise(okay(SendStrings.OOPS, SendStrings.ENTER_BITCOIN_ADDRESS))

        val parsed = DestinationParser.parse(address, source.network)
        if (SendMath.isLnurl(address) || parsed is Destination.Lightning || parsed is Destination.Lnurl) {
            _state.update { it.copy(mode = SendMode.Lightning) }
            refreshAvailable()
            checkLightning()
            return
        }

        if (snapshot.amountText.isBlank()) return raise(okay(SendStrings.OOPS, SendStrings.ENTER_AMOUNT))

        _state.update { it.copy(nextLoading = true) }
        scope.launch {
            val price = source.fiatPricePerBitcoin()
            var sats = SendMath.parseSats(snapshot.amountText, snapshot.currency, price)
            if (sats == null) return@launch stopNext()
            if (sats <= 0) return@launch stopNext(okay(SendStrings.OOPS, SendStrings.ENTER_AMOUNT))
            val spendable = source.onchainSpendableSats()
            if (sats > spendable) {
                // `checkSendOnchain`: offer Swap & Pay when Lightning could cover it instead.
                val lightning = source.lightningSendableSats()
                val requested: Long = sats
                if (lightning >= requested) {
                    return@launch stopNext(
                        SendAlert(
                            title = SendStrings.INSUFFICIENT_FUNDS,
                            message = SendMath.plain(SendStrings.ONCHAIN_INSUFFICIENT_FUNDS).replace("<amount>", SendMath.group(spendable)) +
                                "\n\n" + SendMath.plain(SendStrings.SWAP_INSUFFICIENT_FUNDS_LIGHTNING).replace("<amount>", SendMath.group(lightning)),
                            buttons = listOf(
                                // `cancelSwapOffer` clears the amount.
                                SendAlertButton(SendStrings.CANCEL) { _state.update { it.copy(amountText = "") } },
                                SendAlertButton(SendStrings.SWAP_AND_PAY) { _effects.tryEmit(SendEffect.SwapAndPayAddress(address, requested)) },
                            ),
                        ),
                    )
                }
                return@launch stopNext(okay(SendStrings.OOPS, SendStrings.SPENDABLE_BALANCE))
            }

            val estimates = source.feeEstimates()
                ?: return@launch stopNext(okay(SendStrings.OOPS, "${SendStrings.CANNOT_PROCEED}. Error: Couldn't fetch recommended fees."))
            fees = estimates

            val drain = source.drainQuote(address, SendMath.wholeSatPerVb(estimates.hour))
            if (maxSendableOnchainSats != null && sats == maxSendableOnchainSats) didTapAvailable = true

            val sendingMaximum = drain != null && (didTapAvailable || sats >= drain.sendableSats)
            var drainTotal: Long? = null
            if (sendingMaximum && drain != null) {
                sats = drain.sendableSats
                drainTotal = drain.sendableSats + drain.feeSats
            }

            val vsize = if (sendingMaximum && drain != null) {
                drain.vsize
            } else {
                source.transactionVsize(address, sats, SendMath.wholeSatPerVb(estimates.hour)).getOrElse { failure ->
                    return@launch stopNext(okay(SendStrings.OOPS, failure.message ?: "${SendStrings.CANNOT_PROCEED}."))
                }
            }

            val symbol = source.fiatCurrency().symbol
            var confirm = ConfirmState(
                mode = SendMode.Onchain,
                addressOrInvoice = address,
                displayedAddress = address,
                amountSats = sats,
                amountFiat = SendMath.formattedFiat(sats, price, symbol),
                pricePerBitcoin = price,
                fiatSymbol = symbol,
                vsize = vsize,
                fees = estimates,
                sendingMaximum = sendingMaximum,
                drainTotalSats = drainTotal,
            )
            // Not even the cheapest tier fits: offer the most the balance can pay, as "Slow".
            val lowest = SendMath.feeSats(estimates.economy, vsize)
            val availableForFee = spendable - sats
            if (lowest > availableForFee) {
                val perVb = if (vsize > 0) availableForFee.toDouble() / vsize else 1.0
                confirm = confirm.copy(maxAvailableFeePerVb = maxOf(perVb, 1.0), selectedFee = FeeTier.Low)
            }
            _state.update { it.copy(nextLoading = false, confirm = confirm, amountText = if (sendingMaximum) sats.toString() else it.amountText) }
        }
    }

    /** `checkSendLightning`. */
    private fun checkLightning() {
        val snapshot = _state.value
        val entered = snapshot.toText.trim()
        if (entered.isEmpty()) return raise(okay(SendStrings.OOPS, SendStrings.ENTER_INVOICE))

        val destination = DestinationParser.parse(entered, source.network)
        if (destination is Destination.Lnurl || SendMath.isLnurl(entered)) {
            return raise(okay(SendStrings.OOPS, SendStrings.LNURL_NOT_ON_ANDROID))
        }

        when (destination) {
            is Destination.OnChain -> {
                _state.update { it.copy(toText = destination.address, mode = SendMode.Onchain) }
                refreshAvailable()
                if (source.onchainReady()) checkOnchain()
                return
            }
            is Destination.Lightning -> Unit
            else -> {
                val message = if (entered.lowercase().startsWith("lno")) SendStrings.BOLT12_NOT_SUPPORTED
                else SendStrings.INVALID_INVOICE_2.replace("<invoice>", entered)
                return raise(okay(SendStrings.OOPS, message))
            }
        }

        scope.launch {
            val price = source.fiatPricePerBitcoin()
            val invoiceAmount = destination.amountSats
            val sats = invoiceAmount ?: SendMath.parseSats(snapshot.amountText, snapshot.currency, price)?.takeIf { it > 0 }
            if (sats == null) {
                raise(
                    SendAlert(
                        title = SendStrings.INVOICE,
                        message = SendStrings.AMOUNT_MISSING,
                        buttons = listOf(SendAlertButton(SendStrings.OKAY)),
                        tag = TestID.Alert.amountMissing,
                    ),
                )
                return@launch
            }
            val sendable = source.lightningSendableSats()
            if (sats > sendable) {
                val lightningShort = SendMath.plain(SendStrings.LIGHTNING_INSUFFICIENT_FUNDS).replace("<amount>", SendMath.group(sendable))
                // `checkAvailableOnchainBalance`: offer Swap & Pay when the on-chain balance could cover it.
                val onchain = source.onchainSpendableSats()
                if (onchain >= sats) {
                    raise(
                        SendAlert(
                            title = SendStrings.INSUFFICIENT_FUNDS,
                            message = lightningShort + "\n\n" + SendMath.plain(SendStrings.SWAP_INSUFFICIENT_FUNDS).replace("<amount>", SendMath.group(onchain)),
                            buttons = listOf(
                                SendAlertButton(SendStrings.CANCEL),
                                SendAlertButton(SendStrings.SWAP_AND_PAY) { _effects.tryEmit(SendEffect.SwapAndPayInvoice(destination.invoice, sats)) },
                            ),
                        ),
                    )
                } else {
                    raise(okay(SendStrings.INSUFFICIENT_FUNDS, lightningShort))
                }
                return@launch
            }
            val symbol = source.fiatCurrency().symbol
            _state.update {
                it.copy(
                    amountText = sats.toString(),
                    currency = AmountCurrency.Satoshis,
                    confirm = ConfirmState(
                        mode = SendMode.Lightning,
                        addressOrInvoice = destination.invoice,
                        displayedAddress = destination.invoice,
                        amountSats = sats,
                        amountFiat = SendMath.formattedFiat(sats, price, symbol),
                        pricePerBitcoin = price,
                        fiatSymbol = symbol,
                        lightningFeesSats = SendMath.maxRoutingFeeSats(sats),
                        invoiceHasAmount = invoiceAmount != null,
                    ),
                )
            }
        }
    }

    private fun switchToFee(confirm: ConfirmState, tier: FeeTier) {
        var next = confirm.copy(selectedFee = tier)
        val feeInSats = next.feeFor(tier)
        if (next.sendingMaximum && next.drainTotalSats != null) {
            val amount = maxOf(next.drainTotalSats!! - feeInSats, 0L)
            next = next.copy(amountSats = amount, amountFiat = SendMath.formattedFiat(amount, next.pricePerBitcoin, next.fiatSymbol))
        }
        _state.update { it.copy(confirm = next) }

        // `canAffordFees`.
        val spendable = source.onchainSpendableSats()
        if (!next.sendingMaximum && feeInSats + next.amountSats > spendable) {
            raise(
                SendAlert(
                    title = SendStrings.BALANCE_2,
                    message = SendStrings.INSUFFICIENT_ONCHAIN_BALANCE.replace("<fee>", "$spendable sats"),
                    buttons = listOf(SendAlertButton(SendStrings.UPDATE_AMOUNT) { updateAmountToFit(feeInSats) }, SendAlertButton(SendStrings.CLOSE)),
                    tag = TestID.Alert.insufficientOnchainBalance,
                ),
            )
            return
        }
        // `checkHighFeeRate`.
        if (next.amountSats > 0 && feeInSats.toDouble() / next.amountSats > 0.1) {
            raise(okay(SendStrings.HIGH_FEE_RATE, SendStrings.HIGH_FEE_RATE_2))
        }
    }

    /** `handleAmountChange`: the spendable balance less the selected fee. */
    private fun updateAmountToFit(feeInSats: Long) {
        val confirm = _state.value.confirm ?: return
        val amount = maxOf(source.onchainSpendableSats() - feeInSats, 0L)
        val updated = confirm.copy(amountSats = amount, amountFiat = SendMath.formattedFiat(amount, confirm.pricePerBitcoin, confirm.fiatSymbol))
        _state.update {
            it.copy(
                confirm = updated,
                amountText = String.format(java.util.Locale.US, "%.8f", amount / 100_000_000.0),
                currency = AmountCurrency.Bitcoin,
            )
        }
        switchToFee(updated, updated.selectedFee)
    }

    /** `proceedWithOnchainConfirmation`. */
    private fun confirmOnchain() {
        val confirm = _state.value.confirm ?: return
        val fee = SendMath.feeSats(confirm.selectedRate, confirm.vsize)
        raise(
            SendAlert(
                title = SendStrings.SEND_TRANSACTION,
                message = SendMath.plain(SendStrings.SEND_CONFIRMATION)
                    .replace("<amount>", SendMath.group(confirm.amountSats))
                    .replace("<fees>", SendMath.group(fee))
                    .replace("<address>", confirm.addressOrInvoice),
                buttons = listOf(SendAlertButton(SendStrings.CANCEL), SendAlertButton(SendStrings.CONFIRM) { performOnchain() }),
            ),
        )
    }

    /** `performOnchainTransaction`. */
    private fun performOnchain() {
        val confirm = _state.value.confirm ?: return
        if (confirm.sending) return
        setSending(true)
        scope.launch {
            val result = source.sendOnchain(
                address = confirm.addressOrInvoice,
                amountSats = confirm.amountSats,
                satPerVb = SendMath.wholeSatPerVb(confirm.selectedRate),
                sendAll = confirm.sendingMaximum,
            )
            val txId = result.getOrElse { failure ->
                setSending(false)
                raise(
                    SendAlert(
                        title = SendStrings.ERROR,
                        message = "${SendStrings.TRANSACTION_ERROR}: ${failure.message}",
                        buttons = listOf(SendAlertButton(SendStrings.OKAY)),
                        tag = TestID.Alert.transactionError,
                    ),
                )
                return@launch
            }
            finishSend(txId)
        }
    }

    /** `performLightningPayment`. */
    private fun payLightning(confirm: ConfirmState) {
        setSending(true)
        scope.launch {
            val result = source.payInvoice(confirm.addressOrInvoice, if (confirm.invoiceHasAmount) null else confirm.amountSats)
            val paymentId = result.getOrElse { failure ->
                _state.update { it.copy(confirm = null) }
                raise(okay(SendStrings.UNEXPECTED_ERROR, SendStrings.FAILED_INVOICE_PAYMENT_1.replace("<message>", failure.message.orEmpty())))
                return@launch
            }
            finishSend(paymentId)
        }
    }

    /** `addNewPaymentToTable`, or the success alert when the wallet has not seen it yet. */
    private suspend fun finishSend(id: String) {
        val historyId = source.settledTransactionId(id)
        resetFields()
        _state.update { it.copy(confirm = null) }
        refreshAvailable(quiet = true)
        if (historyId != null) {
            _effects.emit(SendEffect.OpenTransaction(historyId))
        } else {
            raise(okay(SendStrings.SUCCESS, SendStrings.TRANSACTION_SUCCESS))
        }
    }

    private fun setSending(sending: Boolean) = _state.update { state ->
        state.copy(confirm = state.confirm?.copy(sending = sending))
    }

    private fun stopNext(alert: SendAlert? = null) {
        _state.update { it.copy(nextLoading = false, alert = alert ?: it.alert) }
    }

    private fun raise(alert: SendAlert) = _state.update { it.copy(alert = alert) }

    private fun okay(title: String, message: String) = SendAlert(title, message, listOf(SendAlertButton(SendStrings.OKAY)))
}
