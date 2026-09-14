package com.bittr.android.core.wallet

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
}
