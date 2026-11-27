package com.bittr.android.home

import androidx.lifecycle.ViewModel
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.feature.value.PriceCurrency
import com.bittr.android.feature.value.PriceHistory
import com.bittr.android.receive.BitcoinPriceSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.StateFlow

/**
 * The chosen currency as the price API's — iOS's `getCorrectBitcoinValue()`, which reads the
 * CHF series when CHF is chosen and the EUR one otherwise.
 */
internal fun Currency.priceCurrency(): PriceCurrency = when (this) {
    Currency.EUR -> PriceCurrency.EUR
    Currency.CHF -> PriceCurrency.CHF
}

private fun PriceCurrency.currency(): Currency = when (this) {
    PriceCurrency.EUR -> Currency.EUR
    PriceCurrency.CHF -> Currency.CHF
}

/** The chosen currency and the shared price history, for the Value screen. */
@HiltViewModel
class ValueScreenViewModel @Inject constructor(
    preferences: AppPreferences,
    val history: PriceHistory,
) : ViewModel() {

    val currency: StateFlow<Currency> = preferences.currency
}

/** The one price history, shared by Home's value card and the Value screen. */
@Module
@InstallIn(SingletonComponent::class)
object ValueModule {

    @Provides
    @Singleton
    fun providePriceHistory(environment: BittrEnvironment, http: HttpClient, prices: BitcoinPriceSource): PriceHistory =
        // The current price comes from the app's one price source, so it is fetched once.
        PriceHistory(environment, http, currentPrice = { currency -> prices.price(currency.currency()) })
}
