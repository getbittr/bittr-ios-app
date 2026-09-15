package com.bittr.android.feature.home

import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class SwapHistoryRowsTest {

    private val utc = TimeZone.getTimeZone("UTC")

    private fun swapRow(status: SwapActivityStatus, suggested: Boolean = false, lightning: Boolean = false, height: Int? = null) =
        WalletActivity(
            id = "20260915120000",
            receivedSats = 59_000,
            sentSats = 60_000,
            feeSats = 300,
            timestampSecs = 1_757_937_600,
            isLightning = lightning,
            confirmationHeight = height,
            description = "Swap onchain to lightning 20260915120000",
            swap = SwapActivity(
                dateId = "Swap onchain to lightning 20260915120000",
                boltzId = "boltz1",
                status = status,
                direction = SwapActivityDirection.OnchainToLightning,
                isSuggested = suggested,
                onchainId = "tx1",
                lightningId = "pre1",
            ),
        )

    @Test
    fun `a completed swap shows the complete icon, no lightning bolt and no unconfirmed colour`() {
        val row = historyRows(listOf(swapRow(SwapActivityStatus.Succeeded)), price = null, currentHeight = 100, timeZone = utc).single()
        assertEquals(HistorySwap.Complete, row.swap)
        assertFalse(row.isLightning)
        assertFalse(row.unconfirmed)
    }

    @Test
    fun `a pending swap shows the pending icon and can still be unconfirmed`() {
        val row = historyRows(listOf(swapRow(SwapActivityStatus.Pending)), price = null, currentHeight = 100, timeZone = utc).single()
        assertEquals(HistorySwap.Pending, row.swap)
        assertEquals(true, row.unconfirmed)
    }

    @Test
    fun `a Swap and Pay leg has no swap icon`() {
        val row = historyRows(listOf(swapRow(SwapActivityStatus.Succeeded, suggested = true, lightning = true)), null, 100, utc).single()
        assertNull(row.swap)
        assertEquals(true, row.isLightning)
    }

    @Test
    fun `a completed onchain-to-lightning swap shows both ids, its status and no description`() {
        val detail = transactionDetail(swapRow(SwapActivityStatus.Succeeded, height = 90), price = null, currentHeight = 100, timeZone = utc)

        assertEquals(HomeStrings.ONCHAIN_ID, detail.idTitle)
        assertEquals("tx1", detail.id)
        assertEquals("tx1", detail.explorerId)
        assertNull(detail.confirmations)
        assertNull(detail.description)
        val swap = detail.swap!!
        assertEquals("boltz1", swap.boltzId)
        assertEquals(HomeStrings.SWAP_SUCCEEDED, swap.status)
        assertEquals(HomeStrings.LIGHTNING_ID, swap.bottomIdTitle)
        assertEquals("pre1", swap.bottomId)
        assertEquals(true, swap.bottomIdCopyable)
        // The swap's total cost: everything that went out beyond what came back.
        assertEquals("1 300 sats", detail.fees)
    }

    @Test
    fun `a pending swap is expecting its second leg`() {
        val swap = transactionDetail(swapRow(SwapActivityStatus.Pending), null, 100, utc).swap!!
        assertEquals(HomeStrings.SWAP_PENDING, swap.status)
        assertEquals(HomeStrings.EXPECTING, swap.bottomId)
        assertFalse(swap.bottomIdCopyable)
    }

    @Test
    fun `an unknown swap id reads Unavailable and opens nothing`() {
        val activity = swapRow(SwapActivityStatus.Succeeded).let { it.copy(swap = it.swap!!.copy(boltzId = null)) }
        val swap = transactionDetail(activity, null, 100, utc).swap!!
        assertEquals(HomeStrings.UNAVAILABLE, swap.swapIdLabel)
        assertNull(swap.boltzId)
    }

    @Test
    fun `a stored invoice description is shown, and the closure sentence is the fallback`() {
        val paid = WalletActivity("pre", 1_000, 0, 0, 1_757_937_600, true, null, paymentHash = "hash", description = "coffee")
        assertEquals("coffee", transactionDetail(paid, null, 100, utc).description)

        val closure = WalletActivity("closetx", 5_000, 0, 0, 1_757_937_600, false, 90)
        assertEquals(
            HomeStrings.CHANNEL_CLOSURE_TRANSACTION,
            transactionDetail(closure, null, 100, utc, closureTxIds = setOf("closetx")).description,
        )
    }
}
