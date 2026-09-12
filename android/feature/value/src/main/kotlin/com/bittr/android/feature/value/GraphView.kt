package com.bittr.android.feature.value

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrTheme
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The floating card's width. iOS's is 80pt (`GraphView.swift:118`). */
private val CardWidth: Dp = 80.dp

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
 */
@Composable
internal fun GraphView(
    points: List<PricePoint>,
    currencySymbol: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    val density = LocalDensity.current
    var scrubbed by remember(points) { mutableStateOf<ScrubbedPoint?>(null) }
    var widthPx by remember { mutableStateOf(0) }

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .onSizeChanged { widthPx = it.width }
                .pointerInput(points) {
                    detectDragGestures(
                        onDragStart = { at -> scrubbed = points.scrub(at.x, size.width.toFloat()) },
                        onDragEnd = { scrubbed = null },
                        onDragCancel = { scrubbed = null },
                        onDrag = { change, _ ->
                            scrubbed = points.scrub(change.position.x, size.width.toFloat())
                        },
                    )
                },
        ) {
            if (points.size < 2) return@Canvas

            val prices = points.map { it.price }
            val lowest = prices.min()
            val span = (prices.max() - lowest).takeIf { it > 0 } ?: 1.0
            val stepX = size.width / (points.size - 1)

            fun at(index: Int) = Offset(
                x = index * stepX,
                y = size.height - ((prices[index] - lowest) / span).toFloat() * size.height,
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

            drawPath(path = path, color = LineColor, style = Stroke(width = 4f))
        }

        // The floating value card. Positioned by hand rather than by a layout,
        // because it tracks a finger rather than a slot.
        scrubbed?.let { scrub ->
            val cardWidthPx = with(density) { CardWidth.toPx() }
            val left = ((scrub.fraction * widthPx) - cardWidthPx / 2f)
                .coerceIn(0f, (widthPx - cardWidthPx).coerceAtLeast(0f))
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = with(density) { left.toDp() })
                    .width(CardWidth)
                    .background(colors.scrim1, BittrCanvasShapes.wordRow)
                    .padding(vertical = 6.dp),
            ) {
                Text(
                    text = CardDateFormat.format(scrub.point.at.atZone(ZoneId.systemDefault())),
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    text = "$currencySymbol ${formatPrice(scrub.point.price)}",
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.testTag(TestID.Value.graphValueLabel),
                )
            }
        }
    }
}

/** Which point a horizontal touch lands on, and where along the chart that is. */
internal data class ScrubbedPoint(val point: PricePoint, val fraction: Float)

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
internal fun List<PricePoint>.scrub(x: Float, width: Float): ScrubbedPoint? {
    if (isEmpty() || width <= 0f) return null
    val fraction = (x / width).coerceIn(0f, 1f)
    val index = (fraction * size).toInt().coerceIn(0, size - 1)
    return ScrubbedPoint(point = this[index], fraction = fraction)
}

private val LineColor = Color(0xFF1A1A1A)

/** `GraphView.cardDateFormatter` — a day and a month, no year. */
private val CardDateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd MMM", Locale.ENGLISH)
