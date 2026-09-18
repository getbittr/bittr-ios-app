package com.bittr.android.feature.value

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The chart's vertical scale.
 *
 * Three properties matter. The domain is the series plus 8 % of its range each side,
 * and nothing else — pass 2 snapped it outward to round numbers, which on five years
 * reached 0 and squashed the curve into the top third. A label sits on a line at the
 * price it prints: the gutter is 32 dp, so labels are rounded to `110k`, and the lines
 * have to be at numbers that survive that rounding. And all four lines are inside the
 * domain, or they draw outside the frame.
 */
class PriceAxisTest {

    @Test
    fun `the domain is the series padded by eight percent of its range`() {
        val axis = PriceAxis.of(listOf(110_000.0, 113_400.0, 119_030.0))!!
        val pad = (119_030.0 - 110_000.0) * 0.08
        assertEquals(110_000.0 - pad, axis.lowest, 1e-6)
        assertEquals(119_030.0 + pad, axis.highest, 1e-6)
        assertEquals(PriceAxis.PADDING / (1 + 2 * PriceAxis.PADDING), axis.fractionOf(110_000.0).toDouble(), 1e-6)
    }

    @Test
    fun `five years is not anchored at zero`() {
        // The bitcoin_value/08 shape: a series whose low is a fraction of its high.
        val axis = PriceAxis.of(listOf(15_000.0, 60_000.0, 110_000.0))!!
        assertTrue("Domain starts at ${axis.lowest}", axis.lowest > 0)
        assertEquals(listOf("25k", "50k", "75k", "100k"), axis.ticks.map(axis::label))
    }

    @Test
    fun `four round gridlines sit inside the domain`() {
        listOf(
            listOf(110_000.0, 113_400.0, 119_030.0),
            listOf(98_600.0, 101_500.0),
            listOf(62_140.0, 64_020.0, 63_310.0),
            listOf(3_200.0, 69_000.0),
            listOf(100_050.0, 100_900.0),
        ).forEach { prices ->
            val axis = PriceAxis.of(prices)!!
            assertEquals(PriceAxis.GRIDLINES, axis.ticks.size)
            axis.ticks.forEach { tick ->
                assertTrue("$tick outside ${axis.lowest}..${axis.highest}", tick in axis.lowest..axis.highest)
                assertEquals("$tick is not a multiple of ${axis.step}", 0.0, Math.IEEEremainder(tick, axis.step), 1e-6)
            }
            val labels = axis.ticks.map(axis::label)
            assertEquals("Labels repeat: $labels", labels.size, labels.distinct().size)
            prices.forEach { assertTrue(axis.fractionOf(it) in 0f..1f) }
        }
    }

    @Test
    fun `when more than four lines fit, the four nearest the middle are kept`() {
        // 2k is the largest step with at least four lines here, and it fits five:
        // 110k…118k. The domain's middle is ~114.5k, so 112k…118k, not 110k…116k.
        val axis = PriceAxis.of(listOf(110_000.0, 113_400.0, 119_030.0))!!
        assertEquals(listOf("112k", "114k", "116k", "118k"), axis.ticks.map(axis::label))
    }

    @Test
    fun `steps under a thousand keep their labels distinct`() {
        val axis = PriceAxis.of(listOf(100_050.0, 100_900.0))!!
        val labels = axis.ticks.map(axis::label)
        assertEquals(labels.size, labels.distinct().size)
        assertTrue(labels.all { '.' in it })
    }

    @Test
    fun `a flat series gets a scale with the line across the middle`() {
        val axis = PriceAxis.of(listOf(100_000.0, 100_000.0))!!
        assertEquals(0.5f, axis.fractionOf(100_000.0), 1e-6f)
        assertEquals(4, axis.ticks.map(axis::label).distinct().size)
    }

    @Test
    fun `no prices, no axis`() {
        assertNull(PriceAxis.of(emptyList()))
    }

    @Test
    fun `the curve's round caps stay inside the plot`() {
        val range = curveXRange(width = 300f, strokeWidth = 9f)
        assertEquals(4.5f, range.start, 0f)
        assertEquals(295.5f, range.endInclusive, 0f)
    }

    @Test
    fun `the date labels read the ends and the thirds of the series`() {
        val points = (0..9).map { PricePoint(Instant.ofEpochSecond(it.toLong()), it.toDouble()) }
        assertEquals(listOf(0.0, 3.0, 6.0, 9.0), points.dateLabelPoints().map { it.price })
        assertTrue(emptyList<PricePoint>().dateLabelPoints().isEmpty())
    }
}
