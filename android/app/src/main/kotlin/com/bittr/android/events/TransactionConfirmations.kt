package com.bittr.android.events

import androidx.lifecycle.ViewModel
import com.bittr.android.core.swaps.SwapCoordinator
import com.bittr.android.core.swaps.SwapEvent
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.core.wallet.ldk.lightning.PaymentFailureReasonView
import com.bittr.android.di.WalletComposition
import com.bittr.android.push.BittrPayoutTracker
import com.bittr.android.removal.WalletRemovalCoordinator
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A transaction to open, and whether as the bittr payout summary (`showConfetti`). */
data class TransactionRequest(val id: String, val confetti: Boolean = false)

/** iOS's `paymentfailed` alert. */
data class PaymentFailureAlert(val title: String, val message: String)

/**
 * What the confirmations ask bittr — `checkPaymentWithBittr` over `GET /transaction_info`.
 * `:app` binds it over the customer store; see `BittrConfirmationsModule`.
 */
interface BittrLookup {

    /** `CacheManager.getSentToBittr().contains(txid)`. */
    fun alreadySent(txId: String): Boolean

    /** bittr has already confirmed [txId] as a purchase or payout. */
    fun isPurchase(txId: String): Boolean

    /**
     * Send [txId] to `/transaction_info`, remember it was sent, and store what bittr returns.
     *
     * @return true when bittr returned exactly this transaction — iOS's
     *   `bittrApiTransactions.count == 1 && first.txId == paymentPreimage`.
     */
    suspend fun check(txId: String): Boolean

    /** `CacheManager.storeInvoiceDescription(preimage:desc:)`, keyed as the history reads descriptions. */
    fun storeDescription(key: String, description: String)

    object None : BittrLookup {
        override fun alreadySent(txId: String) = false
        override fun isPurchase(txId: String) = false
        override suspend fun check(txId: String) = false
        override fun storeDescription(key: String, description: String) = Unit
    }
}

/**
 * The transaction screen once a payment completes — iOS opens `TransactionViewController` from
 * wherever the user is when LDK reports `.paymentReceived` (`launchTransactionVC`) or
 * `.paymentSuccessful` (`addNewPaymentToTable`), and when a swap completes
 * (`openCompletedSwapTransaction`).
 *
 * A payment is looked for by its payment hash in the node's history, then shown as the row the
 * transaction screen reads. The row can lag the event — the node publishes after a sync — so the
 * lookup refreshes and retries, as iOS retries its swap lookup. A payment that belongs to a swap
 * is left to the swap, which opens the combined swap row once both legs are in (iOS:
 * `!isSwap, !isSwapPayment`).
 *
 * ### bittr payouts and purchases (`checkPaymentWithBittr`)
 *
 * A payment that arrives while a bittr payout is expected ([BittrPayoutTracker], iOS's
 * `lightningNotification`) is checked with bittr before it opens: already sent to bittr → the payout
 * summary straight away; otherwise, three seconds later, `/transaction_info` — confirmed → the
 * summary (with the notification id stored as the payment's description), not confirmed → the
 * ordinary transaction screen. A new channel (`.channelPending`) is checked the same way with its
 * funding transaction, and opens the summary of the purchase that funded it only when bittr confirms.
 *
 * `.paymentFailed` raises iOS's `paymentfailed` alert with the reason.
 *
 * Nothing opens while the wallet is locked or during the 10-wrong-PIN removal, and a transaction
 * is asked for once: Send's own result and the node's event name the same payment.
 *
 * @param raw the node's overview, where a Lightning row still has its payment hash.
 * @param history the matched overview the transaction screen reads (descriptions and swaps applied).
 * @param refresh sync and take a reading, so a just-completed payment reaches [raw].
 */
class TransactionConfirmations(
    private val scope: CoroutineScope,
    nodeEvents: Flow<NodeEvent>,
    swapCompletions: Flow<String>,
    private val raw: StateFlow<WalletOverview>,
    private val history: StateFlow<WalletOverview>,
    private val refresh: suspend () -> Unit,
    private val canShow: () -> Boolean,
    private val pause: suspend (Long) -> Unit = { delay(it) },
    private val bittr: BittrLookup = BittrLookup.None,
    private val payouts: BittrPayoutTracker = BittrPayoutTracker(),
    private val clockMillis: () -> Long = System::currentTimeMillis,
) {

    private val _requests = MutableSharedFlow<TransactionRequest>(extraBufferCapacity = 8)

    /** Transactions to open, in the matched history's terms. */
    val requests: SharedFlow<TransactionRequest> = _requests.asSharedFlow()

    private val _paymentFailure = MutableStateFlow<PaymentFailureAlert?>(null)

    /** The `paymentfailed` alert on screen, if any. */
    val paymentFailure: StateFlow<PaymentFailureAlert?> = _paymentFailure.asStateFlow()

    private val asked = ArrayDeque<String>()

    init {
        scope.launch {
            nodeEvents.collect { event ->
                when (event) {
                    is NodeEvent.PaymentReceived -> scope.launch { openReceived(event.paymentHash) }
                    is NodeEvent.PaymentSuccessful -> scope.launch { openPayment(event.paymentHash) }
                    is NodeEvent.ChannelPending -> scope.launch { openFunding(event.fundingTxId) }
                    is NodeEvent.PaymentFailed -> paymentFailed(event.reason)
                    is NodeEvent.ChannelClosed -> Unit
                }
            }
        }
        scope.launch { swapCompletions.collect { request(TransactionRequest(it)) } }
    }

    fun dismissPaymentFailure() {
        _paymentFailure.value = null
    }

    /**
     * The wallet is gone: forget which transactions were already opened (the next wallet's ids are
     * new) and drop a payment-failed alert about the old one. On the scope that owns [asked].
     */
    fun reset() {
        scope.launch {
            asked.clear()
            _paymentFailure.value = null
        }
    }

    internal sealed interface Lookup {
        data object NotYet : Lookup
        data object SwapPayment : Lookup
        data class Row(val id: String) : Lookup
    }

    /** Where the payment with [paymentHash] is in the history the screen reads, if it is there yet. */
    internal fun lookup(paymentHash: String): Lookup {
        val leg = raw.value.transactions.firstOrNull { it.paymentHash.equals(paymentHash, ignoreCase = true) }
            ?: return Lookup.NotYet
        val rows = history.value.transactions
        val mergedIntoSwap = rows.any { row ->
            row.id != leg.id && row.swap?.let { it.lightningId == leg.id || it.onchainId == leg.id } == true
        }
        if (mergedIntoSwap) return Lookup.SwapPayment
        val row = rows.firstOrNull { it.id == leg.id } ?: return Lookup.NotYet
        if (row.swap != null || row.description?.startsWith("Swap ") == true) return Lookup.SwapPayment
        return Lookup.Row(row.id)
    }

    /** The payment's row once it is in the history, retrying while the wallet catches up. */
    private suspend fun findRow(paymentHash: String): Lookup {
        for (wait in RETRY_WAITS_MS) {
            if (wait > 0) pause(wait)
            runCatching { refresh() }
            val found = lookup(paymentHash)
            if (found != Lookup.NotYet) return found
        }
        return Lookup.NotYet
    }

    private suspend fun openPayment(paymentHash: String) {
        val found = findRow(paymentHash) as? Lookup.Row ?: return
        request(TransactionRequest(found.id))
    }

    /** `.paymentReceived`: a bittr payout is checked with bittr first; anything else opens as it is. */
    private suspend fun openReceived(paymentHash: String) {
        val found = findRow(paymentHash) as? Lookup.Row ?: return
        val notificationId = payouts.awaiting(clockMillis())
        if (notificationId == null) {
            request(TransactionRequest(found.id))
            return
        }
        // Checked once, whatever bittr answers: the next payment is not this payout.
        payouts.clear()
        checkWithBittr(
            txId = found.id,
            inHistory = true,
            otherwise = TransactionRequest(found.id),
            onConfirmed = { bittr.storeDescription(paymentHash, notificationId) },
        )
    }

    /** `.channelPending`: the purchase that funded the new channel, once bittr confirms it. */
    private suspend fun openFunding(fundingTxId: String) {
        checkWithBittr(txId = fundingTxId, inHistory = false, otherwise = null)
    }

    /**
     * `checkPaymentWithBittr(paymentPreimage:paymentDetails:isFundingTransaction:)`.
     *
     * @param inHistory the transaction is a row of this wallet's history, which iOS looks it up in
     *   when bittr already knows it. The funding transaction is not; bittr's stored record stands in.
     * @param otherwise what opens when bittr doesn't confirm it (iOS: the payment details, if any).
     */
    private suspend fun checkWithBittr(
        txId: String,
        inHistory: Boolean,
        otherwise: TransactionRequest?,
        onConfirmed: () -> Unit = {},
    ) {
        if (bittr.alreadySent(txId)) {
            if (inHistory || bittr.isPurchase(txId)) request(TransactionRequest(txId, confetti = true))
            return
        }
        pause(BITTR_CHECK_DELAY_MS)
        val confirmed = runCatching { bittr.check(txId) }.getOrDefault(false)
        if (confirmed) {
            onConfirmed()
            request(TransactionRequest(txId, confetti = true))
        } else if (otherwise != null) {
            request(otherwise)
        }
    }

    private fun paymentFailed(reason: PaymentFailureReasonView?) {
        if (!canShow()) return
        val reasonText = reason?.let(::reasonWords).orEmpty()
        _paymentFailure.value = PaymentFailureAlert(
            title = PAYMENT_FAILED,
            message = PAYMENT_FAILED_2.replace("<reason>", if (reasonText.isEmpty()) "" else " $reasonText."),
        )
    }

    private fun request(request: TransactionRequest) {
        if (!canShow() || request.id in asked) return
        asked.addLast(request.id)
        while (asked.size > REMEMBERED) asked.removeFirst()
        _requests.tryEmit(request)
    }

    internal companion object {
        /** An immediate look, a quick second one for the matched history to catch up, then iOS's 5 s. */
        val RETRY_WAITS_MS = listOf(0L, 1_000L, 5_000L, 5_000L)
        const val REMEMBERED = 16

        /** `DispatchQueue.global().asyncAfter(deadline: .now() + 3)` before `/transaction_info`. */
        const val BITTR_CHECK_DELAY_MS = 3_000L

        /** `paymentfailed`. */
        const val PAYMENT_FAILED = "Payment failed"

        /** `paymentfailed2`. */
        const val PAYMENT_FAILED_2 =
            "Your Lightning payment didn't go through.<reason>\n\nLightning payments can fail when the receiver is offline or doesn't have the app open, when their wallet doesn't have enough receiving capacity, when there's no affordable route through the network, or when the invoice has expired. Try again later or ask the receiver to open their app."

        /** The reason ids iOS looks up; `noReason` has no dictionary entry, so no reason is shown. */
        fun reasonWords(reason: PaymentFailureReasonView): String = when (reason) {
            PaymentFailureReasonView.RecipientRejected -> "Recipient rejected"
            PaymentFailureReasonView.UserAbandoned -> "User abandoned"
            PaymentFailureReasonView.RetriesExhausted -> "Retries exhausted"
            PaymentFailureReasonView.PaymentExpired -> "Payment expired"
            PaymentFailureReasonView.RouteNotFound -> "Route not found"
            PaymentFailureReasonView.UnexpectedError -> "Unexpected error"
            PaymentFailureReasonView.UnknownRequiredFeatures -> "Unknown required features"
            PaymentFailureReasonView.InvoiceRequestExpired -> "Invoice request expired"
            PaymentFailureReasonView.InvoiceRequestRejected -> "Invoice request rejected"
            PaymentFailureReasonView.BlindedPathCreationFailed -> "Blinded path creation failed"
        }
    }
}

@Module
@InstallIn(SingletonComponent::class)
object TransactionConfirmationsModule {

    @Provides
    @Singleton
    fun provideTransactionConfirmations(
        composition: WalletComposition,
        history: WalletOverviewSource,
        wallet: WalletService,
        removal: WalletRemovalCoordinator,
        swaps: SwapCoordinator,
        bittr: BittrLookup,
        payouts: BittrPayoutTracker,
    ): TransactionConfirmations = TransactionConfirmations(
        // Main, like the push coordinator: one thread owns what has been asked for.
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        nodeEvents = composition.nodeEvents.events,
        swapCompletions = swaps.events.filterIsInstance<SwapEvent.OpenTransaction>().map { it.transactionId },
        raw = composition.overview.overview,
        history = history.overview,
        refresh = {
            withContext(Dispatchers.IO) {
                runCatching { composition.lightning.syncWallets() }
                composition.refresh()
            }
        },
        canShow = { wallet.state.value == WalletState.Ready && !removal.isLockoutRemoval },
        bittr = bittr,
        payouts = payouts,
    )
}

/** How the navigation graph reaches [TransactionConfirmations]. */
@HiltViewModel
class TransactionConfirmationsViewModel @Inject constructor(val confirmations: TransactionConfirmations) : ViewModel()
