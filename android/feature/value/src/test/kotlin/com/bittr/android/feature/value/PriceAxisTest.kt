package com.bittr.android.feature.value

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The chart's gridline scale.
 *
 * The property that matters is that a label sits on a line at the price it prints: the
 * gutter is 32 dp, so labels are rounded to `110k`, and the scale has to put its lines
 * at numbers that survive that rounding. Plus the series has to fit between the
 * bottom and top lines, or the curve draws outside the frame.
 */
class PriceAxisTest {

    @Test
    fun `the series fits between four round gridlines`() {
        val prices = listOf(110_000.0, 113_400.0, 119_030.0)
        val axis = PriceAxis.of(prices)!!

        assertEquals(PriceAxis.GRIDLINES, axis.ticks.size)
        assertEquals(110_000.0, axis.lowest, 0.0)
        assertEquals(5_000.0, axis.step, 0.0)
        assertEquals(listOf("110k", "115k", "120k", "125k"), axis.ticks.map(axis::label))
        prices.forEach { assertTrue(axis.fractionOf(it) in 0f..1f) }
    }

    @Test
    fun `rounding the bottom down never leaves the top below the highest price`() {
        // 1k steps would fit the range (2.9k) but not once 98.6k rounds down to 98k.
        val axis = PriceAxis.of(listOf(98_600.0, 101_500.0))!!
        assertTrue(axis.lowest <= 98_600.0)
        assertTrue(axis.highest >= 101_500.0)
        assertEquals(listOf("98k", "100k", "102k", "104k"), axis.ticks.map(axis::label))
    }

    @Test
    fun `steps under a thousand keep their labels distinct`() {
        val axis = PriceAxis.of(listOf(100_050.0, 100_900.0))!!
        val labels = axis.ticks.map(axis::label)
        assertEquals(labels.size, labels.distinct().size)
        assertEquals("100.0k", labels.first())
    }

    @Test
    fun `a flat series still gets a scale, with the line on the bottom gridline`() {
        val axis = PriceAxis.of(listOf(100_000.0, 100_000.0))!!
        assertEquals(0f, axis.fractionOf(100_000.0), 0f)
        assertEquals(4, axis.ticks.map(axis::label).distinct().size)
    }

    @Test
    fun `no prices, no axis`() {
        assertNull(PriceAxis.of(emptyList()))
    }

    @Test
    fun `the date labels read the ends and the thirds of the series`() {
        val points = (0..9).map { PricePoint(Instant.ofEpochSecond(it.toLong()), it.toDouble()) }
        assertEquals(listOf(0.0, 3.0, 6.0, 9.0), points.dateLabelPoints().map { it.price })
        assertTrue(emptyList<PricePoint>().dateLabelPoints().isEmpty())
    }
}
