package com.bittr.android.feature.value

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrLightColorsExtended
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.iosShadow
import kotlin.math.roundToInt

/**
 * The colours the value card draws with — iOS's `ValueViewController`: the card
 * `yelloworblue2`, the price `blackorwhite`, the axes `blackorwhite` at 20 % (lines) and
 * 40 % (labels), and the span buttons white and white at 70 %, as `showSelectedSpan`
 * paints them. The card follows the scheme again, as iOS's does; the line on it is white
 * (see [GraphView]).
 *
 * The scrub card keeps the pinned cream and hairline it floats on the chart with.
 */
internal object ChartColors {
    val card: Color @Composable get() = BittrTheme.colors.levelCard
    val ink: Color @Composable get() = BittrTheme.colors.onCanvas
    val axisLabel: Color @Composable get() = ink.copy(alpha = 0.4f)
    val axisLine: Color @Composable get() = ink.copy(alpha = 0.2f)

    /** The scrub card's fill and edge, fixed in both schemes. See [GraphView]. */
    val raised: Color = BittrLightColorsExtended.tonalFill
    val hairline: Color = BittrLightColorsExtended.onChartSurface.copy(alpha = 0.12f)

    /** The span buttons: white selected, white at 70 % otherwise, ink labels on both. */
    val spanSelected: Color = Color.White
    val spanUnselected: Color = Color.White.copy(alpha = 0.7f)
    val spanLabel: Color = BittrLightColorsExtended.onChartSurface
    val spanLabelDisabled: Color = spanLabel.copy(alpha = 0.5f)

    /** The loading placeholder and its travelling highlight. */
    val placeholder: Color @Composable get() = ink.copy(alpha = 0.08f)
    val placeholderSweep: Color = Color.White.copy(alpha = 0.35f)
}

/** `graphView`'s height less the band its dates sit in. */
private val ChartHeight: Dp = 140.dp

/**
 * How far the top and bottom gridlines sit inside [ChartHeight]. Half a label's height,
 * so the top and bottom Y labels centre on their lines without leaving the chart.
 */
private val PlotInsetVertical: Dp = 8.dp

/** How far inside the gridlines the curve starts and stops, the same at both ends. */
private val PlotInsetHorizontal: Dp = 10.dp

/**
 * The Y labels' gutter: `graphView` starts 55 into the card, whose padding is 15. The plot
 * leaves as much again empty on its right, so the gridlines, the curve, the dates and the
 * loading placeholder are centred on the card rather than pushed right by the labels.
 */
private val YGutter: Dp = 40.dp

private val SpanShape = RoundedCornerShape(8.dp)

/**
 * The chart module the design review (2026-09-18, `bitcoin_value/04`–`08`) asked for:
 * price, delta, chart and range selector in one white card, where they used to be four
 * loose rows on the canvas with a chart that had no frame of reference.
 *
 * **The loading state keeps this card's shape** (`bitcoin_value/03`): the price slot,
 * the chip slot and the chart frame are all laid out from the first frame and hold
 * placeholders while the fetch is in flight, so nothing moves when the data lands.
 * The selector is shown disabled rather than hidden — its taps are dropped during the
 * fetch anyway ([ValueUiState.selectSpan]), and now it says so.
 */
@Composable
internal fun ValueChartCard(
    state: ValueUiState,
    onSelect: (GraphSpan) -> Unit,
    modifier: Modifier = Modifier,
) {
    val points = state.visiblePoints
    val axis = remember(points) { PriceAxis.of(points.map { it.price }) }

    // `centerCard`: `yelloworblue2` with 13 pt corners and `setShadow()`. The price 50 from its
    // top, the pill 10 under it, the graph 20 under that, the span buttons 45 below the graph
    // (its dates take the first 25 of that) and 30 above the card's bottom.
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .fillMaxWidth()
            .iosShadow(IosCardShape)
            .background(ChartColors.card, IosCardShape)
            .padding(start = 15.dp, end = 15.dp, top = 50.dp, bottom = 30.dp),
    ) {
        PriceLine(state)
        Spacer(Modifier.height(10.dp))
        DeltaChipSlot(state)
        Spacer(Modifier.height(20.dp))
        ChartFrame(state, axis)
        Spacer(Modifier.height(20.dp))
        RangeSelector(state = state, onSelect = onSelect)
    }
}

/**
 * The current price, centred.
 *
 * `displaySmall` is Gilroy-Bold 36, the scale's hero-amount slot and what
 * `currentValueLabel` is on iOS (`rwD-dr-40A`) — see BIT-151 for the time it was not.
 * The review asks for 34; `Type.kt` rules out a one-off size at a call site, and the
 * other hero amounts in the app are this slot, so the two-sp difference belongs to the
 * scale if the design system wants it.
 */
@Composable
private fun PriceLine(state: ValueUiState) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 40.dp),
    ) {
        if (state.isFetchingData) {
            Placeholder(Modifier.size(width = 180.dp, height = 32.dp), BittrCanvasShapes.pill)
        } else {
            Text(
                text = state.currentValue.orEmpty(),
                style = MaterialTheme.typography.displaySmall,
                color = ChartColors.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.testTag(TestID.Value.currentValueLabel),
            )
        }
    }
}

/**
 * The chip's slot, held at the chip's height while loading so the chart below does not
 * jump up by it when the data lands. Placeholder'd like the price: a blank gap between
 * two shimmering blocks reads as something missing rather than something coming.
 */
@Composable
private fun DeltaChipSlot(state: ValueUiState) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.heightIn(min = 26.dp)) {
        if (state.isFetchingData) {
            Placeholder(Modifier.size(width = 72.dp, height = 26.dp), RoundedCornerShape(13.dp))
        } else {
            DeltaChip(state)
        }
    }
}

/**
 * The percentage chip.
 *
 * Its visibility is the flow's "data loaded" signal: `profitView` starts at alpha 0
 * and is faded in by `drawGraph` (`ValueViewController.swift:388-405`), so
 * `value.profitLabel` appearing means the series is parsed and drawn. Keeping it out
 * of the tree until then is what makes `extendedWaitUntil` return at the right
 * moment rather than immediately.
 *
 * The arrow is the review's, and it is also the chip's first non-colour signal for a
 * rise: iOS writes a loss as `-20 %` but a gain as a bare `19 %`, so until now only the
 * green said which way it went (WCAG 1.4.1).
 */
@Composable
private fun DeltaChip(state: ValueUiState) {
    if (!state.hasData) return
    val percentage = profitPercentage(state.visiblePoints.map { it.price }) ?: return
    val loss = percentage.startsWith("-")
    val colors = BittrTheme.colors
    val content = if (loss) colors.loss else colors.profit

    // `profitView`: 26 tall with 13 pt corners, `profitbackground0.8` (or the loss pair); the
    // 11 pt arrow 13 in, the percentage 5 after it in Gilroy Regular 14, 13 from the end.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier
            .height(26.dp)
            .background(if (loss) colors.lossBgMuted else colors.profitBgMuted, RoundedCornerShape(13.dp))
            .padding(horizontal = 13.dp),
    ) {
        ArrowGlyph(up = !loss, color = content)
        Text(
            text = percentage,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp, lineHeight = 14.sp),
            color = content,
            modifier = Modifier
                .offset(y = 1.dp)
                .testTag(TestID.Value.profitLabel),
        )
    }
}

/**
 * The plot, its gridlines, and both axes' labels.
 *
 * The Y labels sit in a gutter *outside* the plot, mirrored by an empty one on its right, and
 * the curve stops [PlotInsetHorizontal]
 * short of the right edge — before the review the line ran into the edge of the screen.
 * The gridlines span the full plot including that inset, so the line ends visibly
 * inside the frame rather than at it.
 */
@Composable
private fun ChartFrame(state: ValueUiState, axis: PriceAxis?) {
    val loading = state.isFetchingData
    val axisLine = ChartColors.axisLine
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(ChartHeight),
        ) {
            YAxisLabels(
                axis = if (loading) null else axis,
                modifier = Modifier
                    .width(YGutter)
                    .fillMaxHeight(),
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .drawBehind {
                        if (loading) return@drawBehind
                        val inset = PlotInsetVertical.toPx()
                        gridFractions(axis).forEach { fraction ->
                            val y = inset + (1 - fraction) * (size.height - 2 * inset)
                            drawLine(
                                color = axisLine,
                                start = Offset(0f, y),
                                end = Offset(size.width, y),
                                strokeWidth = 1.dp.toPx(),
                            )
                        }
                    },
            ) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(
                        start = PlotInsetHorizontal,
                        end = PlotInsetHorizontal,
                        top = PlotInsetVertical,
                        bottom = PlotInsetVertical,
                    ),
                ) {
                    // Tagged and present from the first frame — the flow asserts it
                    // before the data arrives, so it must not be gated on having points.
                    GraphView(
                        points = state.visiblePoints,
                        axis = axis,
                        currencySymbol = ValueCopy.currencySymbol(state),
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag(TestID.Value.graphView),
                    )
                    if (!loading && !state.hasData) {
                        // `noDataLabel` — a span with no points is a displayable state,
                        // not a failure (`ValueViewController.swift:366-372`).
                        Text(
                            text = ValueCopy.NO_DATA,
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                            // The storyboard's black, in both modes.
                            color = BittrTheme.colors.onChartSurface,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }
                }
                if (loading) {
                    // The loading indicator, and it carries `value.valueSpinner`: the
                    // flow asserts that id is gone once `value.profitLabel` is up, and
                    // the review replaced iOS's spinner with this placeholder. It is
                    // the indicator, whatever it looks like, so it keeps the id.
                    Placeholder(
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag(TestID.Value.valueSpinner),
                    )
                }
            }
            Spacer(Modifier.width(YGutter))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.width(YGutter))
            XAxisLabels(
                points = if (loading) emptyList() else state.visiblePoints,
                span = state.selectedSpan,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 18.dp)
                    .padding(horizontal = PlotInsetHorizontal),
            )
            Spacer(Modifier.width(YGutter))
        }
    }
}

/**
 * The four gridline prices, each centred on its line and right-aligned against the
 * plot.
 *
 * `labelMedium`, Regular 13. The review asks for 12 sp / 500: 13 is the scale's floor
 * (DEV-06 — the same floor the scrub card's date took over iOS's 10), and Gilroy ships
 * Regular and Bold only, so a 500 would render as Regular anyway.
 */
@Composable
private fun YAxisLabels(axis: PriceAxis?, modifier: Modifier) {
    Layout(
        modifier = modifier,
        content = {
            axis?.ticks?.forEach { tick -> AxisLabel(axis.label(tick)) }
        },
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val inset = PlotInsetVertical.roundToPx()
        val gap = 4.dp.roundToPx()
        val plot = (constraints.maxHeight - 2 * inset).toFloat()
        val fractions = gridFractions(axis)
        layout(constraints.maxWidth, constraints.maxHeight) {
            // Same arithmetic as the gridlines in [ChartFrame], so each label centres
            // on its own line.
            placeables.forEachIndexed { index, label ->
                val centre = constraints.maxHeight - inset - fractions[index] * plot
                // Wider than the gutter overflows left into the card's padding rather
                // than into the plot — a `98.25k` is rare, and clipped it would lie.
                label.place(
                    x = constraints.maxWidth - gap - label.width,
                    y = (centre - label.height / 2f).roundToInt(),
                )
            }
        }
    }
}

/**
 * Four dates under the plot at 0, ⅓, ⅔ and 1 of its width — the samples
 * [dateLabelPoints] picks — each centred on its x and clamped inside the plot so the
 * first and last do not hang off it.
 */
@Composable
private fun XAxisLabels(points: List<PricePoint>, span: GraphSpan, modifier: Modifier) {
    val format = remember(span) { span.axisDateFormat() }
    val labels = remember(points, format) { points.dateLabelPoints().map { format.format(it.at) } }
    Layout(
        modifier = modifier,
        content = { labels.forEach { AxisLabel(it) } },
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val width = constraints.maxWidth
        val height = maxOf(constraints.minHeight, placeables.maxOfOrNull { it.height } ?: 0)
        layout(width, height) {
            placeables.forEachIndexed { index, label ->
                val centre = width * index / (DATE_LABELS - 1f)
                val x = (centre - label.width / 2f).roundToInt()
                    .coerceIn(0, (width - label.width).coerceAtLeast(0))
                label.place(x, 0)
            }
        }
    }
}

/**
 * Where the gridlines sit, 0 at the bottom of the plot and 1 at the top, bottom first.
 *
 * With data they are the axis's round prices, wherever those land inside the padded
 * domain. Without (a span with no points), there are no prices to place, and evenly
 * spaced lines keep the empty chart looking like the same chart.
 */
private fun gridFractions(axis: PriceAxis?): List<Float> =
    axis?.ticks?.map(axis::fractionOf)
        ?: List(PriceAxis.GRIDLINES) { it / (PriceAxis.GRIDLINES - 1f) }

@Composable
private fun AxisLabel(text: String) {
    Text(
        text = text,
        // Gilroy Regular 12 at 40 %, as iOS draws the axis labels.
        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp, lineHeight = 12.sp),
        color = ChartColors.axisLabel,
        maxLines = 1,
        softWrap = false,
    )
}

/**
 * The span buttons — `buttonsView`: four plates 30 tall with 8 pt corners, 5 apart and centred,
 * each sized to its label (Gilroy Bold 14, 10 in from either side, 1.5 below centre). The selected
 * one is white with `setShadow()` and reads long ("1 week"); the others are white at 70 % and read
 * short ("m"), as `showSelectedSpan` paints them. The long label is also why the flow taps
 * `value.monthButton` and then looks for the graph rather than for "m".
 *
 * While the fetch is in flight the taps are dropped ([ValueUiState.selectSpan]) and the labels
 * say so, dimmed.
 */
@Composable
private fun RangeSelector(state: ValueUiState, onSelect: (GraphSpan) -> Unit) {
    val enabled = !state.isFetchingData
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.selectableGroup(),
    ) {
        GraphSpan.entries.forEach { span ->
            val selected = span == state.selectedSpan
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(30.dp)
                    .then(if (selected) Modifier.iosShadow(SpanShape) else Modifier)
                    .clip(SpanShape)
                    .background(if (selected) ChartColors.spanSelected else ChartColors.spanUnselected)
                    .selectable(
                        selected = selected,
                        enabled = enabled,
                        role = Role.RadioButton,
                        onClick = { onSelect(span) },
                    )
                    .testTag(span.testTag)
                    .padding(horizontal = 10.dp),
            ) {
                Text(
                    text = state.titleFor(span),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        lineHeight = 14.sp,
                    ),
                    color = if (enabled) ChartColors.spanLabel else ChartColors.spanLabelDisabled,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier.offset(y = 1.5.dp),
                )
            }
        }
    }
}

/** The id each segment carries, so the flow can tap m, y and 5y by name. */
private val GraphSpan.testTag: String
    get() = when (this) {
        GraphSpan.WEEK -> TestID.Value.weekButton
        GraphSpan.MONTH -> TestID.Value.monthButton
        GraphSpan.YEAR -> TestID.Value.yearButton
        GraphSpan.FIVE_YEARS -> TestID.Value.fiveYearsButton
    }

/**
 * A loading block: ink @ 8 % with a lighter band sweeping across it every 1.2 s.
 *
 * The sweep is read inside the draw lambda, so the animation redraws the block and
 * never recomposes or re-lays-out the card around it.
 */
@Composable
private fun Placeholder(modifier: Modifier, shape: Shape) {
    val placeholder = ChartColors.placeholder
    val sweep = rememberInfiniteTransition(label = "placeholder").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_200, easing = LinearEasing)),
        label = "sweep",
    )
    Box(
        modifier
            .clip(shape)
            .background(placeholder)
            .drawBehind {
                val band = size.width * 0.5f
                val start = -band + sweep.value * (size.width + band)
                drawRect(
                    Brush.horizontalGradient(
                        0f to Color.Transparent,
                        0.5f to ChartColors.placeholderSweep,
                        1f to Color.Transparent,
                        startX = start,
                        endX = start + band,
                    ),
                )
            },
    )
}

/**
 * The chip's direction arrow, drawn rather than set as a glyph: Gilroy has no arrows,
 * and a fallback-font `↑` sits on a different baseline from the digits beside it.
 */
@Composable
private fun ArrowGlyph(up: Boolean, color: Color) {
    // `arrow.up` / `arrow.down`, 11 by 14.
    Canvas(Modifier.size(width = 11.dp, height = 14.dp)) {
        val stroke = Stroke(width = 1.75.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        val w = size.width
        val h = size.height
        rotate(if (up) 0f else 180f) {
            drawLine(color, Offset(w / 2, h * 0.85f), Offset(w / 2, h * 0.15f), stroke.width, StrokeCap.Round)
            drawPath(
                Path().apply {
                    moveTo(w * 0.2f, h * 0.45f)
                    lineTo(w / 2, h * 0.15f)
                    lineTo(w * 0.8f, h * 0.45f)
                },
                color,
                style = stroke,
            )
        }
    }
}
