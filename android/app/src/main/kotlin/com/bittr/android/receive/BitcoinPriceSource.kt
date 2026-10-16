package com.bittr.android.receive

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.preferences.Currency
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * The current price of one bitcoin in the display currency — iOS's `didFetchConversionRates()`
 * (`LoadWalletData.swift:288`), `GET /price/btc` read for `btc_eur` or `btc_chf`.
 *
 * The value chart's `PriceHistory` reads its current price from here too, so `GET /price/btc`
 * is fetched once for the whole app and the chart and Home cannot disagree about it.
 */
class BitcoinPriceSource(
    private val environment: BittrEnvironment,
    private val http: HttpClient,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {

    private val lock = Mutex()
    private var prices: Map<Currency, Double>? = null
    private var readAtMillis = 0L

    private val _freshReadings = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /**
     * Emits after each new reading from the network — iOS's Value screen setting Home's rates
     * when it loads. Home reads the price again then; the reading it gets is this one, cached.
     */
    val freshReadings: Flow<Unit> = _freshReadings.asSharedFlow()

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
        val read = lock.withLock {
            val cached = prices
            if (cached != null && nowMillis() - readAtMillis < FRESH_MILLIS) {
                cached
            } else {
                val response = http.execute(HttpRequest(HttpMethod.GET, environment.url(PRICE_PATH)))
                if (!response.isSuccessful) return@runCatching null
                // Parsed before it is kept: a reply without every currency's price is used
                // for what it has, but not cached, so the next caller asks again.
                parse(response.body).also { parsed ->
                    if (parsed.keys.containsAll(Currency.entries)) {
                        prices = parsed
                        readAtMillis = nowMillis()
                        _freshReadings.tryEmit(Unit)
                    }
                }
            }
        }
        read[currency]
    }.getOrNull()

    private fun parse(body: String): Map<Currency, Double> {
        val json = JSONObject(body)
        return Currency.entries.mapNotNull { currency ->
            json.optString(field(currency)).toDoubleOrNull()?.let { currency to it }
        }.toMap()
    }

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
