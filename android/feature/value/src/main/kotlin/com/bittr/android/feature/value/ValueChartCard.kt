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
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrLightColorsExtended
import kotlin.math.roundToInt

/**
 * The colours the chart card draws with, all pinned to one value in both schemes.
 *
 * The card is `chartSurface` — fixed white in light *and* dark, for the arithmetic on
 * `BittrColors.chartSurface` (BIT-156): no dark fill has an edge on `blue1` and still
 * carries white text. Everything drawn on it therefore has to be pinned too, and the
 * trap is the scheme-following tokens that *look* right: `tonalFill` is `blue3` in
 * dark, `profit` is a pale green meant for the blue canvas, `emphasis` is yellow. Each
 * of those would land on white at under 2 : 1. So every colour here is read off
 * [BittrLightColorsExtended] — the light value, which is the one measured against a
 * light surface — rather than off `BittrTheme.colors`.
 *
 * The three alphas are the design review's (2026-09-18) and are named here rather
 * than at their call sites so there is one place to change them. They would belong in
 * `core/designsystem` beside `chartSurface`; this module does not own that file.
 */
internal object ChartColors {
    val surface: Color = BittrLightColorsExtended.chartSurface
    val ink: Color = BittrLightColorsExtended.onChartSurface

    /**
     * The axis labels. The review asks for ink at **55 %**, which on white is
     * `#7A7A7A` — **4.30 : 1**, under AA's 4.5 for text this size. This is the card's
     * existing muted ink, 70 %, at 7.39 : 1, which is also what the scrub card's date
     * already uses: one caption colour on this card, not two.
     */
    val inkMuted: Color = BittrLightColorsExtended.onChartSurfaceMuted

    /** The cream: the range selector's track and the scrub card. See [RangeSelector]. */
    val raised: Color = BittrLightColorsExtended.tonalFill

    /** Gridlines and the segmented control's outline — the review's ink @ 12 %. */
    val hairline: Color = ink.copy(alpha = 0.12f)

    /** The loading placeholder — the review's ink @ 8 %. */
    val placeholder: Color = ink.copy(alpha = 0.08f)

    /** The travelling highlight across [placeholder]. */
    val placeholderSweep: Color = Color.White.copy(alpha = 0.65f)

    /**
     * A range label while the selector is disabled. Ink at 50 %, not Material's 38 %:
     * the same floor `onActionFillDisabled` was set to, the lightest alpha that keeps
     * a disabled label at 3 : 1 — here 3.6 : 1 on white and 3.5 : 1 on the cream.
     */
    val disabledLabel: Color = ink.copy(alpha = 0.50f)

    /**
     * The delta chip. The review specified `#E7F6EC`/`#1F8A4C` and
     * `#FDEBEC`/`#B3261E`; these are the signed-off profit/loss tokens instead
     * (A11Y-04 / DEV-60, founder sign-off BIT-15), which carry the contrast decisions
     * the rest of the app's profit pills are held to. Light values, because the chip
     * is on the white card in both schemes — the dark ones are a pale label on a
     * translucent pill meant for `blue1`.
     */
    val profit: Color = BittrLightColorsExtended.profit
    val profitBg: Color = BittrLightColorsExtended.profitBg
    val loss: Color = BittrLightColorsExtended.loss
    val lossBg: Color = BittrLightColorsExtended.lossBg
}

/** The plot's height with its axis bands, from the review. */
private val ChartHeight: Dp = 200.dp

/**
 * How far the top and bottom gridlines sit inside [ChartHeight]. Half a label's height,
 * so the top and bottom Y labels centre on their lines without leaving the chart, and
 * the 3 dp stroke on an extreme gridline is not cut by the edge.
 */
private val PlotInsetVertical: Dp = 8.dp

/** The review's: the curve stops this far short of the card's content edge. */
private val PlotInsetEnd: Dp = 8.dp

/** The review's Y-label gutter, left of the plot and outside it. */
private val YGutter: Dp = 32.dp

private val SegmentHeight: Dp = 40.dp

/** How far the white selected segment sits inside the cream track, so the track shows round it. */
private val SelectedInset: Dp = 3.dp
private val ChipShape = RoundedCornerShape(12.dp)
private val GlyphSize: Dp = 14.dp

/**
 * Below this, a selected segment drops its check and keeps only the long label.
 *
 * `1 month` in Bold 14 is ~55 dp, and the check and its gap add 18. A 411 dp phone
 * gives each segment ~81 dp; a 320 dp one gives 58, where the check would push the
 * label into the next segment. The long label and the fill still say "selected" there.
 */
private val CheckMinSegmentWidth: Dp = 78.dp

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

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .fillMaxWidth()
            .background(ChartColors.surface, BittrCanvasShapes.card)
            .padding(20.dp),
    ) {
        PriceLine(state)
        Spacer(Modifier.height(8.dp))
        DeltaChipSlot(state)
        Spacer(Modifier.height(20.dp))
        ChartFrame(state, axis)
        Spacer(Modifier.height(16.dp))
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
    Box(contentAlignment = Alignment.Center, modifier = Modifier.heightIn(min = 28.dp)) {
        if (state.isFetchingData) {
            Placeholder(Modifier.size(width = 72.dp, height = 28.dp), ChipShape)
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
    val content = if (loss) ChartColors.loss else ChartColors.profit

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .background(if (loss) ChartColors.lossBg else ChartColors.profitBg, ChipShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        ArrowGlyph(up = !loss, color = content)
        // Bold 14 is `bodyMedium` with the weight, per `Type.kt`'s convention table.
        Text(
            text = percentage,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
            color = content,
            modifier = Modifier.testTag(TestID.Value.profitLabel),
        )
    }
}

/**
 * The plot, its gridlines, and both axes' labels.
 *
 * The Y labels sit in a gutter *outside* the plot and the curve stops [PlotInsetEnd]
 * short of the right edge — before the review the line ran into the edge of the screen.
 * The gridlines span the full plot including that inset, so the line ends visibly
 * inside the frame rather than at it.
 */
@Composable
private fun ChartFrame(state: ValueUiState, axis: PriceAxis?) {
    val loading = state.isFetchingData
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
                                color = ChartColors.hairline,
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
                        .padding(end = PlotInsetEnd, top = PlotInsetVertical, bottom = PlotInsetVertical),
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
                            style = MaterialTheme.typography.bodyMedium,
                            color = ChartColors.inkMuted,
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
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.width(YGutter))
            XAxisLabels(
                points = if (loading) emptyList() else state.visiblePoints,
                span = state.selectedSpan,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 18.dp)
                    .padding(end = PlotInsetEnd),
            )
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
        style = MaterialTheme.typography.labelMedium,
        color = ChartColors.inkMuted,
        maxLines = 1,
        softWrap = false,
    )
}

/**
 * The range selector: one connected, single-select segmented control where there were
 * four detached pills.
 *
 * **A cream track with a white selected segment, which carries a check.** Pass 2 had
 * this the other way round — cream selected, white unselected — because the segments
 * then sat straight on the white card, where a white selected segment has nothing to
 * stand out against (the inversion BIT-156 fixed once on this screen). The third
 * review (2026-09-18) asked again for white-selected on cream, and the way to give it
 * that without the inversion is to put the cream *under the whole control*: the track
 * is the background the white segment reads against, not the card. The selected
 * segment is inset inside the track and outlined, because cream against white is only
 * 1.16 : 1 and the fill alone is not relied on — the check, and the long label
 * (`showSelectedSpan`), say which is selected without colour (WCAG 1.4.1).
 *
 * The long label is also why the flow taps `value.monthButton` and then looks for the
 * graph rather than for "m": the label it just tapped has changed to "1 month".
 *
 * Each segment is a full 48 dp touch target (`BittrTokens.Size.minTouchTarget`); the
 * review's 40 dp is the drawn band inside it.
 */
@Composable
private fun RangeSelector(state: ValueUiState, onSelect: (GraphSpan) -> Unit) {
    val enabled = !state.isFetchingData
    val spans = GraphSpan.entries
    BoxWithConstraints(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxWidth(),
    ) {
        val showCheck = maxWidth / spans.size >= CheckMinSegmentWidth
        // The track, drawn once under all four segments.
        Box(
            Modifier
                .fillMaxWidth()
                .height(SegmentHeight)
                .background(ChartColors.raised, BittrCanvasShapes.pill),
        )
        Row(Modifier.fillMaxWidth().selectableGroup()) {
            spans.forEachIndexed { index, span ->
                val selected = span == state.selectedSpan
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .selectable(
                            selected = selected,
                            enabled = enabled,
                            role = Role.RadioButton,
                            onClick = { onSelect(span) },
                        )
                        .testTag(span.testTag),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(SegmentHeight)
                            .drawBehind {
                                // Dividers only between two cream segments: beside the
                                // white one, its own outline is the edge.
                                val previous = spans.getOrNull(index - 1) ?: return@drawBehind
                                if (selected || previous == state.selectedSpan) return@drawBehind
                                drawLine(
                                    color = ChartColors.hairline,
                                    start = Offset(0f, 0f),
                                    end = Offset(0f, size.height),
                                    strokeWidth = 1.dp.toPx(),
                                )
                            }
                            .then(
                                if (selected) {
                                    Modifier
                                        .padding(SelectedInset)
                                        .background(ChartColors.surface, BittrCanvasShapes.pill)
                                        .border(1.dp, ChartColors.hairline, BittrCanvasShapes.pill)
                                } else {
                                    Modifier
                                },
                            ),
                    ) {
                        val label = if (enabled) ChartColors.ink else ChartColors.disabledLabel
                        if (selected && showCheck) {
                            CheckGlyph(color = label)
                            Spacer(Modifier.width(4.dp))
                        }
                        // Bold 14, where the review says 600: Gilroy has no SemiBold,
                        // and 600 resolves to the Bold face regardless.
                        Text(
                            text = state.titleFor(span),
                            style = MaterialTheme.typography.bodyMedium
                                .copy(fontWeight = FontWeight.Bold),
                            color = label,
                            maxLines = 1,
                            softWrap = false,
                        )
                    }
                }
            }
        }
        // The outline is drawn once over the whole band rather than per segment, so it
        // is one pill and not four. No pointer input, so taps fall through to the row.
        Box(
            Modifier
                .fillMaxWidth()
                .height(SegmentHeight)
                .border(1.dp, ChartColors.hairline, BittrCanvasShapes.pill),
        )
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
    val sweep = rememberInfiniteTransition(label = "placeholder").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_200, easing = LinearEasing)),
        label = "sweep",
    )
    Box(
        modifier
            .clip(shape)
            .background(ChartColors.placeholder)
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
    Canvas(Modifier.size(GlyphSize)) {
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

/** The selected segment's leading check, drawn for the reason [ArrowGlyph] is. */
@Composable
private fun CheckGlyph(color: Color) {
    Canvas(Modifier.size(GlyphSize)) {
        drawPath(
            Path().apply {
                moveTo(size.width * 0.15f, size.height * 0.52f)
                lineTo(size.width * 0.4f, size.height * 0.76f)
                lineTo(size.width * 0.85f, size.height * 0.26f)
            },
            color,
            style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}
