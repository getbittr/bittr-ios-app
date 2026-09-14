package com.bittr.android.receive

import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource

/** [FiatPriceSource] over the user's chosen currency and bittr's price endpoint. */
class AppFiatPriceSource(
    private val prices: BitcoinPriceSource,
    private val preferences: AppPreferences,
) : FiatPriceSource {

    override suspend fun current(): FiatPrice? {
        val currency = preferences.currency.value
        return prices.price(currency)?.let { FiatPrice(pricePerBitcoin = it, symbol = currency.symbol) }
    }
}
