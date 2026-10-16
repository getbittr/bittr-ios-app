package com.bittr.android.feature.value

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import java.time.LocalDate
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** The display currency the chart is drawn in. iOS offers exactly these two. */
enum class PriceCurrency(
    val symbol: String,
    internal val historicalPath: String,
) {
    EUR("€", "eur"),
    CHF("CHF", "chf");
}

/** The endpoint path under the API base URL, per `ValueViewController.swift:239`. */
private const val PRICE_PATH = "price/btc"

/** Everything the value screen needs for one load. */
internal data class PriceSnapshot(
    val series: Map<GraphSpan, List<PricePoint>>,
    val currentPrice: Double,
)

/**
 * The price data behind the chart: the historical buckets and the current price, which is
 * appended to every span (`ValueViewController.swift:261-264`), so the series is not complete
 * until both have returned. [PriceHistory] is the live one.
 */
internal interface PriceRepository {

    suspend fun load(currency: PriceCurrency, today: LocalDate): PriceSnapshot
}

/**
 * The price history behind Home's value card and the Value screen, fetched once for both —
 * iOS's `PriceHistory.load(cache:)` (#97, #98).
 *
 * - **One fetch for both.** The parsed historical series are kept per currency for
 *   [FRESH_MILLIS], as iOS keeps its payloads for 15 minutes, so the Value screen reuses the
 *   series Home's card loaded and the other way round. Two loads at once share one fetch.
 * - **One current price for the app.** [currentPrice] is the app's own price source, so
 *   `GET /price/btc` is read once for the conversion rate, the card and the screen.
 * - **One endpoint at a time.** The current price is asked for first, so a load waits on a
 *   conversion fetch already in flight rather than racing it: the two price endpoints are
 *   never hit together, which is what made the backend answer 429 at launch.
 * - **Parsed off the main thread**, on [parsing].
 * - **Every load updates [weeks]**, which Home's card reads, so a Value screen load brings
 *   the card up to date too.
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
 *
 * @param currentPrice the current price of one bitcoin in a currency, or null when it could
 *   not be fetched.
 */
class PriceHistory(
    private val environment: BittrEnvironment,
    private val http: HttpClient,
    private val currentPrice: suspend (PriceCurrency) -> Double?,
    private val nowMillis: () -> Long = System::currentTimeMillis,
    private val parsing: CoroutineDispatcher = Dispatchers.Default,
) {

    private class Cached(val atMillis: Long, val series: Map<GraphSpan, List<PricePoint>>)

    private val lock = Mutex()
    private val historical = mutableMapOf<PriceCurrency, Cached>()

    private val _weeks = MutableStateFlow<Map<PriceCurrency, List<Double>>>(emptyMap())

    /** The latest week of prices per currency, oldest first and ending on the current price. */
    val weeks: StateFlow<Map<PriceCurrency, List<Double>>> = _weeks.asStateFlow()

    /** The week's prices in [currency] — what Home's value card draws. */
    suspend fun week(currency: PriceCurrency): List<Double> =
        load(currency, LocalDate.now()).series[GraphSpan.WEEK].orEmpty().map { it.price }

    internal suspend fun load(currency: PriceCurrency, today: LocalDate): PriceSnapshot {
        // The current price first — see the class comment on one endpoint at a time.
        val current = currentPrice(currency) ?: error("no current ${currency.name} price")
        val history = lock.withLock {
            historical[currency]?.takeIf { nowMillis() - it.atMillis < FRESH_MILLIS }?.series
                ?: fetchHistorical(currency, today).also { historical[currency] = Cached(nowMillis(), it) }
        }

        // Each span ends on the value shown above the chart, which is what makes
        // the last point of the line and the big number agree.
        val now = java.time.Instant.now()
        val series = GraphSpan.entries.associateWith { span ->
            history[span].orEmpty() + PricePoint(at = now, price = current)
        }
        _weeks.update { weeks -> weeks + (currency to series[GraphSpan.WEEK].orEmpty().map { it.price }) }
        return PriceSnapshot(series = series, currentPrice = current)
    }

    /**
     * A non-2xx throws here rather than at the seam, preserving what the screen already did:
     * `ValueScreen` wraps the load in `runCatching` and shows its retry state, and the price
     * API has no partial-failure semantics worth reading a status code for. Only a payload
     * that parsed is kept.
     */
    private suspend fun fetchHistorical(currency: PriceCurrency, today: LocalDate): Map<GraphSpan, List<PricePoint>> {
        val url = environment.url("$PRICE_PATH/historical/${currency.historicalPath}")
        val response = http.execute(HttpRequest(HttpMethod.GET, url))
        if (!response.isSuccessful) error("price API returned ${response.code} for $url")
        return withContext(parsing) { parsePriceSeries(response.body, today) }
    }

    companion object {
        /** iOS keeps a price payload for 15 minutes (`PriceHistory`). */
        const val FRESH_MILLIS: Long = 15 * 60 * 1000L
    }
}
