package com.bittr.android.home

import androidx.lifecycle.ViewModel
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.feature.value.PriceCurrency
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * The chosen currency as the price API's — iOS's `getCorrectBitcoinValue()`, which reads the
 * CHF series when CHF is chosen and the EUR one otherwise.
 */
internal fun Currency.priceCurrency(): PriceCurrency = when (this) {
    Currency.EUR -> PriceCurrency.EUR
    Currency.CHF -> PriceCurrency.CHF
}

/** The chosen currency, for the Value screen to load its prices in. */
@HiltViewModel
class ValueCurrencyViewModel @Inject constructor(preferences: AppPreferences) : ViewModel() {

    val currency: StateFlow<Currency> = preferences.currency
}
