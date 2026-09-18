package com.bittr.android.feature.swap

import com.bittr.android.core.swaps.BoltzStatus
import com.bittr.android.core.swaps.SwapAlert
import com.bittr.android.core.swaps.SwapAmounts
import com.bittr.android.core.swaps.SwapCopy
import com.bittr.android.core.swaps.SwapCoordinator
import com.bittr.android.core.swaps.SwapDirection
import com.bittr.android.core.swaps.SwapEvent
import com.bittr.android.core.swaps.SwapPreparation
import com.bittr.android.core.swaps.SwapRequest
import com.bittr.android.core.swaps.SwapStatusState
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The display currency, for the fees alert's fiat figures. `:app` implements it. */
interface SwapFiat {
    fun currencyCode(): String
    suspend fun pricePerBitcoin(): Double?
}

/**
 * How the swap screen was opened. Empty for the Move screen's swap button.
 *
 * @property invoice Swap & Pay from Send: the invoice to pay with an onchain-to-lightning swap.
 * @property payoutAddress Swap & Pay from Send: where a lightning-to-onchain swap pays out.
 * @property boltzId an existing swap's status card.
 * @property payoutSwapSats "Swap & Instant Receive" on a channel-full payout (iOS
 *   `pendingOnchainAmount` → `handleNotificationSwap`): a lightning-to-onchain swap of this amount,
 *   started straight away.
 */
data class SwapLaunch(
    val invoice: String? = null,
    val invoiceAmountSats: Long? = null,
    val payoutAddress: String? = null,
    val payoutAmountSats: Long? = null,
    val boltzId: String? = null,
    val payoutSwapSats: Long? = null,
)

data class SwapUiButton(val label: String, val onClick: () -> Unit)

data class SwapUiAlert(val title: String, val message: String, val buttons: List<SwapUiButton>, val tag: String? = null)

data class SwapUiState(
    val amountText: String = "",
    /** iOS opens on lightning-to-onchain (`swapDirection = .lightningToOnchain`). */
    val direction: SwapDirection = SwapDirection.LightningToOnchain,
    val available: String = movable(0),
    val availableLoading: Boolean = false,
    val nextLoading: Boolean = false,
    val alert: SwapUiAlert? = null,
    /** The status card, once a swap is under way. */
    val status: SwapStatusState? = null,
) {
    val directionLabel: String get() = direction.label()
}

internal fun SwapDirection.label(): String =
    if (this == SwapDirection.OnchainToLightning) SwapCopy.ONCHAIN_TO_LIGHTNING else SwapCopy.LIGHTNING_TO_ONCHAIN

internal fun movable(sats: Long): String = SwapCopy.SATS_AT_A_TIME.replace("<amount>", SwapAmounts.group(sats))

sealed interface SwapUiEffect {
    data class OpenTransaction(val id: String) : SwapUiEffect
    data object RequestNotifications : SwapUiEffect
    data class ShareFile(val file: File) : SwapUiEffect
}

/**
 * `SwapViewController` and `SwapStatusViewController`'s screen logic, over [SwapCoordinator].
 */
class SwapController(
    private val coordinator: SwapCoordinator,
    private val fiat: SwapFiat,
    private val scope: CoroutineScope,
    private val launch: SwapLaunch = SwapLaunch(),
) {
    private val _state = MutableStateFlow(SwapUiState())
    val state: StateFlow<SwapUiState> = _state.asStateFlow()

    private val _effects = MutableSharedFlow<SwapUiEffect>(extraBufferCapacity = 8)
    val effects: SharedFlow<SwapUiEffect> = _effects.asSharedFlow()

    private var maxOnchainToLightning: Long? = null
    private var maxLightningToOnchain: Long? = null
    private var limitJob: Job? = null
    private var statusJob: Job? = null
    private var started = false

    fun start() {
        if (started) return
        started = true
        scope.launch { coordinator.events.collect(::onEvent) }
        when {
            launch.boltzId != null -> coordinator.statusOf(launch.boltzId)?.let(::watch)
            launch.invoice != null -> startSuggested(SwapDirection.OnchainToLightning, launch.invoiceAmountSats ?: 0) {
                SwapRequest(SwapDirection.OnchainToLightning, it, existingInvoice = launch.invoice, suggested = true)
            }
            launch.payoutAddress != null -> startSuggested(SwapDirection.LightningToOnchain, launch.payoutAmountSats ?: 0) {
                SwapRequest(SwapDirection.LightningToOnchain, it, payoutAddress = launch.payoutAddress, suggested = true)
            }
            // `handleNotificationSwap`: not a suggested swap — `lightningToOnchain(payoutAddress: nil)`.
            launch.payoutSwapSats != null && launch.payoutSwapSats > 0 ->
                startSuggested(SwapDirection.LightningToOnchain, launch.payoutSwapSats) {
                    SwapRequest(SwapDirection.LightningToOnchain, it)
                }
            else -> refreshLimit()
        }
    }

    fun onAmountChange(text: String) {
        _state.update { it.copy(amountText = text.filter(Char::isDigit)) }
    }

    /** `fromButtonTapped` → `switchDirection()`: [Cancel, Onchain to Lightning, Lightning to Onchain]. */
    fun onDirectionTapped() {
        show(
            SwapUiAlert(
                SwapCopy.SWAP_FUNDS_HEADER,
                SwapCopy.SWAP_DIRECTION,
                listOf(
                    SwapUiButton(SwapCopy.CANCEL) { dismissAlert() },
                    SwapUiButton(SwapCopy.ONCHAIN_TO_LIGHTNING) { setDirection(SwapDirection.OnchainToLightning) },
                    SwapUiButton(SwapCopy.LIGHTNING_TO_ONCHAIN) { setDirection(SwapDirection.LightningToOnchain) },
                ),
            ),
        )
    }

    fun onAvailableQuestion() = okay(SwapCopy.LIMIT_LIGHTNING, SwapCopy.LIMIT_LIGHTNING_ANSWER)

    fun onBoltzTapped() = okay(SwapCopy.BOLTZ_EXPLANATION_TITLE, SwapCopy.BOLTZ_EXPLANATION)

    /** `nextTapped`. */
    fun onNext() {
        val snapshot = _state.value
        if (snapshot.nextLoading) return
        val amount = snapshot.amountText.toLongOrNull()
        if (amount == null || amount <= 0) return okay(SwapCopy.SWAP_FUNDS, SwapCopy.ENTER_AMOUNT_OF_SATOSHIS)
        _state.update { it.copy(nextLoading = true) }
        scope.launch {
            handle(coordinator.prepare(SwapRequest(snapshot.direction, amount, maxOnchainToLightning, maxLightningToOnchain)))
        }
    }

    fun onRefresh() {
        _state.value.status?.swap?.boltzId?.let(coordinator::refresh)
    }

    fun onStatusQuestion() {
        val status = _state.value.status ?: return
        okay(SwapCopy.SWAP_QUESTION, BoltzStatus.answer(status.lastStatus, status.swap.direction))
    }

    fun onDownload() {
        val id = _state.value.status?.swap?.boltzId ?: return
        coordinator.swapFile(id)?.let { _effects.tryEmit(SwapUiEffect.ShareFile(it)) }
    }

    fun dismissAlert() {
        _state.update { it.copy(alert = null) }
    }

    private fun setDirection(direction: SwapDirection) {
        _state.update { it.copy(direction = direction, alert = null) }
        refreshLimit()
    }

    /** `calculateSendableAmount`, waiting out the on-chain scan the way `bdkWalletUnavailable` does. */
    private fun refreshLimit() {
        limitJob?.cancel()
        val direction = _state.value.direction
        _state.update { it.copy(available = movable(0), availableLoading = true) }
        limitJob = scope.launch {
            var limit = coordinator.limit(direction)
            if (limit.needsOnchainSync) {
                okay(SwapCopy.SYNCING, SwapCopy.AWAITING_BDK_SYNC)
                if (!coordinator.awaitOnchainReady()) {
                    _state.update { it.copy(availableLoading = false) }
                    return@launch
                }
                limit = coordinator.limit(direction)
            }
            if (direction == SwapDirection.OnchainToLightning) maxOnchainToLightning = limit.maxSats else maxLightningToOnchain = limit.maxSats
            if (_state.value.direction == direction) {
                _state.update { it.copy(available = movable(limit.maxSats), availableLoading = false) }
            }
        }
    }

    /** `handlePendingLightningInvoice` / `handlePendingOnchainPayment`: straight into the swap. */
    private fun startSuggested(direction: SwapDirection, amount: Long, request: (Long) -> SwapRequest) {
        _state.update { it.copy(direction = direction, amountText = if (amount > 0) amount.toString() else "", nextLoading = true) }
        refreshLimit()
        scope.launch {
            if (direction == SwapDirection.OnchainToLightning && !coordinator.onchainReady() && !coordinator.awaitOnchainReady()) {
                _state.update { it.copy(nextLoading = false) }
                return@launch
            }
            handle(coordinator.prepare(request(amount)))
        }
    }

    private suspend fun handle(preparation: SwapPreparation) {
        _state.update { it.copy(nextLoading = false) }
        when (preparation) {
            is SwapPreparation.Refused -> show(preparation.alert.toUi())
            is SwapPreparation.Ready -> {
                val message = coordinator.feesMessage(preparation.swap, fiat.currencyCode(), fiat.pricePerBitcoin())
                show(
                    SwapUiAlert(
                        SwapCopy.SWAP_FUNDS,
                        message,
                        listOf(
                            // `cancelSwapFromFeesAlert` → `clearPendingSwapData`.
                            SwapUiButton(SwapCopy.CANCEL) { _state.update { it.copy(alert = null, amountText = "") } },
                            SwapUiButton(SwapCopy.PROCEED) {
                                dismissAlert()
                                coordinator.proceed(preparation)?.let(::watch)
                            },
                        ),
                    ),
                )
            }
        }
    }

    private fun watch(status: StateFlow<SwapStatusState>) {
        statusJob?.cancel()
        statusJob = scope.launch { status.collect { card -> _state.update { it.copy(status = card) } } }
    }

    private fun onEvent(event: SwapEvent) {
        when (event) {
            is SwapEvent.Alert -> {
                val current = _state.value.status?.swap?.boltzId
                if (event.boltzId == null || current == null || event.boltzId == current) show(event.alert.toUi())
            }
            is SwapEvent.OpenTransaction -> _effects.tryEmit(SwapUiEffect.OpenTransaction(event.transactionId))
            is SwapEvent.ShowSwap -> if (_state.value.status?.swap?.boltzId != event.boltzId) coordinator.statusOf(event.boltzId)?.let(::watch)
        }
    }

    private fun SwapAlert.toUi() = SwapUiAlert(
        title = title,
        message = message,
        buttons = listOf(
            SwapUiButton(SwapCopy.OKAY) {
                dismissAlert()
                if (requestsNotifications) _effects.tryEmit(SwapUiEffect.RequestNotifications)
            },
        ),
        tag = testTag,
    )

    private fun okay(title: String, message: String) = show(SwapUiAlert(title, message, listOf(SwapUiButton(SwapCopy.OKAY) { dismissAlert() })))

    private fun show(alert: SwapUiAlert) {
        _state.update { it.copy(alert = alert) }
    }
}
