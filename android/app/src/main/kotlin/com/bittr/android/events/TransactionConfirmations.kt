package com.bittr.android.events

import androidx.lifecycle.ViewModel
import com.bittr.android.core.swaps.SwapCoordinator
import com.bittr.android.core.swaps.SwapEvent
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.di.WalletComposition
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
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
 * Nothing opens while the wallet is locked or during the 10-wrong-PIN removal, and a transaction
 * is asked for once: Send's own result and the node's event name the same payment.
 *
 * @param raw the node's overview, where a Lightning row still has its payment hash.
 * @param history the matched overview the transaction screen reads (descriptions and swaps applied).
 * @param refresh sync and take a reading, so a just-completed payment reaches [raw].
 */
class TransactionConfirmations(
    scope: CoroutineScope,
    nodeEvents: Flow<NodeEvent>,
    swapCompletions: Flow<String>,
    private val raw: StateFlow<WalletOverview>,
    private val history: StateFlow<WalletOverview>,
    private val refresh: suspend () -> Unit,
    private val canShow: () -> Boolean,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {

    private val _requests = MutableSharedFlow<String>(extraBufferCapacity = 8)

    /** Transaction ids to open, in the matched history's terms. */
    val requests: SharedFlow<String> = _requests.asSharedFlow()

    private val asked = ArrayDeque<String>()

    init {
        scope.launch {
            nodeEvents.collect { event ->
                when (event) {
                    is NodeEvent.PaymentReceived -> scope.launch { openPayment(event.paymentHash) }
                    is NodeEvent.PaymentSuccessful -> scope.launch { openPayment(event.paymentHash) }
                    is NodeEvent.ChannelClosed -> Unit
                }
            }
        }
        scope.launch { swapCompletions.collect { request(it) } }
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

    private suspend fun openPayment(paymentHash: String) {
        for (wait in RETRY_WAITS_MS) {
            if (wait > 0) pause(wait)
            runCatching { refresh() }
            when (val found = lookup(paymentHash)) {
                Lookup.NotYet -> Unit
                Lookup.SwapPayment -> return
                is Lookup.Row -> {
                    request(found.id)
                    return
                }
            }
        }
    }

    private fun request(id: String) {
        if (!canShow() || id in asked) return
        asked.addLast(id)
        while (asked.size > REMEMBERED) asked.removeFirst()
        _requests.tryEmit(id)
    }

    private companion object {
        /** An immediate look, a quick second one for the matched history to catch up, then iOS's 5 s. */
        val RETRY_WAITS_MS = listOf(0L, 1_000L, 5_000L, 5_000L)
        const val REMEMBERED = 16
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
    )
}

/** How the navigation graph reaches [TransactionConfirmations]. */
@HiltViewModel
class TransactionConfirmationsViewModel @Inject constructor(val confirmations: TransactionConfirmations) : ViewModel()
