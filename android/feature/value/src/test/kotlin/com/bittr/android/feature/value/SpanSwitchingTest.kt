package com.bittr.android.feature.value

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.Period

/**
 * Span switching — the logic BIT-99 names as worth testing on this screen.
 *
 * These run on the JVM with no Robolectric and no emulator: the span model is
 * deliberately free of Android types so that the part of this screen with actual
 * behaviour can be checked in seconds.
 */
class SpanSwitchingTest {

    private val loaded = ValueUiState(isFetchingData = false)

    @Test
    fun `a span tap while data is in flight is ignored`() {
        val fetching = ValueUiState(selectedSpan = GraphSpan.WEEK, isFetchingData = true)

        val after = fetching.selectSpan(GraphSpan.FIVE_YEARS)

        assertSame("changeSpan returns early while isFetchingData", fetching, after)
        assertEquals(GraphSpan.WEEK, after.selectedSpan)
    }

    @Test
    fun `a span tap after the data lands switches the span`() {
        assertEquals(GraphSpan.MONTH, loaded.selectSpan(GraphSpan.MONTH).selectedSpan)
        assertEquals(GraphSpan.YEAR, loaded.selectSpan(GraphSpan.YEAR).selectedSpan)
        assertEquals(GraphSpan.FIVE_YEARS, loaded.selectSpan(GraphSpan.FIVE_YEARS).selectedSpan)
    }

    @Test
    fun `the flow's m then y then 5y sequence lands on five years`() {
        // The tap order in shared/flows/features/bitcoin_value.yaml.
        val end = loaded
            .selectSpan(GraphSpan.MONTH)
            .selectSpan(GraphSpan.YEAR)
            .selectSpan(GraphSpan.FIVE_YEARS)

        assertEquals(GraphSpan.FIVE_YEARS, end.selectedSpan)
    }

    @Test
    fun `switching span does not disturb the fetch flag or the series`() {
        val withSeries = loaded.copy(
            series = mapOf(GraphSpan.YEAR to listOf(PricePoint(Instant.EPOCH, 1.0))),
        )

        val after = withSeries.selectSpan(GraphSpan.YEAR)

        assertFalse(after.isFetchingData)
        assertEquals(withSeries.series, after.series)
    }

    @Test
    fun `the selected button reads long and the rest read short`() {
        val onYear = loaded.selectSpan(GraphSpan.YEAR)

        assertEquals("1 year", onYear.titleFor(GraphSpan.YEAR))
        assertEquals("w", onYear.titleFor(GraphSpan.WEEK))
        assertEquals("m", onYear.titleFor(GraphSpan.MONTH))
        assertEquals("5y", onYear.titleFor(GraphSpan.FIVE_YEARS))
    }

    @Test
    fun `a span with no points is a drawable empty state, not a failure`() {
        val onlyWeek = loaded.copy(
            series = mapOf(GraphSpan.WEEK to listOf(PricePoint(Instant.EPOCH, 1.0))),
        )

        assertTrue(onlyWeek.hasData)
        assertFalse(onlyWeek.selectSpan(GraphSpan.FIVE_YEARS).hasData)
        assertTrue(onlyWeek.selectSpan(GraphSpan.FIVE_YEARS).visiblePoints.isEmpty())
    }

    @Test
    fun `an unrecognised button tag falls back to week, as changeSpan does`() {
        assertEquals(GraphSpan.WEEK, GraphSpan.fromRawValue(null))
        assertEquals(GraphSpan.WEEK, GraphSpan.fromRawValue(""))
        assertEquals(GraphSpan.WEEK, GraphSpan.fromRawValue("decade"))
    }

    @Test
    fun `raw values match the iOS enum the flow drives`() {
        assertEquals("week", GraphSpan.WEEK.rawValue)
        assertEquals("month", GraphSpan.MONTH.rawValue)
        assertEquals("year", GraphSpan.YEAR.rawValue)
        // Not "fiveYears" — iOS overrides this one case's raw value.
        assertEquals("5years", GraphSpan.FIVE_YEARS.rawValue)

        GraphSpan.entries.forEach {
            assertEquals(it, GraphSpan.fromRawValue(it.rawValue))
        }
    }
}

/** The parts of [GraphSpan] the chart reads when it draws, ported value-for-value. */
class GraphSpanTest {

    @Test
    fun `api indices match the historical payload's positions`() {
        assertEquals(2, GraphSpan.WEEK.apiIndex)
        assertEquals(3, GraphSpan.MONTH.apiIndex)
        assertEquals(6, GraphSpan.YEAR.apiIndex)
        assertEquals(7, GraphSpan.FIVE_YEARS.apiIndex)
    }

    @Test
    fun `start dates count back by the span's own unit`() {
        val from = LocalDate.of(2026, 3, 15)

        assertEquals(LocalDate.of(2026, 3, 8), GraphSpan.WEEK.startDate(from))
        assertEquals(LocalDate.of(2026, 2, 15), GraphSpan.MONTH.startDate(from))
        assertEquals(LocalDate.of(2025, 3, 15), GraphSpan.YEAR.startDate(from))
        assertEquals(LocalDate.of(2021, 3, 15), GraphSpan.FIVE_YEARS.startDate(from))
    }

    @Test
    fun `month arithmetic clamps rather than overflowing`() {
        // Calendar on iOS clamps 31 March minus one month to 28 February; so does
        // java.time. Worth pinning, because a naive day-count would give 3 March.
        assertEquals(
            LocalDate.of(2026, 2, 28),
            GraphSpan.MONTH.startDate(LocalDate.of(2026, 3, 31)),
        )
    }

    @Test
    fun `only the five year series is subsampled`() {
        assertEquals(1, GraphSpan.WEEK.sampleEvery)
        assertEquals(1, GraphSpan.MONTH.sampleEvery)
        assertEquals(1, GraphSpan.YEAR.sampleEvery)
        assertEquals(2, GraphSpan.FIVE_YEARS.sampleEvery)
    }

    @Test
    fun `ticks match iOS, and five years draws none`() {
        assertEquals(GraphSpan.Tick(Period.ofDays(2), "dd MMM", false), GraphSpan.WEEK.tick)
        assertEquals(GraphSpan.Tick(Period.ofDays(7), "dd MMM", false), GraphSpan.MONTH.tick)
        assertEquals(GraphSpan.Tick(Period.ofMonths(3), "MMM", true), GraphSpan.YEAR.tick)
        assertNull(GraphSpan.FIVE_YEARS.tick)
    }
}
