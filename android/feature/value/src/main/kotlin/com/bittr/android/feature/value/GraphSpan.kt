package com.bittr.android.feature.value

import java.time.LocalDate
import java.time.Period

/**
 * The four spans the Bitcoin value chart can be drawn over.
 *
 * Ported from `GraphSpan` in `ios/bittr/Value/ValueViewController.swift:15`. The
 * `rawValue`s are kept identical to iOS because they are what the span buttons carry
 * as their bound string and what `shared/flows/features/bitcoin_value.yaml` drives
 * through the test ids — a rename here is a silent flow break, not a compile error.
 */
enum class GraphSpan(val rawValue: String) {
    WEEK("week"),
    MONTH("month"),
    YEAR("year"),
    FIVE_YEARS("5years");

    /**
     * Where this span's series sits in the historical price API's payload.
     *
     * These are positional indices into a heterogeneous array, not a lookup by name,
     * so they are as fragile as they look — and they are fragile in exactly the same
     * way on iOS. Kept identical rather than improved: whatever the endpoint returns,
     * both clients have to read it the same way.
     */
    val apiIndex: Int
        get() = when (this) {
            WEEK -> 2
            MONTH -> 3
            YEAR -> 6
            FIVE_YEARS -> 7
        }

    /** The earliest date this span plots, counting back from [from]. */
    fun startDate(from: LocalDate): LocalDate = when (this) {
        WEEK -> from.minusDays(7)
        MONTH -> from.minusMonths(1)
        YEAR -> from.minusYears(1)
        FIVE_YEARS -> from.minusYears(5)
    }

    /** For the five-year series, only every second point is plotted. */
    val sampleEvery: Int
        get() = if (this == FIVE_YEARS) 2 else 1

    /** Axis ticks, or `null` for a span that draws none. */
    val tick: Tick?
        get() = when (this) {
            WEEK -> Tick(Period.ofDays(2), "dd MMM", onMonthStart = false)
            MONTH -> Tick(Period.ofDays(7), "dd MMM", onMonthStart = false)
            YEAR -> Tick(Period.ofMonths(3), "MMM", onMonthStart = true)
            FIVE_YEARS -> null
        }

    /** Shown on the span button while it is the selected one. */
    val longTitle: String
        get() = when (this) {
            WEEK -> "1 week"
            MONTH -> "1 month"
            YEAR -> "1 year"
            FIVE_YEARS -> "5 years"
        }

    /** Shown on the span button while it is not selected. */
    val shortTitle: String
        get() = when (this) {
            WEEK -> "w"
            MONTH -> "m"
            YEAR -> "y"
            FIVE_YEARS -> "5y"
        }

    data class Tick(val every: Period, val format: String, val onMonthStart: Boolean)

    companion object {
        /**
         * Resolves a span button's bound string, falling back to [WEEK] on anything
         * unrecognised — the same fallback as `changeSpan`
         * (`ValueViewController.swift:334`), which is what makes an unknown tag land
         * on a drawable chart instead of an empty one.
         */
        fun fromRawValue(rawValue: String?): GraphSpan =
            entries.firstOrNull { it.rawValue == rawValue } ?: WEEK
    }
}
