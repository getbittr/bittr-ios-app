package com.bittr.android.receive

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.preferences.Currency
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {

    private val lock = Mutex()
    private var body: String? = null
    private var readAtMillis = 0L

    /**
     * Null when the price could not be fetched or read.
     *
     * One reading serves every caller for [FRESH_MILLIS]. Home, the profit summary, Receive, Send,
     * the swap screen and a transaction all ask for a price, each currency separately, and they ask
     * together — a single wallet reading set off four `GET /price/btc` inside 100 ms, and staging
     * answered the fourth with 429, which is what `bitcoin_value.yaml` then failed on. iOS fetches
     * its conversion rates once per sync and reads the cached value everywhere else.
     */
    suspend fun price(currency: Currency): Double? = runCatching {
        val json = lock.withLock {
            val cached = body
            if (cached != null && nowMillis() - readAtMillis < FRESH_MILLIS) {
                cached
            } else {
                val response = http.execute(HttpRequest(HttpMethod.GET, environment.url(PRICE_PATH)))
                if (!response.isSuccessful) return@runCatching null
                response.body.also {
                    body = it
                    readAtMillis = nowMillis()
                }
            }
        }
        JSONObject(json).optString(field(currency)).toDoubleOrNull()
    }.getOrNull()

    private fun field(currency: Currency): String = when (currency) {
        Currency.EUR -> "btc_eur"
        Currency.CHF -> "btc_chf"
    }

    private companion object {
        const val PRICE_PATH = "price/btc"

        /** How long one reading serves. A price older than this is refetched. */
        const val FRESH_MILLIS = 30_000L
    }
}
