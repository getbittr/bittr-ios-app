package com.bittr.android.events

import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.core.wallet.ldk.lightning.PaymentFailureReasonView
import com.bittr.android.push.BittrPayoutTracker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    private val opened = mutableListOf<TransactionRequest>()
    private val now = 1_000_000L

    /** bittr, faked: which ids it has seen and which it confirms. */
    private val lookup = object : BittrLookup {
        val sent = mutableSetOf<String>()
        val purchases = mutableSetOf<String>()
        val confirms = mutableSetOf<String>()
        val checked = mutableListOf<String>()
        val descriptions = mutableMapOf<String, String>()
        override fun alreadySent(txId: String) = txId in sent
        override fun isPurchase(txId: String) = txId in purchases
        override suspend fun check(txId: String): Boolean {
            checked += txId
            sent += txId
            return txId in confirms
        }
        override fun storeDescription(key: String, description: String) {
            descriptions[key] = description
        }
    }
    private val payouts = BittrPayoutTracker()

    private val confirmations = TransactionConfirmations(
        scope = CoroutineScope(Dispatchers.Unconfined),
        nodeEvents = nodeEvents,
        swapCompletions = swapCompletions,
        raw = raw,
        history = history,
        refresh = { refreshes += 1; onRefresh(refreshes) },
        canShow = { showable },
        pause = {},
        bittr = lookup,
        payouts = payouts,
        clockMillis = { now },
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

    private val openedIds get() = opened.map { it.id }

    @Test
    fun `a received payment opens its row, found by payment hash`() {
        publish(lightningRow("preimage1", "hash1"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("HASH1", 1_000_000))
        assertEquals(listOf(TransactionRequest("preimage1")), opened)
        assertTrue("no bittr check without an expected payout", lookup.checked.isEmpty())
    }

    @Test
    fun `a payment that has not reached the history yet is retried until it has`() {
        onRefresh = { count -> if (count == 3) publish(lightningRow("preimage2", "hash2")) }
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash2", 1_000))
        assertEquals(listOf("preimage2"), openedIds)
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
        assertEquals(listOf("1"), openedIds)
    }

    @Test
    fun `nothing opens while the wallet is locked or being removed`() {
        showable = false
        publish(lightningRow("preimage4", "hash4"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash4", 1))
        swapCompletions.tryEmit("swap")
        nodeEvents.tryEmit(NodeEvent.PaymentFailed("hash4", PaymentFailureReasonView.RouteNotFound))
        assertTrue(opened.isEmpty())
        assertNull(confirmations.paymentFailure.value)
    }

    @Test
    fun `the same transaction is asked for once`() {
        publish(lightningRow("preimage5", "hash5"))
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash5", null))
        nodeEvents.tryEmit(NodeEvent.PaymentSuccessful("hash5", null))
        assertEquals(listOf("preimage5"), openedIds)
    }

    @Test
    fun `a bittr payout bittr confirms opens as the payout summary, with its notification id as the description`() {
        payouts.expect("notification-1", now)
        lookup.confirms += "preimage6"
        publish(lightningRow("preimage6", "hash6"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash6", 1_000_000))

        assertEquals(listOf(TransactionRequest("preimage6", confetti = true)), opened)
        assertEquals(listOf("preimage6"), lookup.checked)
        assertEquals("notification-1", lookup.descriptions["hash6"])
        assertNull("the payout is checked once", payouts.awaiting(now))
    }

    @Test
    fun `a payment bittr doesn't confirm opens as an ordinary transaction`() {
        payouts.expect("notification-2", now)
        publish(lightningRow("preimage7", "hash7"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash7", 1_000))
        assertEquals(listOf(TransactionRequest("preimage7")), opened)
        assertTrue(lookup.descriptions.isEmpty())
    }

    @Test
    fun `a payout already sent to bittr opens as the summary without asking again`() {
        payouts.expect("notification-3", now)
        lookup.sent += "preimage8"
        publish(lightningRow("preimage8", "hash8"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash8", 1_000))
        assertEquals(listOf(TransactionRequest("preimage8", confetti = true)), opened)
        assertTrue(lookup.checked.isEmpty())
    }

    @Test
    fun `an expired payout expectation doesn't make a later payment a payout`() {
        payouts.expect("old", now - BittrPayoutTracker.WINDOW_MILLIS - 1)
        publish(lightningRow("preimage9", "hash9"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash9", 1_000))
        assertEquals(listOf(TransactionRequest("preimage9")), opened)
    }

    @Test
    fun `a new channel opens its funding purchase once bittr confirms it, and nothing otherwise`() {
        nodeEvents.tryEmit(NodeEvent.ChannelPending("channel-1", "funding-unknown"))
        assertTrue(opened.isEmpty())
        assertEquals(listOf("funding-unknown"), lookup.checked)

        lookup.confirms += "funding-1"
        nodeEvents.tryEmit(NodeEvent.ChannelPending("channel-2", "funding-1"))
        assertEquals(listOf(TransactionRequest("funding-1", confetti = true)), opened)
    }

    @Test
    fun `a funding transaction bittr already knows opens only when its purchase is stored`() {
        lookup.sent += listOf("funding-2", "funding-3")
        lookup.purchases += "funding-3"
        nodeEvents.tryEmit(NodeEvent.ChannelPending("channel-3", "funding-2"))
        nodeEvents.tryEmit(NodeEvent.ChannelPending("channel-4", "funding-3"))
        assertEquals(listOf(TransactionRequest("funding-3", confetti = true)), opened)
    }

    @Test
    fun `a failed payment raises the payment failed alert with its reason`() {
        nodeEvents.tryEmit(NodeEvent.PaymentFailed("hash10", PaymentFailureReasonView.RouteNotFound))
        val alert = confirmations.paymentFailure.value!!
        assertEquals("Payment failed", alert.title)
        assertTrue(alert.message, alert.message.startsWith("Your Lightning payment didn't go through. Route not found.\n\n"))

        confirmations.dismissPaymentFailure()
        nodeEvents.tryEmit(NodeEvent.PaymentFailed(null, null))
        assertTrue(confirmations.paymentFailure.value!!.message.startsWith("Your Lightning payment didn't go through.\n\n"))
    }

    /** After a wallet removal the next wallet's transactions open again, and the old alert is gone. */
    @Test
    fun `a reset forgets what was opened and drops the payment failed alert`() {
        publish(lightningRow("preimage1", "hash1"))
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash1", 1_000_000))
        nodeEvents.tryEmit(NodeEvent.PaymentFailed(null, null))
        assertEquals(1, opened.size)

        confirmations.reset()
        assertNull(confirmations.paymentFailure.value)
        nodeEvents.tryEmit(NodeEvent.PaymentReceived("hash1", 1_000_000))
        assertEquals(listOf(TransactionRequest("preimage1"), TransactionRequest("preimage1")), opened)
    }
}
