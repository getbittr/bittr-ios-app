package com.bittr.android.core.wallet

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The swap file's amount travels onto the matched rows, for the transaction screen. */
class SwapAmountHistoryTest {

    private val dateId = "Swap onchain to lightning 2026-09-15 12:00:00"

    private fun leg(id: String, lightning: Boolean, received: Long, sent: Long) =
        WalletActivity(id, received, sent, 0, 100, lightning, null, description = dateId)

    @Test
    fun `completed and pending swap rows carry the swapped amount`() {
        val both = listOf(leg("tx", lightning = false, received = 0, sent = 50_000), leg("pre", lightning = true, received = 49_094, sent = 0))
        val completed = SwapHistory.matched(both, swapIdFor = { "boltz1" }, swapAmountFor = { 50_000L }, suggestedStatus = { null })
        assertEquals(50_000L, completed.single().swap?.amountSats)

        val pending = SwapHistory.matched(both.take(1), swapIdFor = { "boltz1" }, swapAmountFor = { 50_000L }, suggestedStatus = { null })
        assertEquals(50_000L, pending.single().swap?.amountSats)
    }

    @Test
    fun `a swap and pay leg carries it too, and no file means no amount`() {
        val single = listOf(leg("tx", lightning = false, received = 0, sent = 21_500))
        val suggested = SwapHistory.matched(single, swapIdFor = { "boltz1" }, swapAmountFor = { 20_000L }, suggestedStatus = { SwapActivityStatus.Succeeded })
        assertEquals(20_000L, suggested.single().swap?.amountSats)

        val noFile = SwapHistory.matched(single, swapIdFor = { null }, suggestedStatus = { null })
        assertNull(noFile.single().swap?.amountSats)
    }
}
