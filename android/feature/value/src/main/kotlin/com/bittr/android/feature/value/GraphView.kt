package com.bittr.android.feature.value

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrTheme
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/** The floating card's width. iOS's is 80pt (`GraphView.swift:118`). */
private val CardWidth: Dp = 80.dp

/**
 * The gap iOS leaves between the card's bottom edge and the point it is reading.
 *
 * Not a number from the storyboard — it is what falls out of iOS's two formulas once
 * they are put side by side, which is the only way to port the y position onto a chart
 * whose curve is laid out differently.
 *
 * ```
 * coordYFor(i)  = (H - 25) - (H - 30) * f      // the curve  (GraphView.swift:159-164)
 * yConstraint   =  30      + (H - 30) * f      // the card   (GraphView.swift:108)
 * card bottom   =  H - yConstraint             // (GraphView.swift:122)
 *               =  coordYFor(i) - 5            // for every f
 * ```
 *
 * So the card's bottom edge rides exactly 5 pt above the data point, everywhere. The
 * `30` is not a top floor and not a gap: it is the inset of iOS's *curve* from the
 * bottom of the view (25) carried into the card's constraint. Porting `30` literally
 * would be wrong here, because [GraphView]'s scale has no such inset — its bottom and
 * top gridlines are its bottom and top edges — so a literal `30 + f * (H - 30)` drifts
 * from a 30 dp gap at the bottom of the chart to none at the top. The 5 dp
 * relationship is what transfers.
 */
private val CardGap: Dp = 5.dp

/** The curve's stroke — the design review's 3 dp. */
private val CurveWidth: Dp = 3.dp

/**
 * The price line, and the card that follows a finger across it.
 *
 * Ported from `GraphView`. The curve there is a hand-rolled quadratic Bézier with
 * antipodal control points (`quadCurvedPath`, `:186-275`); the midpoint-quadratic
 * construction below draws the same shape for a series sampled evenly along x, which
 * is what this one is.
 *
 * **The scrub is the part with a Maestro dependency.** `bitcoin_value.yaml` drags
 * across `value.graphView` and its comment records that the floating card exists
 * only while the finger is down — `touchesEnded` tears it off
 * (`GraphView.swift:62-68`) — so it cannot be asserted after the swipe completes.
 * That is reproduced here: [scrubbed] is set on drag and cleared on release, and
 * `value.graphValueLabel` exists exactly while it is set. Leaving the card up after
 * the gesture would look tidier and would make the flow's comment wrong.
 *
 * **This is the plot and only the plot.** Since the design review (2026-09-18) the
 * gridlines, both axes' labels and the 8 dp right inset belong to the chart card
 * around it (`ValueChartCard.kt`), and they sit *outside* this composable on purpose:
 * `value.graphView` is the element the flow swipes from the centre of and the tests
 * scrub by fraction of, and both of those mean "the curve's own width". Putting a
 * 32 dp label gutter inside it would have shifted every finger position by the gutter.
 * The top and bottom edges here are the top and bottom gridlines, so [PriceAxis]
 * fractions map straight onto this height.
 */
@Composable
internal fun GraphView(
    points: List<PricePoint>,
    axis: PriceAxis?,
    currencySymbol: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    val density = LocalDensity.current
    var scrubbed by remember(points) { mutableStateOf<ScrubbedPoint?>(null) }
    var chartSize by remember { mutableStateOf(IntSize.Zero) }

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .onSizeChanged { chartSize = it }
                .pointerInput(points) {
                    detectDragGestures(
                        onDragStart = { at ->
                            scrubbed = points.scrub(at.x, size.width.toFloat(), axis)
                        },
                        onDragEnd = { scrubbed = null },
                        onDragCancel = { scrubbed = null },
                        onDrag = { change, _ ->
                            scrubbed = points.scrub(change.position.x, size.width.toFloat(), axis)
                        },
                    )
                },
        ) {
            if (points.size < 2 || axis == null) return@Canvas

            // The same 0…1 the card positions itself with, so the two cannot drift.
            val fractions = points.map { axis.fractionOf(it.price) }
            val stepX = size.width / (points.size - 1)

            fun at(index: Int) = Offset(
                x = index * stepX,
                y = size.height - fractions[index] * size.height,
            )

            // Smooth through the midpoints: each segment curves toward the point it
            // passes, with that point as the control. The line stays inside the
            // data's range, which an interpolating spline does not.
            val path = Path().apply {
                moveTo(at(0).x, at(0).y)
                for (index in 1 until points.size) {
                    val previous = at(index - 1)
                    val current = at(index)
                    quadraticTo(
                        previous.x,
                        previous.y,
                        (previous.x + current.x) / 2f,
                        (previous.y + current.y) / 2f,
                    )
                }
                val last = at(points.size - 1)
                lineTo(last.x, last.y)
            }

            // Ink on the chart card, in both schemes. iOS strokes the curve with
            // `whiteoryellow` (`GraphView.swift:175`) — the token DEV-47 merged into
            // `emphasis` — because on iOS the curve sits on the canvas. It does not any
            // more: the design review put the chart in a fixed white card, and
            // `emphasis` is yellow in dark, which on white is about 1.6 : 1 — under the
            // 3 : 1 WCAG 1.4.11 floor for a graphical object, the failure BIT-156 took
            // this stroke off a literal to fix. The review's own spec was a white line
            // with a shadow, drawn for a line on yellow; on white that is invisible.
            // `onChartSurface` is the card's ink, 19.44 : 1.
            //
            // 3 dp with round caps and joins, from the review. It was 4 *px*, which is
            // 1.5 dp at 420 dpi.
            drawPath(
                path = path,
                color = colors.onChartSurface,
                style = Stroke(
                    width = CurveWidth.toPx(),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
        }

        // The floating value card. Positioned by hand rather than by a layout,
        // because it tracks a finger rather than a slot.
        scrubbed?.let { scrub ->
            val cardWidthPx = with(density) { CardWidth.toPx() }
            val left = ((scrub.fraction * chartSize.width) - cardWidthPx / 2f)
                .coerceIn(0f, (chartSize.width - cardWidthPx).coerceAtLeast(0f))
            // iOS's `yConstraint`, rebuilt on this chart's geometry: the card's bottom
            // edge sits [CardGap] above the point, so it rides the curve rather than
            // sliding along the top edge while the line moves underneath it.
            val bottom = with(density) { CardGap.toPx() } +
                scrub.priceFraction * chartSize.height
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    // Placed rather than offset, because the vertical clamp needs the
                    // card's own height and nothing else here knows it: the card is
                    // two text labels and padding, where iOS pins a fixed 40 pt.
                    //
                    // The clamp is the port's, and it is the one place this deviates
                    // from iOS deliberately. At the top of the series iOS's own formula
                    // puts the card's bottom edge at y = 0 — the whole card above the
                    // view, drawn outside its bounds. Compose clips it away instead of
                    // overhanging, so the card would simply vanish at the peak of the
                    // curve. Clamping into the chart is the same treatment `left`
                    // already gets at the left and right edges.
                    .layout { measurable, constraints ->
                        val placeable = measurable.measure(constraints)
                        val lowestTop = (chartSize.height - placeable.height)
                            .toFloat().coerceAtLeast(0f)
                        val top = (chartSize.height - bottom - placeable.height)
                            .coerceIn(0f, lowestTop)
                        layout(placeable.width, placeable.height) {
                            placeable.place(left.roundToInt(), top.roundToInt())
                        }
                    }
                    .width(CardWidth)
                    // A fixed light surface in both schemes, for the reason BIT-156
                    // gave: no fill on the dark canvas both has an edge and carries
                    // white text, so this is a light card with ink on it or no card.
                    //
                    // But not white any more. iOS's card is `.white`
                    // (`GraphView.swift:112`) because it floats on the canvas; since the
                    // design review it floats on the white chart card, and white on
                    // white is the 1.00 : 1 BIT-156 was about, reached from the other
                    // side. The cream tonal fill — pinned to its light value, because
                    // `tonalFill` is `blue3` in dark and this card does not follow the
                    // scheme — plus the chart's own hairline gives it an edge, and
                    // keeps both labels' ink: 16.7 : 1 for the price, 6.8 : 1 for the
                    // 70 % date. The same fill marks the selected range segment, so
                    // "cream on this card" means one thing.
                    .background(ChartColors.raised, BittrCanvasShapes.wordRow)
                    .border(1.dp, ChartColors.hairline, BittrCanvasShapes.wordRow)
                    .padding(vertical = 6.dp),
            ) {
                // The scale's floor, and the one BIT-151 call site where iOS is not
                // simply reproducible: `dateLabel` is Gilroy-Regular
                // **10** (`GraphView.swift:128`), and `Type.kt` defines nothing below
                // `labelMedium`'s 13. That floor is the port's, from DEV-06 and the
                // A11Y line the shrink-to-fit balance also respects, so the date
                // takes it rather than reintroducing a 10 sp one-off.
                //
                // The de-emphasis is a token, not iOS's `alpha = 0.4`
                // (`GraphView.swift:131`). Copying that number gives black at 40 % on
                // this card — **2.85 : 1** — which misses AA for a 13 sp regular label
                // and misses the 3 : 1 large-text floor as well, so it is not readable
                // under any reading of the rule. Same call BIT-94 made.
                //
                // It was `mutedOnCanvas` until BIT-156, which is right for a label on
                // the canvas and wrong on this card: the card stopped following the
                // canvas, and `mutedOnCanvas` is white in dark. `onChartSurfaceMuted`
                // is that token's light value pinned — the same ink at 70 %, 7.39 : 1
                // here. Measured in `TokenContrastTest`.
                Text(
                    text = CardDateFormat.format(scrub.point.at.atZone(ZoneId.systemDefault())),
                    style = MaterialTheme.typography.labelMedium,
                    color = colors.onChartSurfaceMuted,
                )
                // `priceLabel` is Gilroy-**Bold** 12 (`GraphView.swift:144`), and 13 is
                // the scale's floor, so this is `labelMedium` with the weight the
                // storyboard asks for — the `copy` convention `Type.kt` spells out for
                // a slot that carries one weight. It was reading `labelLarge`'s Bold
                // 16, four sp over iOS, which does not fit: `CHF 120,000` wrapped onto
                // two lines inside the 80 dp card, measured, not guessed. BIT-152.
                //
                // The colour is spelled rather than inherited, and that is load-bearing
                // now: `BittrCanvas` provides `onCanvas` as the content colour and this
                // card no longer is the canvas — in dark that inherited white would be
                // the fill. `GraphCardFitTest` asserts both call sites. BIT-156.
                Text(
                    text = "$currencySymbol ${formatPrice(scrub.point.price)}",
                    style = MaterialTheme.typography.labelMedium
                        .copy(fontWeight = FontWeight.Bold),
                    color = colors.onChartSurface,
                    modifier = Modifier.testTag(TestID.Value.graphValueLabel),
                )
            }
        }
    }
}

/**
 * Which point a horizontal touch lands on, and where on the chart that is — in both
 * axes, because the card tracks both.
 *
 * @property fraction where along the chart's width the finger is, 0…1.
 * @property priceFraction where [point]'s price sits on the chart's [PriceAxis], 0 at
 *   the bottom gridline and 1 at the top. This is the curve's own y, so the card
 *   derived from it lands on the line rather than near it.
 */
internal data class ScrubbedPoint(
    val point: PricePoint,
    val fraction: Float,
    val priceFraction: Float,
)

/**
 * Resolves a touch to a point.
 *
 * iOS clamps the fraction to 0…1 and then indexes `Int(fraction * count) - 1`
 * (`GraphView.swift:88-100`), which runs one short at the right-hand edge and is
 * saved by a second clamp on the index. Here the index is derived and then coerced
 * into the list, which reaches the last point where iOS reaches the second to last —
 * a difference of one sample under the finger, and the alternative is porting an
 * off-by-one.
 */
internal fun List<PricePoint>.scrub(
    x: Float,
    width: Float,
    axis: PriceAxis? = PriceAxis.of(map { it.price }),
): ScrubbedPoint? {
    if (isEmpty() || width <= 0f || axis == null) return null
    val fraction = (x / width).coerceIn(0f, 1f)
    val index = (fraction * size).toInt().coerceIn(0, size - 1)
    return ScrubbedPoint(
        point = this[index],
        fraction = fraction,
        priceFraction = axis.fractionOf(this[index].price),
    )
}

/**
 * `GraphView.cardDateFormatter` — `dd MMM yyyy` (`GraphView.swift:25`).
 *
 * This read `dd MMM` and said so in this KDoc, which was simply wrong about iOS: the
 * card showed `08 Sep` where iOS shows `08 Sep 2026`, and
 * `reference_set_duplicate_audit.md:68` — the spec that stands in for the screenshot
 * this card cannot appear in, since `touchesEnded` tears it off before any capture —
 * gives the format as `dd MMM yyyy`. It had been that way since BIT-99 with no
 * decision recorded anywhere, so it was an oversight rather than a divergence. BIT-157.
 *
 * The reason to check rather than just restore it is the 80 dp card, which BIT-152
 * already found the price wrapping in. The year costs ~32 dp and still fits on one
 * line: `08 Sep 2026` measures **73.9 dp** of the 80, and the widest string the
 * pattern can produce in any month of any `20yy` — `04 May 2040`, since Gilroy's
 * digits are not tabular either — measures **78.4 dp**. `GraphCardFitTest` renders
 * every month and holds both numbers.
 *
 * So this is now the card's tightest row rather than the price's 72.4 dp, and its
 * worst case has **1.6 dp** of slack. That is a real fit and not a comfortable one;
 * it is also the shape the card was already in, since neither label here shrinks to
 * fit and neither does iOS's.
 *
 * The date labels under the chart are a different label with their own, shorter
 * format per span ([axisDateFormat]).
 *
 * `internal` so `GraphCardFitTest` can find the date label by the string this card
 * actually puts in it, rather than re-spelling the pattern and measuring whatever
 * that produces.
 */
internal val CardDateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.ENGLISH)
