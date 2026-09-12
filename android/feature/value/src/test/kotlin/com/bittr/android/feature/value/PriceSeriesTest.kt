package com.bittr.android.feature.value

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Parsing the historical-price payload.
 *
 * Robolectric because `org.json` has no implementation on a plain JVM. The payload
 * shape — an array of interval buckets, each span reading its own index — is
 * documented at length in `ValueViewController.swift:199-219`, and the fixture below
 * is that shape in miniature.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PriceSeriesTest {

    private val today = LocalDate.of(2026, 9, 12)

    /** Buckets 0-8, with the four the spans read filled in. */
    private fun payload(
        week: List<Pair<String, String>>,
        month: List<Pair<String, String>> = week,
        year: List<Pair<String, String>> = week,
        fiveYears: List<Pair<String, String>> = week,
    ): String {
        fun bucket(points: List<Pair<String, String>>) = buildString {
            append("""{"interval":"x","data":[""")
            append(
                points.joinToString(",") { (at, price) ->
                    """{"time_iso8601":"$at","price":"$price"}"""
                },
            )
            append("]}")
        }
        val empty = """{"interval":"x","data":[]}"""
        val buckets = MutableList(9) { empty }
        buckets[GraphSpan.WEEK.apiIndex] = bucket(week)
        buckets[GraphSpan.MONTH.apiIndex] = bucket(month)
        buckets[GraphSpan.YEAR.apiIndex] = bucket(year)
        buckets[GraphSpan.FIVE_YEARS.apiIndex] = bucket(fiveYears)
        return buckets.joinToString(",", prefix = "[", postfix = "]")
    }

    @Test
    fun `each span reads its own bucket`() {
        val json = payload(
            week = listOf("2026-09-10T00:00:00Z" to "100", "2026-09-11T00:00:00Z" to "110"),
            month = listOf(
                "2026-09-01T00:00:00Z" to "200",
                "2026-09-05T00:00:00Z" to "210",
                "2026-09-09T00:00:00Z" to "220",
            ),
        )

        val series = parsePriceSeries(json, today, ZoneOffset.UTC)

        assertEquals(listOf(100.0), series.getValue(GraphSpan.WEEK).map { it.price })
        assertEquals(listOf(200.0, 210.0), series.getValue(GraphSpan.MONTH).map { it.price })
    }

    @Test
    fun `points older than the span are dropped`() {
        val json = payload(
            week = listOf(
                "2026-01-01T00:00:00Z" to "1",
                "2026-09-08T00:00:00Z" to "2",
                "2026-09-10T00:00:00Z" to "3",
                "2026-09-11T00:00:00Z" to "4",
            ),
        )

        val week = parsePriceSeries(json, today, ZoneOffset.UTC).getValue(GraphSpan.WEEK)
        assertEquals(
            "A week's bucket holds more than a week; the January point is out of range " +
                "and the last surviving one is the API's copy of the live price.",
            listOf(2.0, 3.0),
            week.map { it.price },
        )
    }

    /**
     * The five-year series plots every second point, counted over what survived the
     * cutoff rather than over the raw array (`ValueViewController.swift:298-301`) —
     * sampling the raw array instead would shift which points are kept whenever the
     * bucket's leading history changes length.
     */
    @Test
    fun `the five-year series is sampled every other point`() {
        val points = (1..7).map { "202${it}-01-01T00:00:00Z" to "$it" }
        val json = payload(week = emptyList(), fiveYears = points)

        val series = parsePriceSeries(json, today, ZoneOffset.UTC)
            .getValue(GraphSpan.FIVE_YEARS)

        assertEquals(
            "Kept: 2022, 2024, 2026 (2021 predates the five-year cutoff), then the last " +
                "one is dropped as the API's copy of the live price.",
            listOf(2.0, 4.0),
            series.map { it.price },
        )
    }

    @Test
    fun `an empty bucket is an empty series rather than a failure`() {
        val series = parsePriceSeries(payload(week = emptyList()), today, ZoneOffset.UTC)
        assertEquals(emptyList<PricePoint>(), series.getValue(GraphSpan.WEEK))

        val state = ValueUiState(series = series, isFetchingData = false)
        assertTrue(
            "The screen draws noDataLabel rather than raising — other spans may have data.",
            !state.hasData,
        )
    }

    @Test
    fun `a malformed point is skipped rather than failing the whole span`() {
        val json = """
            [{},{},{"interval":"x","data":[
              {"time_iso8601":"not-a-date","price":"1"},
              {"time_iso8601":"2026-09-10T00:00:00Z","price":"2"},
              {"time_iso8601":"2026-09-11T00:00:00Z","price":"3"}
            ]}]
        """.trimIndent()

        val week = parsePriceSeries(json, today, ZoneOffset.UTC).getValue(GraphSpan.WEEK)
        assertEquals(listOf(2.0), week.map { it.price })
    }

    @Test
    fun `a price arriving as a number is read too`() {
        val json = """
            [{},{},{"interval":"x","data":[
              {"time_iso8601":"2026-09-10T00:00:00Z","price":98000.5},
              {"time_iso8601":"2026-09-11T00:00:00Z","price":"99000"}
            ]}]
        """.trimIndent()

        assertEquals(
            "iOS reads price as a String only; a bucket that switched to numbers would " +
                "empty the Android chart and leave iOS alone, which nobody would look for.",
            listOf(98000.5),
            parsePriceSeries(json, today, ZoneOffset.UTC).getValue(GraphSpan.WEEK).map { it.price },
        )
    }

    @Test
    fun `a short payload leaves the spans it cannot fill absent`() {
        val series = parsePriceSeries("[{},{},{\"data\":[]}]", today, ZoneOffset.UTC)
        assertTrue(GraphSpan.WEEK in series)
        assertTrue(
            "Bucket 7 is not there, so the five-year span has no entry — and the screen " +
                "reads an absent span as empty, not as an error.",
            GraphSpan.FIVE_YEARS !in series,
        )
    }

    @Test
    fun `the price is rounded and grouped`() {
        assertEquals("98,451", formatPrice("98450.7", Locale.UK))
        assertEquals("98,450", formatPrice(98_450.2, Locale.UK))
        assertEquals(
            "iOS's own fallback for a value that does not parse; matching it keeps a " +
                "broken response looking identical on both platforms.",
            "0",
            formatPrice("not a number", Locale.UK),
        )
    }

    @Test
    fun `the profit badge truncates as iOS does`() {
        assertEquals("19 %", profitPercentage(listOf(100.0, 119.9)))
        assertEquals("-20 %", profitPercentage(listOf(100.0, 80.0)))
        assertEquals("0 %", profitPercentage(listOf(100.0, 100.0)))
        assertNull("No points, no badge — and no badge is the flow's \"not loaded yet\".", profitPercentage(emptyList()))
    }

    @Test
    fun `a zero first price does not divide by zero`() {
        assertEquals("0 %", profitPercentage(listOf(0.0, 100.0)))
    }

    @Test
    fun `the scrub resolves a touch to a point and clamps at both edges`() {
        val points = (0..9).map { PricePoint(at = java.time.Instant.EPOCH, price = it.toDouble()) }

        assertEquals(0.0, points.scrub(x = 0f, width = 100f)!!.point.price, 0.0)
        assertEquals(9.0, points.scrub(x = 100f, width = 100f)!!.point.price, 0.0)
        assertEquals(
            "Past the right edge clamps to the last point rather than indexing out.",
            9.0,
            points.scrub(x = 500f, width = 100f)!!.point.price,
            0.0,
        )
        assertEquals(5.0, points.scrub(x = 55f, width = 100f)!!.point.price, 0.0)

        assertNull(emptyList<PricePoint>().scrub(x = 10f, width = 100f))
        assertNull("A chart that has not been measured yet.", points.scrub(x = 10f, width = 0f))
    }
}
