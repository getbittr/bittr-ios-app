package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/**
 * The price of one bitcoin in the currency the user chose — iOS's
 * `bittrWallet.getCorrectBitcoinValue()`, which every fiat figure in the wallet is
 * multiplied from.
 *
 * @property symbol what iOS prints after a fiat amount (`chosenCurrency`): "€" or "CHF".
 */
data class FiatPrice(val pricePerBitcoin: Double, val symbol: String)

/** Where [FiatPrice] comes from. Null when the price could not be fetched. */
fun interface FiatPriceSource {
    suspend fun current(): FiatPrice?

    /**
     * The symbol of the currency the user chose, without fetching a price — what Home looks up a
     * cached conversion rate by before the live one arrives. Null for a source that cannot say.
     */
    fun currentSymbol(): String? = null

    /**
     * Emits whenever the user picks a different display currency, so a screen holding a
     * price can fetch it again — Home's conversion and history otherwise keep showing the
     * old currency after Settings changes it. Empty for a source whose currency is fixed.
     */
    val currencyChanges: Flow<Any> get() = emptyFlow()
}
