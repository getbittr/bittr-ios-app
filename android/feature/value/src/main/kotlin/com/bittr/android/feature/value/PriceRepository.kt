package com.bittr.android.feature.value

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import java.time.LocalDate
import org.json.JSONObject

/** The display currency the chart is drawn in. iOS offers exactly these two. */
enum class PriceCurrency(
    val symbol: String,
    internal val historicalPath: String,
    // Not `field`: inside a property getter that is the backing-field keyword, and
    // the constructor property is shadowed by it.
    internal val currentField: String,
) {
    EUR("€", "eur", "btc_eur"),
    CHF("CHF", "chf", "btc_chf");
}

/** The endpoint path under the API base URL, per `ValueViewController.swift:239`. */
private const val PRICE_PATH = "price/btc"

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

/**
 * The live implementation, reading from the backend [environment] names.
 *
 * ### Why it takes an environment instead of holding a URL
 *
 * It used to hold `"https://getbittr.com/api/price/btc"` as a constant, which meant
 * the regtest build (`com.bittr.android.regtest`) read the **production** price API.
 * That is the bug BIT-32 is filed for, reproduced on Android: the iOS call site this
 * screen is ported from, `ValueViewController.swift:239`, is one of the three BIT-32
 * names. It arrived here with the Wave 1 screens rather than being decided.
 *
 * Price is the harmless end of that class — an unauthenticated GET. The sibling on
 * the same list is not: `DeviceViewController.swift:283` reads `/notifications`,
 * authenticated by a lightning-pubkey signature, so the same mistake there is a
 * debug build reading real customers' payout state. `ApiBaseUrlGuardTest` in `:app`
 * is what stops the next one, and this class is why it was written (BIT-41 item 1).
 */
internal class HttpPriceRepository(
    private val environment: BittrEnvironment,
    private val http: HttpClient,
) : PriceRepository {

    override suspend fun load(currency: PriceCurrency, today: LocalDate): PriceSnapshot {
        // No `withContext(Dispatchers.IO)` any more: HttpClient moves to a background
        // dispatcher itself, so the choice sits with the one implementation rather
        // than with every call site that happens to make a request.
        val historical = parsePriceSeries(
            get("$PRICE_PATH/historical/${currency.historicalPath}"),
            today,
        )

        val current = JSONObject(get(PRICE_PATH))
            .optString(currency.currentField)
            .toDoubleOrNull()
            ?: error("price response carried no ${currency.currentField}")

        // Each span ends on the value shown above the chart, which is what makes
        // the last point of the line and the big number agree.
        val now = java.time.Instant.now()
        val series = GraphSpan.entries.associateWith { span ->
            historical[span].orEmpty() + PricePoint(at = now, price = current)
        }

        return PriceSnapshot(series = series, currentPrice = current)
    }

    /**
     * A non-2xx throws here rather than at the seam, preserving what this screen
     * already did: `ValueScreen` wraps the load in `runCatching` and shows its retry
     * state, and the price API has no partial-failure semantics worth reading a
     * status code for. The endpoints that *do* — `api-contract` §2.3 needs to tell a
     * rate limit from a bad signature — read `HttpResponse.code` instead.
     */
    private suspend fun get(path: String): String {
        val url = environment.url(path)
        val response = http.execute(HttpRequest(HttpMethod.GET, url))
        if (!response.isSuccessful) error("price API returned ${response.code} for $url")
        return response.body
    }
}
