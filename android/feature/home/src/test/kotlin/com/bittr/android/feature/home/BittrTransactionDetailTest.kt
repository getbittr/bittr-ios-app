package com.bittr.android.feature.home

import com.bittr.android.core.wallet.BittrPurchase
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletActivity
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The bittr purchase section and the payout summary — `setTransactionData()`'s `isBittr` and `showConfetti` branches. */
class BittrTransactionDetailTest {

    private val utc = TimeZone.getTimeZone("UTC")

    /** 0.002 BTC arrived by Lightning. */
    private val payout = WalletActivity("preimage", 200_000, 0, 0, 1_700_000_000, true, null, description = "notification-1")

    private fun purchase(
        net: Double? = 90.0,
        gross: Double = 100.0,
        transferFeeSats: Long? = 1_000,
        surcharge: Double? = 0.0,
        currency: String = "EUR",
    ) = BittrPurchase(
        txId = "preimage",
        currency = currency,
        bitcoinAmountSats = 200_000,
        fiatNetAmount = net,
        fiatGrossAmount = gross,
        transferFeeSats = transferFeeSats,
        bittrFee = 1.5,
        surcharge = surcharge,
        historicalExchangeRate = 45_000.0,
        timestampSecs = 1_700_000_000,
    )

    @Test
    fun `a bittr payout shows what bittr received, its fees and today's profit in the purchase currency`() {
        val detail = transactionDetail(payout, FiatPrice(55_000.0, "CHF"), null, utc, purchase = purchase(), purchasePrice = 50_000.0)
        val bittr = detail.bittr!!
        assertEquals("100.00 €", bittr.receivedAtBittr)
        assertNull("no surcharge row on a purchase of 100 or more", bittr.surcharge)
        assertEquals("1.50 €", bittr.bittrFee)
        assertEquals("1 000 sats", bittr.transferFee)
        assertEquals(HomeStrings.TRANSFER_FEE_2, bittr.transferFeeExplanation)
        assertEquals("90.00 €", bittr.purchaseValue)
        assertEquals("45 000 €/btc", bittr.exchangeRate)
        assertEquals("100.00 €", bittr.currentValue)
        assertEquals("10.00 €", bittr.profit)
        assertFalse(bittr.isLoss)
        assertNull("the section replaces the plain current value", detail.currentValue)
    }

    @Test
    fun `a loss is signed and flagged`() {
        val bittr = transactionDetail(payout, null, null, utc, purchase = purchase(net = 120.0), purchasePrice = 50_000.0).bittr!!
        assertEquals("- 20.00 €", bittr.profit)
        assertTrue(bittr.isLoss)
    }

    @Test
    fun `with no transfer fee the purchase value is gross minus surcharge and bittr fee`() {
        val bittr = transactionDetail(
            payout, null, null, utc,
            purchase = purchase(net = 95.0, gross = 50.0, transferFeeSats = 0, surcharge = 1.0),
            purchasePrice = 50_000.0,
        ).bittr!!
        assertEquals("47.50 €", bittr.purchaseValue)
        assertEquals("1.00 €", bittr.surcharge)
    }

    @Test
    fun `a purchase bittr hasn't priced yet shows its value as the purchase value and no profit`() {
        val bittr = transactionDetail(payout, null, null, utc, purchase = purchase(net = 0.0, currency = "CHF"), purchasePrice = 50_000.0).bittr!!
        assertEquals("100.00 CHF", bittr.purchaseValue)
        assertEquals("0.00 CHF", bittr.profit)
    }

    @Test
    fun `the funding purchase explains the one-time connection fee`() {
        val bittr = transactionDetail(payout, null, null, utc, purchase = purchase(), isFunding = true).bittr!!
        assertEquals(HomeStrings.TRANSFER_FEE_1, bittr.transferFeeExplanation)
    }

    @Test
    fun `the payout summary hides the description and the note`() {
        val detail = transactionDetail(payout, null, null, utc, note = "mine", purchase = purchase(), confetti = true)
        assertTrue(detail.confetti)
        assertNull(detail.description)
        assertNull(detail.note)

        val plain = transactionDetail(payout, null, null, utc, note = "mine", purchase = purchase())
        assertEquals("notification-1", plain.description)
        assertEquals("mine", plain.note)
    }

    @Test
    fun `a funding purchase that isn't in the history is shown from bittr's record`() {
        val activity = purchaseActivity(purchase())
        val detail = transactionDetail(activity, null, null, utc, purchase = purchase(), confetti = true, isFunding = true)
        assertEquals("+ 200 000 sats", detail.amount)
        assertTrue(detail.isLightning)
        assertEquals(1_700_000_000, activity.timestampSecs)
    }
}
