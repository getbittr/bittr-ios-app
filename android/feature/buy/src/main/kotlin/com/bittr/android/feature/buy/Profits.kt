package com.bittr.android.feature.buy

import kotlin.math.abs
import kotlin.math.roundToLong

/** One bittr purchase, as the profit calculation reads it. */
data class PurchaseForProfit(
    /** The bitcoin received, in BTC — iOS's `received.inBTC()`. */
    val receivedBtc: Double,
    /** The purchase currency, `"EUR"` or `"CHF"`. Anything else is CHF, as on iOS. */
    val currency: String?,
    /** `fiat_amount_net`, in [currency]. */
    val fiatNetAmount: Double,
)

/** The three Profits figures, in whole units of the chosen currency. */
data class ProfitSummary(
    val totalProfit: Long,
    val totalInvestment: Long,
    val currentValue: Long,
    val currencySymbol: String,
) {
    /** `"<symbol> <Int>"` — ProfitViewController's three labels. */
    val investmentText: String get() = "$currencySymbol $totalInvestment"
    val valueText: String get() = "$currencySymbol $currentValue"
    val profitText: String get() = "$currencySymbol $totalProfit"

    /** Home's pill: `"0 %"` with no investment, else the rounded percentage without a sign. */
    val percentText: String
        get() = if (totalInvestment == 0L) {
            "0 %"
        } else {
            "${abs((totalProfit.toDouble() / totalInvestment * 100).roundToLong())} %"
        }

    /** Loss colours and a down arrow when negative. */
    val isLoss: Boolean get() = totalProfit < 0
}

/**
 * `calculateProfit()` (`LoadWalletData.swift:412-450`), as a pure function.
 *
 * For a purchase in the chosen currency, profit is today's value minus what was paid. For one in
 * the other currency, both figures are first worked out in the purchase currency and then
 * rescaled into the chosen one at today's rates — iOS's exact arithmetic, including rounding each
 * purchase to a whole unit before summing.
 *
 * @param chosenSymbol `"€"` or `"CHF"`, the preference.
 * @param chosenPrice today's price of one bitcoin in the chosen currency.
 * @param eurPrice today's EUR price, used for EUR purchases when CHF is chosen. Null reads as 0,
 *   as iOS's `valueInEUR ?? 0` does.
 * @param chfPrice today's CHF price, likewise.
 */
object ProfitCalculator {

    fun summarise(
        purchases: List<PurchaseForProfit>,
        chosenSymbol: String,
        chosenPrice: Double,
        eurPrice: Double?,
        chfPrice: Double?,
    ): ProfitSummary {
        var profit = 0L
        var investment = 0L
        var value = 0L
        for (purchase in purchases) {
            val purchaseSymbol = if (purchase.currency == "EUR") "€" else "CHF"
            val sameCurrency = purchaseSymbol == chosenSymbol
            val conversion = when {
                sameCurrency -> chosenPrice
                purchaseSymbol == "€" -> eurPrice ?: 0.0
                else -> chfPrice ?: 0.0
            }
            var purchaseProfit = purchase.receivedBtc * conversion - purchase.fiatNetAmount
            var purchaseInvestment = purchase.fiatNetAmount
            if (!sameCurrency) {
                purchaseProfit = purchaseProfit / conversion * chosenPrice
                purchaseInvestment = purchase.fiatNetAmount / conversion * chosenPrice
            }
            profit += roundHalfAwayFromZero(purchaseProfit)
            investment += roundHalfAwayFromZero(purchaseInvestment)
            value += roundHalfAwayFromZero(purchase.receivedBtc * chosenPrice)
        }
        return ProfitSummary(profit, investment, value, chosenSymbol)
    }

    /** Swift's `Double.rounded()`, which rounds halves away from zero. NaN and infinity read 0. */
    private fun roundHalfAwayFromZero(value: Double): Long {
        if (value.isNaN() || value.isInfinite()) return 0
        return if (value < 0) -((-value) + 0.5).toLong() else (value + 0.5).toLong()
    }
}
