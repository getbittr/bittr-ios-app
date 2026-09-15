package com.bittr.android.feature.home

import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** `TransactionViewController.setTransactionData()`'s swap branches: amount, type and fees. */
class SwapTransactionDetailTest {

    private val utc = TimeZone.getTimeZone("UTC")

    private fun swapRow(
        received: Long,
        sent: Long,
        fee: Long,
        status: SwapActivityStatus,
        direction: SwapActivityDirection = SwapActivityDirection.OnchainToLightning,
        suggested: Boolean = false,
        amount: Long? = null,
        lightning: Boolean = false,
    ) = WalletActivity(
        id = "row",
        receivedSats = received,
        sentSats = sent,
        feeSats = fee,
        timestampSecs = 0,
        isLightning = lightning,
        confirmationHeight = null,
        swap = SwapActivity("Swap onchain to lightning 1", "boltz1", status, direction, isSuggested = suggested, amountSats = amount),
    )

    @Test
    fun `a completed swap shows what arrived, its direction, and the cost on top`() {
        // Ruben's swap: 50 000 sats on-chain in, 49 094 arrived on Lightning, 0 network fee in the row.
        val detail = transactionDetail(swapRow(received = 49_094, sent = 50_000, fee = 0, status = SwapActivityStatus.Succeeded), null, 100, utc)

        assertEquals("49 094 sats", detail.amount)
        assertEquals(HomeStrings.ONCHAIN_TO_LIGHTNING, detail.type)
        assertFalse(detail.typeBolt)
        assertEquals("906 sats", detail.fees)
    }

    @Test
    fun `the network fee is part of a completed swap's cost`() {
        val detail = transactionDetail(swapRow(received = 49_094, sent = 50_000, fee = 150, status = SwapActivityStatus.Succeeded), null, 100, utc)
        assertEquals("1 056 sats", detail.fees)
    }

    @Test
    fun `a lightning to onchain swap names its direction`() {
        val detail = transactionDetail(
            swapRow(received = 48_000, sent = 50_000, fee = 0, status = SwapActivityStatus.Succeeded, direction = SwapActivityDirection.LightningToOnchain, lightning = true),
            null,
            100,
            utc,
        )
        assertEquals(HomeStrings.LIGHTNING_TO_ONCHAIN, detail.type)
        assertEquals("48 000 sats", detail.amount)
    }

    @Test
    fun `a pending swap shows the swap file's amount, and the rest as fees`() {
        val detail = transactionDetail(swapRow(received = 0, sent = 51_200, fee = 0, status = SwapActivityStatus.Pending, amount = 50_000), null, 100, utc)
        assertEquals("50 000 sats", detail.amount)
        assertEquals("1 200 sats", detail.fees)
    }

    @Test
    fun `a pending swap without its file falls back to the row`() {
        val detail = transactionDetail(swapRow(received = 0, sent = 51_200, fee = 0, status = SwapActivityStatus.Pending), null, 100, utc)
        assertEquals("51 200 sats", detail.amount)
        assertEquals("0 sats", detail.fees)
    }

    @Test
    fun `a failed onchain to lightning swap swapped nothing`() {
        val detail = transactionDetail(swapRow(received = 49_000, sent = 50_000, fee = 300, status = SwapActivityStatus.Failed), null, 100, utc)
        assertEquals("0 sats", detail.amount)
        assertEquals("1 300 sats", detail.fees)
    }

    @Test
    fun `a swap and pay leg shows the paid invoice amount and the rest as fees`() {
        val detail = transactionDetail(
            swapRow(received = 0, sent = 21_500, fee = 200, status = SwapActivityStatus.Succeeded, suggested = true, amount = 20_000),
            null,
            100,
            utc,
        )
        assertEquals("- 20 000 sats", detail.amount)
        assertEquals("1 700 sats", detail.fees)
        assertEquals(HomeStrings.REGULAR, detail.type)
    }

    @Test
    fun `a swap and pay leg without its file shows the whole outflow and the network fee`() {
        val detail = transactionDetail(
            swapRow(received = 0, sent = 21_500, fee = 200, status = SwapActivityStatus.Pending, suggested = true),
            null,
            100,
            utc,
        )
        assertEquals("- 21 500 sats", detail.amount)
        assertEquals("200 sats", detail.fees)
    }

    @Test
    fun `a plain lightning payment keeps the bolt`() {
        val detail = transactionDetail(WalletActivity("p", 1_000, 0, 0, 0, true, null), null, 100, utc)
        assertEquals(HomeStrings.INSTANT, detail.type)
        assertEquals(true, detail.typeBolt)
    }
}
