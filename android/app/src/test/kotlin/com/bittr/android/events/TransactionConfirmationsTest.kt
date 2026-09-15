package com.bittr.android.events

import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TransactionConfirmationsTest {

    private val nodeEvents = MutableSharedFlow<NodeEvent>(extraBufferCapacity = 8)
    private val swapCompletions = MutableSharedFlow<String>(extraBufferCapacity = 8)
    private val raw = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = true))
    private val history = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = true))
    private var showable = true
    private var refreshes = 0
    private var onRefresh: (Int) -> Unit = {}
    private val opened = mutableListOf<String>()

    private val confirmations = TransactionConfirmations(
        scope = CoroutineScope(Dispatchers.Unconfined),
        nodeEvents = nodeEvents,
        swapCompletions = swapCompletions,
        raw = raw,
        history = history,
        refresh = { refreshes += 1; onRefresh(refreshes) },
        canShow = { showable },
        pause = {},
    )

    init {
        CoroutineScope(Dispatchers.Unconfined).launch { confirmations.requests.collect { opened += it } }
    }

    private fun lightningRow(id: String, hash: String, description: String? = null, swap: SwapActivity? = null) =
        WalletActivity(id, 1_000, 0, 0, 100, true, null, paymentHash = hash, description = description, swap = swap)

    private fun publish(vararg rows: WalletActivity) {
        raw.value = raw.value.copy(transactions = rows.toList())
        history.value = history.value.copy(transactions = rows.toList())
    }

    @Test
    fun `a received payment opens its row, found by payment hash`() {
        publish(lightningRow("preimage1", "hash1"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("HASH1", 1_000_000))
        assertEquals(listOf("preimage1"), opened)
    }

    @Test
    fun `a payment that has not reached the history yet is retried until it has`() {
        onRefresh = { count -> if (count == 3) publish(lightningRow("preimage2", "hash2")) }
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash2", 1_000))
        assertEquals(listOf("preimage2"), opened)
        assertEquals(3, refreshes)
    }

    @Test
    fun `a payment that never shows up opens nothing`() {
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("missing", 1))
        assertTrue(opened.isEmpty())
        assertEquals(4, refreshes)
    }

    @Test
    fun `a swap's own payment is left to the swap, which opens the combined row`() {
        val leg = lightningRow("preimage3", "hash3", description = "Swap onchain to lightning 1")
        raw.value = raw.value.copy(transactions = listOf(leg))
        history.value = history.value.copy(
            transactions = listOf(
                WalletActivity(
                    "1", 49_000, 50_000, 0, 100, false, null,
                    swap = SwapActivity("Swap onchain to lightning 1", "boltz", SwapActivityStatus.Succeeded, SwapActivityDirection.OnchainToLightning, lightningId = "preimage3"),
                ),
            ),
        )
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash3", 49_000_000))
        assertTrue(opened.isEmpty())

        swapCompletions.tryEmit("1")
        assertEquals(listOf("1"), opened)
    }

    @Test
    fun `nothing opens while the wallet is locked or being removed`() {
        showable = false
        publish(lightningRow("preimage4", "hash4"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash4", 1))
        swapCompletions.tryEmit("swap")
        assertTrue(opened.isEmpty())
    }

    @Test
    fun `the same transaction is asked for once`() {
        publish(lightningRow("preimage5", "hash5"))
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash5", null))
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash5", null))
        assertEquals(listOf("preimage5"), opened)
    }
}
