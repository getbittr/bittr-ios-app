package com.bittr.android.feature.value

/**
 * The value screen's words, from the iOS `Language.swift` entries it reads, with
 * their ids recorded for the BIT-12 migration — the arrangement `ScannerCopy`
 * established. None of these carry a factual claim about the build.
 */
internal object ValueCopy {

    object Id {
        const val TITLE = "bitcoinvalue"
        const val HISTORICAL_DATA_ERROR = "historicaldata"
        const val OOPS = "oops"
        const val TRY_AGAIN = "tryagain"
        const val CANCEL = "cancel"
    }

    const val TITLE: String = "bitcoin value"

    const val HISTORICAL_DATA_ERROR: String =
        "We could not reach our server. Please try again."

    const val OOPS: String = "Oops!"
    const val TRY_AGAIN: String = "Try again"
    const val CANCEL: String = "Cancel"

    /**
     * `noDataLabel`. iOS's storyboard copy for an empty span; it is not in
     * `Language.swift`, so this is the Android wording for the same state rather
     * than a transcription.
     */
    const val NO_DATA: String = "No price history for this period."

    /**
     * The symbol the scrub card prefixes. It follows the value above the chart,
     * which is set from the chosen currency — so it is read back off the state
     * rather than passed down a second time and allowed to disagree.
     */
    fun currencySymbol(state: ValueUiState): String =
        state.currentValue?.substringBefore(' ')?.takeIf { it.isNotEmpty() }
            ?: PriceCurrency.EUR.symbol
}
