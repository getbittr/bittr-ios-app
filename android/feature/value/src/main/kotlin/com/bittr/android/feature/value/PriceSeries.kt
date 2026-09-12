package com.bittr.android.feature.value

import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/**
 * Turns the historical-price payload into the series the chart draws.
 *
 * Ported from `pricePoints` (`ValueViewController.swift:292-310`). The payload is a
 * heterogeneous array of interval buckets — minute, hourly, daily, monthly,
 * semi-annual, YTD, 1 year, 5 years, max — and each span reads the bucket at its own
 * fixed position ([GraphSpan.apiIndex]). Positional, and as fragile as it looks, but
 * both clients have to read the same response the same way.
 *
 * Three behaviours are carried deliberately, because each one changes what the chart
 * shows rather than only how it is built:
 *
 * 1. **Points older than the span's start are dropped.** A bucket holds more history
 *    than the span plots.
 * 2. **The 5-year series is sampled every other point** — counted over the points
 *    that survived the cutoff, not over the raw array.
 * 3. **The last surviving point is dropped.** It is the API's own copy of the latest
 *    price, and the screen appends the *live* one instead, so keeping both would
 *    draw the same moment twice.
 */
internal fun parsePriceSeries(
    json: String,
    today: LocalDate,
    zone: ZoneId = ZoneId.systemDefault(),
): Map<GraphSpan, List<PricePoint>> {
    val buckets = JSONArray(json)
    val series = LinkedHashMap<GraphSpan, List<PricePoint>>()

    GraphSpan.entries.forEach { span ->
        if (buckets.length() <= span.apiIndex) return@forEach
        val raw = buckets.optJSONObject(span.apiIndex)?.optJSONArray("data") ?: return@forEach
        series[span] = pricePoints(raw, span, span.startDate(today), zone)
    }
    return series
}

private fun pricePoints(
    raw: JSONArray,
    span: GraphSpan,
    cutoff: LocalDate,
    zone: ZoneId,
): List<PricePoint> {
    val points = mutableListOf<PricePoint>()
    var kept = 0

    for (index in 0 until raw.length()) {
        val point = raw.optJSONObject(index) ?: continue
        val at = point.optString("time_iso8601").toInstantOrNull() ?: continue
        if (!at.isAfter(cutoff.atStartOfDay(zone).toInstant())) continue

        kept++
        if ((kept - 1) % span.sampleEvery != 0) continue

        val price = point.priceOrNull() ?: continue
        points += PricePoint(at = at, price = price)
    }

    // The API's copy of the latest price. See the class note.
    if (points.isNotEmpty()) points.removeAt(points.lastIndex)
    return points
}

/**
 * The price field.
 *
 * iOS reads it as a `String` and would drop a point typed as a number
 * (`ValueViewController.swift:302`). Both are accepted here: a bucket that started
 * arriving as JSON numbers would empty the Android chart and leave the iOS one
 * alone, which is a difference nobody would look for.
 */
private fun JSONObject.priceOrNull(): Double? = when {
    isNull("price") -> null
    else -> optString("price").toDoubleOrNull() ?: optDouble("price").takeIf { !it.isNaN() }
}

private fun String.toInstantOrNull(): Instant? =
    if (isEmpty()) null else runCatching { Instant.parse(this) }.getOrElse { error ->
        if (error is DateTimeParseException) null else throw error
    }

/**
 * The price as the screen shows it: rounded to whole units, grouped by the device's
 * locale.
 *
 * Ported from `formatEuroValue` and its `NumberFormatter`
 * (`ValueViewController.swift:312-328`), including the "0" fallback for a value that
 * does not parse — the label reading `0` is iOS's own answer, and matching it keeps
 * a broken response looking identical on both platforms.
 */
internal fun formatPrice(value: String, locale: Locale = Locale.getDefault()): String {
    val number = value.toDoubleOrNull() ?: return "0"
    return NumberFormat.getNumberInstance(locale).apply {
        maximumFractionDigits = 0
    }.format(Math.round(number))
}

internal fun formatPrice(value: Double, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getNumberInstance(locale).apply {
        maximumFractionDigits = 0
    }.format(Math.round(value))

/**
 * The percentage badge: the move from the first plotted point to the last.
 *
 * `drawGraph` truncates rather than rounds — `Int(profit)` — so a 1.9 % rise reads
 * "1 %" on iOS. Kept, because the two screens sitting side by side showing 1 % and
 * 2 % is a worse outcome than one of them being a fraction optimistic.
 */
internal fun profitPercentage(prices: List<Double>): String? {
    if (prices.isEmpty()) return null
    val first = prices.first()
    val profit = if (first > 0) (prices.last() - first) / first * 100 else 0.0
    return "${profit.toInt()} %"
}
