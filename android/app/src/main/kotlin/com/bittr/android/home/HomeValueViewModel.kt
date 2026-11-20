package com.bittr.android.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.feature.value.PriceHistory
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * The week of prices behind Home's value card — iOS's `homeVC.graphPoints`.
 *
 * Loaded once for as long as Home is on the back stack, as iOS keeps `graphPoints` on the view
 * controller: opening Settings or Send and coming back does not load it again. A failed load
 * leaves the card without a line, and the next time Home is built it tries again.
 *
 * In the chosen currency, as iOS's `getCorrectBitcoinValue()`. Choosing another loads that
 * currency's week, and a load still running for the previous currency is dropped, as iOS's
 * `graphLoadID` drops it. The line is read from [PriceHistory.weeks], so a Value screen load
 * brings it up to date too, as iOS's Value screen sets Home's graph points.
 */
@HiltViewModel
class HomeValueViewModel @Inject constructor(
    history: PriceHistory,
    preferences: AppPreferences,
) : ViewModel() {

    val week: StateFlow<List<Double>?> = combine(preferences.currency, history.weeks) { currency, weeks ->
        weeks[currency.priceCurrency()]
    }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    init {
        viewModelScope.launch {
            preferences.currency.collectLatest { currency ->
                try {
                    history.week(currency.priceCurrency())
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    // No line, as iOS shows none when `PriceHistory.load` throws.
                }
            }
        }
    }
}
