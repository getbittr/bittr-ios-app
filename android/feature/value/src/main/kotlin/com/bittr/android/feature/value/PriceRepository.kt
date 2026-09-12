package com.bittr.android.feature.value

import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** The display currency the chart is drawn in. iOS offers exactly these two. */
enum class PriceCurrency(
    val symbol: String,
    private val historicalPath: String,
    // Not `field`: inside a property getter that is the backing-field keyword, and
    // the constructor property is shadowed by it.
    internal val currentField: String,
) {
    EUR("€", "eur", "btc_eur"),
    CHF("CHF", "chf", "btc_chf");

    internal val historicalUrl: String get() = "$PRICE_API/historical/$historicalPath"
}

private const val PRICE_API = "https://getbittr.com/api/price/btc"

/** Everything the value screen needs for one load. */
internal data class PriceSnapshot(
    val series: Map<GraphSpan, List<PricePoint>>,
    val currentPrice: Double,
)

/**
 * The price data behind the chart.
 *
 * Two sequential requests, as on iOS: the historical buckets and then the current
 * price. They are sequential rather than concurrent because the second one's value
 * is appended to every span (`ValueViewController.swift:261-264`), so the series is
 * not complete until both have returned — and because the flow's 90-second wait was
 * written against two round trips taking, in the comment's own measurements, about
 * five and about nine seconds.
 */
internal interface PriceRepository {

    suspend fun load(currency: PriceCurrency, today: LocalDate): PriceSnapshot
}

internal class HttpPriceRepository : PriceRepository {

    override suspend fun load(currency: PriceCurrency, today: LocalDate): PriceSnapshot =
        withContext(Dispatchers.IO) {
            val historical = parsePriceSeries(get(currency.historicalUrl), today)

            val current = JSONObject(get(PRICE_API))
                .optString(currency.currentField)
                .toDoubleOrNull()
                ?: error("price response carried no ${currency.currentField}")

            // Each span ends on the value shown above the chart, which is what makes
            // the last point of the line and the big number agree.
            val now = java.time.Instant.now()
            val series = GraphSpan.entries.associateWith { span ->
                historical[span].orEmpty() + PricePoint(at = now, price = current)
            }

            PriceSnapshot(series = series, currentPrice = current)
        }

    private fun get(url: String): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) error("price API returned $code for $url")
            return connection.inputStream.use { it.reader().readText() }
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val TIMEOUT_MS = 30_000
    }
}
