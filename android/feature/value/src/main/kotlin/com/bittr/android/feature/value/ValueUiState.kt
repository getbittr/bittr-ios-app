package com.bittr.android.feature.value

import java.time.Instant

/** One point on the chart: a price at a moment. */
data class PricePoint(val at: Instant, val price: Double)

/**
 * State of the Bitcoin value screen.
 *
 * Ported from the fields `ValueViewController` keeps across `getCurrentValue` and
 * `changeSpan`. The two behaviours worth holding onto here — and worth testing —
 * are that a span tap is *ignored* while data is in flight, and that an empty
 * series is a displayable state rather than a failure.
 */
data class ValueUiState(
    val selectedSpan: GraphSpan = GraphSpan.WEEK,
    val isFetchingData: Boolean = true,
    val series: Map<GraphSpan, List<PricePoint>> = emptyMap(),
    val currentValue: String? = null,
    val profitPercentage: String? = null,
) {

    /** The points the chart draws for the currently selected span. */
    val visiblePoints: List<PricePoint>
        get() = series[selectedSpan].orEmpty()

    /**
     * `drawGraph` hides the graph and shows `noDataLabel` when the selected span has
     * no points (`ValueViewController.swift:366`). An empty series is not an error
     * state — the other spans may still have data — so it is modelled here rather
     * than raised.
     */
    val hasData: Boolean
        get() = visiblePoints.isNotEmpty()

    /**
     * Applies a span-button tap.
     *
     * `changeSpan` returns immediately while `isFetchingData` is true
     * (`ValueViewController.swift:332`). That guard is why
     * `bitcoin_value.yaml` waits for `value.profitLabel` *before* it taps m/y/5y:
     * taps that arrive during the fetch are dropped on the floor, silently. Keeping
     * the guard means the Android flow has the same ordering requirement as the iOS
     * one, which is the point of the port.
     */
    fun selectSpan(span: GraphSpan): ValueUiState =
        if (isFetchingData) this else copy(selectedSpan = span)

    /** The title a span button shows: long while selected, short otherwise. */
    fun titleFor(span: GraphSpan): String =
        if (span == selectedSpan) span.longTitle else span.shortTitle
}
