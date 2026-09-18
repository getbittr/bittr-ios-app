package com.bittr.android.feature.value

import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * The chart's vertical scale: the series with 8 % of its range above and below, and
 * four gridlines at round prices inside that.
 *
 * iOS draws no axis at all — the curve spans min to max of the series and the reader
 * has only the scrub card to learn what any height means. The design review
 * (2026-09-18, `bitcoin_value/04`–`08`) asked for four gridlines with labels, and a
 * label only means something if it sits *on* its gridline: labelling min-to-max
 * quarters would print `110,347` next to a line and then round it to `110k` to fit the
 * 32 dp gutter, which is a number the line is not at. So the gridlines go at round
 * prices.
 *
 * Pass 2 went further and *widened the scale* to those round prices, which is what the
 * third review (`bitcoin_value/08`) caught: on five years the round step that covers
 * the series is a large one, rounding the bottom down to a multiple of it reached `0`,
 * and the curve was squeezed into the top third of the plot. So the domain is now the
 * data's — [lowest] and [highest] are min and max padded by [PADDING] of the range,
 * never snapped — and the round numbers are fitted *inside* it instead. The gridlines
 * therefore no longer sit at the plot's top and bottom edges, which is why they, their
 * labels, the curve and the scrub card all read their y off [fractionOf].
 *
 * Steps are 1, 2, 3, 4, 5, 6 or 8 × 10ⁿ. The in-betweens are there because 1-2-5 alone
 * often fits five lines or three, and four of five leaves one end of the plot bare.
 * 2.5 is allowed from 25 000 up (`25k 50k 75k 100k`, the natural five-year scale) and
 * not below: 2 500 is the step that produces `112.5k`, which does not fit the gutter at
 * the scale's 13 sp floor.
 */
internal data class PriceAxis(
    val lowest: Double,
    val highest: Double,
    val step: Double,
    val ticks: List<Double>,
) {

    /** Where [price] sits on this scale, 0 at the bottom of the plot and 1 at the top. */
    fun fractionOf(price: Double): Float = ((price - lowest) / (highest - lowest)).toFloat()

    /**
     * A gridline's label, short enough for the 32 dp gutter: `110k`, or `98.5k` when
     * the step is under a thousand and whole thousands would repeat. No currency
     * symbol — the price above the chart already says which currency this is, and the
     * symbol is what would not fit.
     */
    fun label(tick: Double): String {
        if (tick < 1_000) return String.format(Locale.ENGLISH, "%.0f", tick)
        // As many decimals as the step has in thousands, so no two lines read the same
        // and none reads a number it is not at.
        val decimals = (0..1).firstOrNull { d ->
            val scaled = step / 1_000 * 10.0.pow(d)
            abs(scaled - scaled.roundToLong()) < EPSILON
        } ?: 2
        return String.format(Locale.ENGLISH, "%.${decimals}fk", tick / 1_000)
    }

    companion object {
        /** The review's four. */
        const val GRIDLINES = 4

        /** The review's headroom above the highest price and below the lowest. */
        const val PADDING = 0.08

        fun of(prices: List<Double>): PriceAxis? {
            if (prices.isEmpty()) return null
            val low = prices.min()
            val high = prices.max()
            // A flat series has no range to pad by. A fifth of a percent of the price
            // either side puts the line across the middle of the plot, with gridlines
            // close around it and their labels still distinct.
            val pad = ((high - low) * PADDING).takeIf { it > 0 }
                ?: (abs(low) * 0.002).coerceAtLeast(2.0)
            return PriceAxis(lowest = low - pad, highest = high + pad, step = 0.0, ticks = emptyList())
                .withTicks()
        }

        /**
         * The largest round step that puts exactly four gridlines inside the domain.
         * When none does, the largest that puts in more, and the four of those whose
         * middle is nearest the plot's — so the lines spread over the plot rather than
         * bunching at one end.
         */
        private fun PriceAxis.withTicks(): PriceAxis {
            val magnitude = floor(log10((highest - lowest) / (GRIDLINES - 1)))
            val fitting = (-1..1)
                .flatMap { shift -> NICE_MANTISSAS.map { it * 10.0.pow(magnitude + shift) } }
                .filter { it >= QUARTER_STEP_FLOOR || !it.isQuarterStep() }
                .sortedDescending()
                .map { it to ticksInside(it) }
            val (step, inside) = fitting.firstOrNull { it.second.size == GRIDLINES }
                ?: fitting.first { it.second.size > GRIDLINES }
            val centre = (lowest + highest) / 2
            val start = (0..inside.size - GRIDLINES).minBy { first ->
                abs((inside[first] + inside[first + GRIDLINES - 1]) / 2 - centre)
            }
            return copy(step = step, ticks = inside.subList(start, start + GRIDLINES))
        }

        private fun PriceAxis.ticksInside(step: Double): List<Double> {
            val first = ceil(lowest / step - EPSILON) * step
            val count = floor((highest - first) / step + EPSILON).toInt() + 1
            return List(count.coerceAtLeast(0)) { first + step * it }
        }

        private val NICE_MANTISSAS = listOf(1.0, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0)

        /** The smallest 2.5 × 10ⁿ step whose gridlines are all whole thousands. */
        private const val QUARTER_STEP_FLOOR = 25_000.0

        private fun Double.isQuarterStep(): Boolean {
            val mantissa = this / 10.0.pow(floor(log10(this)))
            return abs(mantissa - 2.5) < 1e-6
        }

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
