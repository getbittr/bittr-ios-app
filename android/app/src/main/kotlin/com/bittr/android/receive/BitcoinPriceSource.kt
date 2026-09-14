package com.bittr.android.receive

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.preferences.Currency
import org.json.JSONObject

/**
 * The current price of one bitcoin in the display currency — iOS's `didFetchConversionRates()`
 * (`LoadWalletData.swift:288`), `GET /price/btc` read for `btc_eur` or `btc_chf`.
 *
 * Read the same way `HttpPriceRepository` reads the same endpoint for the value chart, so
 * the two cannot disagree about one response.
 */
class BitcoinPriceSource(
    private val environment: BittrEnvironment,
    private val http: HttpClient,
) {

    /** Null when the price could not be fetched or read. */
    suspend fun price(currency: Currency): Double? = runCatching {
        val response = http.execute(HttpRequest(HttpMethod.GET, environment.url(PRICE_PATH)))
        if (!response.isSuccessful) return@runCatching null
        JSONObject(response.body).optString(field(currency)).toDoubleOrNull()
    }.getOrNull()

    private fun field(currency: Currency): String = when (currency) {
        Currency.EUR -> "btc_eur"
        Currency.CHF -> "btc_chf"
    }

    private companion object {
        const val PRICE_PATH = "price/btc"
    }
}
