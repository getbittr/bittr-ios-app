package com.bittr.android.receive

import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.drop

/** [FiatPriceSource] over the user's chosen currency and bittr's price endpoint. */
class AppFiatPriceSource(
    private val prices: BitcoinPriceSource,
    private val preferences: AppPreferences,
) : FiatPriceSource {

    /** The preference's later values; the current one is what [current] already reads. */
    override val currencyChanges: Flow<Any> = preferences.currency.drop(1)

    override fun currentSymbol(): String = preferences.currency.value.symbol

    override suspend fun current(): FiatPrice? {
        val currency = preferences.currency.value
        return prices.price(currency)?.let { FiatPrice(pricePerBitcoin = it, symbol = currency.symbol) }
    }
}
