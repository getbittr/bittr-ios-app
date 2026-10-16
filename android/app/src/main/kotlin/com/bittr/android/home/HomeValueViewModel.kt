package com.bittr.android.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.feature.value.loadWeekPrices
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * The week of prices behind Home's value card — iOS's `homeVC.graphPoints`.
 *
 * Fetched once for as long as Home is on the back stack, as iOS keeps `graphPoints` on the view
 * controller: opening Settings or Send and coming back does not fetch it again. A failed fetch
 * leaves the card without a line, and the next time Home is built it tries again.
 *
 * In the chosen currency, as iOS's `getCorrectBitcoinValue()`. Choosing another clears the line
 * and loads that currency's week, as iOS clears `graphPoints`, and a load still running for the
 * previous currency is dropped, as iOS's `graphLoadID` drops it.
 */
@HiltViewModel
class HomeValueViewModel @Inject constructor(
    environment: BittrEnvironment,
    http: HttpClient,
    preferences: AppPreferences,
) : ViewModel() {

    private val _week = MutableStateFlow<List<Double>?>(null)
    val week: StateFlow<List<Double>?> = _week.asStateFlow()

    init {
        viewModelScope.launch {
            preferences.currency.collectLatest { currency ->
                _week.value = null
                try {
                    _week.value = loadWeekPrices(environment, http, currency.priceCurrency())
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    // No line, as iOS shows none when `PriceHistory.load` throws.
                }
            }
        }
    }
}
