package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletActivity
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionDetailTest {

    private val utc = TimeZone.getTimeZone("UTC")

    @Test
    fun `an on-chain send shows its fee, confirmations and explorer link`() {
        // 2025-09-04 08:05 UTC
        val send = WalletActivity("abc", receivedSats = 0, sentSats = 9_000, feeSats = 653, timestampSecs = 1_756_973_100, isLightning = false, confirmationHeight = 98)
        val detail = transactionDetail(send, FiatPrice(100_000.0, "€"), currentHeight = 100, timeZone = utc)

        assertEquals("4 Sep 2025 08:05", detail.date)
        assertEquals("- 9 000 sats", detail.amount)
        assertEquals("653 sats", detail.fees)
        assertEquals("3", detail.confirmations)
        assertEquals("abc", detail.explorerId)
        assertEquals("9.65 €", detail.currentValue)
    }

    @Test
    fun `a lightning receive has no fees, confirmations or explorer link`() {
        val receive = WalletActivity("hash", receivedSats = 1_000, sentSats = 0, feeSats = 0, timestampSecs = 0, isLightning = true, confirmationHeight = null)
        val detail = transactionDetail(receive, price = null, currentHeight = 100, timeZone = utc)

        assertEquals("+ 1 000 sats", detail.amount)
        assertNull(detail.fees)
        assertNull(detail.confirmations)
        assertNull(detail.explorerId)
        assertNull(detail.currentValue)
    }

    @Test
    fun `an unconfirmed on-chain transaction says so`() {
        val pending = WalletActivity("abc", 5_000, 0, 0, 0, false, null)
        assertEquals("Unconfirmed", transactionDetail(pending, null, 100, utc).confirmations)
    }

    @Test
    fun `a channel closure payout explains where its funds came from`() {
        val payout = WalletActivity("closetx", 90_000, 0, 0, 0, false, 99)
        val detail = transactionDetail(payout, null, 100, utc, closureTxIds = setOf("closetx"))
        assertEquals(HomeStrings.CHANNEL_CLOSURE_TRANSACTION, detail.description)
        assertNull(transactionDetail(payout, null, 100, utc).description)
    }

    @Test
    fun `a blank note is no note`() {
        val receive = WalletActivity("hash", 1_000, 0, 0, 0, true, null)
        assertEquals("coffee", transactionDetail(receive, null, 100, utc, note = "coffee").note)
        assertNull(transactionDetail(receive, null, 100, utc, note = "  ").note)
    }

    @Test
    fun `fiat values keep two decimals and group the whole part`() {
        assertEquals("1 234.50", twoDecimals(1234.5))
        assertEquals("0.07", twoDecimals(0.066))
    }
}
