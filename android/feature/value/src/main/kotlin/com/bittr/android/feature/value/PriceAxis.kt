package com.bittr.android.feature.value

import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/**
 * The chart's vertical scale: four gridlines at round prices, with the series inside
 * them.
 *
 * iOS draws no axis at all — the curve spans min to max of the series and the reader
 * has only the scrub card to learn what any height means. The design review
 * (2026-09-18, `bitcoin_value/04`–`08`) asked for four gridlines with labels, and a
 * label only means something if it sits *on* its gridline. Labelling min-to-max
 * quarters would print `110,347` next to a line and then round it to `110k` to fit the
 * 32 dp gutter, which is a number the line is not at. So the scale is widened to round
 * values instead, and the curve is laid out on that scale rather than on the data's
 * own range.
 *
 * That costs the curve some height — it no longer touches the top and bottom of the
 * plot — and it is the one reason the curve and the scrub card both read their y off
 * [fractionOf] rather than off the series: the card rides the line, so the two have to
 * agree on what a price's height is.
 *
 * Steps are 1, 2 or 5 × 10ⁿ. 2.5 is left out on purpose: it is the step that produces
 * `112.5k`, which does not fit the gutter at the scale's 13 sp floor.
 */
internal data class PriceAxis(val lowest: Double, val step: Double) {

    val highest: Double get() = lowest + step * (GRIDLINES - 1)

    /** The gridlines' prices, bottom first. */
    val ticks: List<Double> get() = List(GRIDLINES) { lowest + step * it }

    /** Where [price] sits on this scale, 0 at the bottom gridline and 1 at the top. */
    fun fractionOf(price: Double): Float = ((price - lowest) / (highest - lowest)).toFloat()

    /**
     * A gridline's label, short enough for the 32 dp gutter: `110k`, or `98.5k` when
     * the step is under a thousand and whole thousands would repeat. No currency
     * symbol — the price above the chart already says which currency this is, and the
     * symbol is what would not fit.
     */
    fun label(tick: Double): String {
        if (tick < 1_000) return String.format(Locale.ENGLISH, "%.0f", tick)
        val decimals = when {
            step >= 1_000 -> 0
            step >= 100 -> 1
            else -> 2
        }
        return String.format(Locale.ENGLISH, "%.${decimals}fk", tick / 1_000)
    }

    companion object {
        /** The review's four; the plot is split into three bands between them. */
        const val GRIDLINES = 4

        fun of(prices: List<Double>): PriceAxis? {
            if (prices.isEmpty()) return null
            val low = prices.min()
            val high = prices.max()
            // A flat series has no range to divide. A step of a thousandth of the price
            // keeps its gridlines close together and its labels distinct, and puts the
            // line on the bottom gridline — where the old min/max scale drew it too.
            val raw = ((high - low) / (GRIDLINES - 1)).takeIf { it > 0 }
                ?: (kotlin.math.abs(low) / 1_000).coerceAtLeast(1.0)
            var step = niceAtLeast(raw)
            var lowest = floor(low / step) * step
            // Rounding the bottom down can push the top below the highest price; the
            // next step up always recovers it, and rarely needs more than one pass.
            while (lowest + step * (GRIDLINES - 1) < high) {
                step = niceAtLeast(step * 1.000_001)
                lowest = floor(low / step) * step
            }
            return PriceAxis(lowest = lowest, step = step)
        }

        private fun niceAtLeast(value: Double): Double {
            val magnitude = 10.0.pow(floor(log10(value)))
            val mantissa = value / magnitude
            val nice = NICE_MANTISSAS.first { it >= mantissa - EPSILON }
            return nice * magnitude
        }

        private val NICE_MANTISSAS = listOf(1.0, 2.0, 5.0, 10.0)
        private const val EPSILON = 1e-9
    }
}

/** The review's four date labels under the plot: the ends and the two thirds. */
internal const val DATE_LABELS = 4

/**
 * The samples the date labels read, at 0, ⅓, ⅔ and 1 of the series by index — which is
 * also by x, because the curve spaces samples evenly.
 */
internal fun List<PricePoint>.dateLabelPoints(): List<PricePoint> =
    if (isEmpty()) emptyList()
    else List(DATE_LABELS) { this[Math.round(it * (size - 1) / (DATE_LABELS - 1f))] }

/**
 * How a span's date labels read.
 *
 * Week and month take [GraphSpan.tick]'s `dd MMM`, which is iOS's own tick format.
 * Year departs from it: iOS's `MMM` is fine on a ticked axis every three months, but
 * with four labels at thirds of a year the first and last are the same month —
 * `Sep … Sep` — so the year is added. Five years has no iOS tick at all
 * ([GraphSpan.tick] is `null`); the year alone is what distinguishes its labels.
 */
internal fun GraphSpan.axisDateFormat(): DateTimeFormatter =
    DateTimeFormatter.ofPattern(
        when (this) {
            GraphSpan.YEAR -> "MMM yy"
            GraphSpan.FIVE_YEARS -> "yyyy"
            else -> tick?.format ?: "dd MMM"
        },
        Locale.ENGLISH,
    ).withZone(ZoneId.systemDefault())
