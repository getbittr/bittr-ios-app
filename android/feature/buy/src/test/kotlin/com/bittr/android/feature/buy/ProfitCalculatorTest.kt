package com.bittr.android.feature.buy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfitCalculatorTest {

    @Test
    fun `a purchase in the chosen currency is value minus what was paid`() {
        val summary = ProfitCalculator.summarise(
            purchases = listOf(PurchaseForProfit(receivedBtc = 0.001, currency = "EUR", fiatNetAmount = 50.0)),
            chosenSymbol = "€",
            chosenPrice = 60_000.0,
            eurPrice = 60_000.0,
            chfPrice = 57_000.0,
        )
        assertEquals(ProfitSummary(totalProfit = 10, totalInvestment = 50, currentValue = 60, currencySymbol = "€"), summary)
        assertEquals("€ 50", summary.investmentText)
        assertEquals("€ 60", summary.valueText)
        assertEquals("€ 10", summary.profitText)
        assertEquals("20 %", summary.percentText)
        assertFalse(summary.isLoss)
    }

    @Test
    fun `a purchase in the other currency is rescaled at today's rates`() {
        // Bought in CHF for 60 at 50 000 CHF/BTC; today 60 000 CHF and 64 000 EUR, EUR chosen.
        val summary = ProfitCalculator.summarise(
            purchases = listOf(PurchaseForProfit(receivedBtc = 0.0012, currency = "CHF", fiatNetAmount = 60.0)),
            chosenSymbol = "€",
            chosenPrice = 64_000.0,
            eurPrice = 64_000.0,
            chfPrice = 60_000.0,
        )
        // profit in CHF = 72 - 60 = 12 → 12 / 60000 * 64000 = 12.8 → 13
        // investment = 60 / 60000 * 64000 = 64
        // value = 0.0012 * 64000 = 76.8 → 77
        assertEquals(ProfitSummary(13, 64, 77, "€"), summary)
    }

    @Test
    fun `a loss shows as a loss without a minus sign in the pill`() {
        val summary = ProfitCalculator.summarise(
            purchases = listOf(PurchaseForProfit(0.001, "CHF", 100.0)),
            chosenSymbol = "CHF",
            chosenPrice = 50_000.0,
            eurPrice = null,
            chfPrice = null,
        )
        assertEquals(-50, summary.totalProfit)
        assertEquals("CHF -50", summary.profitText)
        assertEquals("50 %", summary.percentText)
        assertTrue(summary.isLoss)
    }

    @Test
    fun `no purchases is zero percent`() {
        assertEquals("0 %", ProfitCalculator.summarise(emptyList(), "€", 60_000.0, null, null).percentText)
    }
}
