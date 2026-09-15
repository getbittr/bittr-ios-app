package com.bittr.android.core.wallet

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SwapHistoryTest {

    private val o2l = "Swap onchain to lightning 20260915120000"
    private val l2o = "Swap lightning to onchain 20260915130000"

    private fun activity(
        id: String,
        received: Long = 0,
        sent: Long = 0,
        fee: Long = 0,
        ts: Long,
        lightning: Boolean,
        height: Int? = null,
        description: String? = null,
        hash: String? = null,
    ) = WalletActivity(id, received, sent, fee, ts, lightning, height, paymentHash = hash, description = description)

    private fun match(list: List<WalletActivity>, suggested: SwapActivityStatus? = null) =
        SwapHistory.matched(list, swapIdFor = { if (it == o2l || it == l2o) "boltz1" else null }, suggestedStatus = { suggested })

    @Test
    fun `descriptions are found by id, then by payment hash`() {
        val list = listOf(
            activity("preimage", received = 1000, ts = 1, lightning = true, hash = "hash1"),
            activity("txid", received = 500, ts = 2, lightning = false),
            activity("other", received = 1, ts = 3, lightning = true),
        )
        val described = SwapHistory.withDescriptions(list, mapOf("hash1" to "coffee", "txid" to "rent"))
        assertEquals(listOf("coffee", "rent", null), described.map { it.description })
    }

    @Test
    fun `an onchain-to-lightning swap's two legs become one completed row`() {
        val onchain = activity("tx1", sent = 60_000, fee = 300, ts = 10, lightning = false, height = 5, description = o2l)
        val lightning = activity("pre1", received = 59_000, ts = 20, lightning = true, description = o2l)
        val plain = activity("tx2", received = 1_000, ts = 15, lightning = false, height = 4)

        val rows = match(listOf(lightning, plain, onchain))

        assertEquals(2, rows.size)
        val swap = rows.first()
        assertEquals("20260915120000", swap.id)
        assertEquals(59_000, swap.receivedSats)
        assertEquals(60_000, swap.sentSats)
        assertEquals(300, swap.feeSats)
        assertEquals(20, swap.timestampSecs)
        assertEquals(false, swap.isLightning)
        assertEquals(SwapActivityStatus.Succeeded, swap.swap?.status)
        assertEquals(SwapActivityDirection.OnchainToLightning, swap.swap?.direction)
        assertEquals("boltz1", swap.swap?.boltzId)
        assertEquals("tx1", swap.swap?.onchainId)
        assertEquals("pre1", swap.swap?.lightningId)
        assertEquals(plain, rows[1])
    }

    @Test
    fun `a lightning-to-onchain swap with one leg is a pending swap row`() {
        val lightning = activity("pre2", sent = 50_000, fee = 10, ts = 30, lightning = true, description = l2o)

        val row = match(listOf(lightning)).single()

        assertEquals("20260915130000", row.id)
        assertEquals(SwapActivityStatus.Pending, row.swap?.status)
        assertEquals(SwapActivityDirection.LightningToOnchain, row.swap?.direction)
        assertEquals("pre2", row.swap?.lightningId)
        assertNull(row.swap?.onchainId)
        assertEquals(0, row.feeSats)
    }

    @Test
    fun `a Swap and Pay leg keeps its row and gains the suggested swap's status`() {
        val leg = activity("pre3", sent = 20_000, ts = 40, lightning = true, description = l2o)

        val row = match(listOf(leg), suggested = SwapActivityStatus.Succeeded).single()

        assertEquals("pre3", row.id)
        assertTrue(row.swap!!.isSuggested)
        assertEquals(SwapActivityStatus.Succeeded, row.swap?.status)
    }

    @Test
    fun `two on-chain legs are a failed swap and its refund`() {
        val funding = activity("fund", sent = 70_000, ts = 50, lightning = false, description = o2l)
        val refund = activity("refund", received = 69_000, ts = 60, lightning = false, description = o2l)

        val row = match(listOf(refund, funding)).single()

        assertEquals(SwapActivityStatus.Failed, row.swap?.status)
        assertEquals("fund", row.swap?.onchainId)
        assertEquals("refund", row.swap?.lightningId)
        assertEquals(70_000, row.sentSats)
        assertEquals(69_000, row.receivedSats)
    }

    @Test
    fun `a history without swap descriptions is returned untouched`() {
        val list = listOf(activity("a", received = 1, ts = 2, lightning = true, description = "coffee"))
        assertTrue(match(list) === list)
    }
}
