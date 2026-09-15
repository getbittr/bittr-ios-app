package com.bittr.android.feature.value

import android.graphics.Bitmap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrDarkColorsExtended
import com.bittr.android.core.designsystem.BittrLightColorsExtended
import com.bittr.android.core.designsystem.BittrTheme
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The scrub card's two labels, measured in the card they have to fit.
 *
 * The floating card is **80 dp wide and positioned by hand** — it tracks a finger
 * rather than sitting in a slot, matching iOS's 80 pt width constraint
 * (`GraphView.swift:120`). No parent constrains its contents and nothing raises a
 * layout error when they do not fit: the text wraps, the card grows downward, and
 * the result looks like a design decision. Both labels also moved recently — the
 * date in BIT-151, the price in BIT-152 — and neither move had been rendered.
 *
 * ### Why this is measured rather than eyeballed
 *
 * `CHF` is a shipped currency ([PriceCurrency]), three characters where `€` is one,
 * and the price is the widest string on this screen per point of type. At the
 * Gilroy-Bold **16** the price carried before BIT-152, `CHF 120,000` laid out on
 * **two lines** inside the 80 dp card, while `€ 99,000` — the string anyone would
 * try first — fitted at 63 dp with room to spare. Checking the euro case only is how
 * that shipped.
 *
 * The assertions are on [TextLayoutResult], not on pixels: one line each, and the
 * widest line inside the card. That is the property the card's hand-positioning
 * cannot enforce for itself.
 *
 * ### This test is only meaningful under native graphics
 *
 * Robolectric's default `LEGACY` graphics mode has no font rasterisation and returns
 * roughly **one pixel per character** — plausible numbers, `lineCount = 1`,
 * `hasVisualOverflow = false`, for any string at any size. A fit assertion measured
 * there passes by construction and means nothing. Hence `@GraphicsMode(NATIVE)`, and
 * hence `assumeNativeTextMetrics`, which reports this as *skipped* rather than green
 * when the real Gilroy face is not what is being measured.
 *
 * PNGs land in `feature/value/build/screenshots/` (`bittr.screenshot.dir`). They are
 * evidence for a human; the assertions above are what fails the build.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GraphCardFitTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun `the scrub card fits on a 411 dp screen`() = assertCardFits("411dp")

    /**
     * The narrowest screen the port supports. The card is a fixed 80 dp either way,
     * so the text fit itself does not change here — what changes is the horizontal
     * clamp that keeps the card on screen, which has less room to work with.
     */
    @Test
    @Config(qualifiers = "w320dp-h568dp-320dpi")
    fun `the scrub card fits on a 320 dp screen`() = assertCardFits("320dp")

    /**
     * The card tracks the price in y, not just the finger in x.
     *
     * iOS pins the card's bottom edge 5 pt above the data point at every position
     * (`GraphView.swift:108` and `:122`, resolved against `coordYFor` at `:159`); the
     * port slid it along the top edge while the line moved underneath. BIT-155.
     *
     * **Asserted as a difference between two scrub positions**, which is what makes it
     * exact without the test knowing anything about the card. The gap and the card's
     * own height are identical at both positions, so they cancel, and what is left is
     * the chart's height times the change in price — arithmetic this test can do.
     *
     * Needs no font metrics, so unlike the fit assertions it is meaningful under
     * `LEGACY` graphics too.
     */
    @Test
    fun `the card rides the curve instead of the top edge`() {
        showScreenWithSixFigureChfPrices()

        val low = scrubTo(0.15f)
        val high = scrubTo(0.55f)

        assertTrue(
            "Both scrubs landed on the same sample (${low.price}), so there is no " +
                "vertical movement to measure. Pick x positions further apart.",
            high.price > low.price,
        )

        val chartHeightPx = composeRule.onNodeWithTag(TestID.Value.graphView)
            .fetchSemanticsNode().boundsInRoot.height
        val expectedShift = -(high.priceFraction - low.priceFraction) * chartHeightPx

        println(
            "GRAPH CARD y-tracking: ${low.price} at ${"%.1f".format(low.top)}px, " +
                "${high.price} at ${"%.1f".format(high.top)}px, " +
                "expected shift ${"%.1f".format(expectedShift)}px",
        )

        assertEquals(
            "The card moved ${"%.1f".format(high.top - low.top)} px between two prices " +
                "that are ${"%.1f".format(-expectedShift)} px apart on the curve. A card " +
                "pinned to the top edge moves 0.",
            expectedShift.toDouble(),
            (high.top - low.top).toDouble(),
            PLACEMENT_TOLERANCE_PX,
        )
    }

    /**
     * The one place this deviates from iOS on purpose.
     *
     * At the top of the series iOS's own formula puts the card's bottom edge at y = 0 —
     * the whole card above the view, which UIKit happily draws outside the bounds and
     * Compose clips away. So the port clamps, the same way the horizontal position is
     * already clamped at the left and right edges. Without the clamp the card is
     * roughly a card-height above the chart here, so this is not a tolerance check.
     */
    @Test
    fun `the card stays inside the chart at the peak of the curve`() {
        showScreenWithSixFigureChfPrices()
        scrubTo(0.98f)

        val chartTop = composeRule.onNodeWithTag(TestID.Value.graphView)
            .fetchSemanticsNode().boundsInRoot.top
        val cardTop = dateNode().fetchSemanticsNode().boundsInRoot.top

        assertTrue(
            "The card's top label is ${"%.1f".format(chartTop - cardTop)} px above the " +
                "chart at the highest sample, where it would be clipped away.",
            cardTop >= chartTop - PLACEMENT_TOLERANCE_PX,
        )
    }

    /**
     * The date reads as a caption, and the price as the value.
     *
     * iOS does this with `dateLabel.alpha = 0.4` (`GraphView.swift:131`) on black text
     * over a hard-coded white card, which is 2.85 : 1 — below even the large-text
     * floor, for a 13 sp regular label. So the de-emphasis is a token instead, and
     * `TokenContrastTest` holds the measurement. BIT-155, and the same call BIT-94 made.
     *
     * This asserts the *call site*, which is the half the arithmetic cannot see: a
     * card that drew both labels in the same token would pass every contrast test.
     *
     * **Run in both schemes since BIT-156**, because the card stopped following the
     * canvas. The tokens are fixed, so the expectation is the same in each — and the
     * failure this catches is a label back on `onCanvas` or `mutedOnCanvas`, which is
     * identical to the right answer in light and is the card itself in dark. Checking
     * light alone cannot tell those apart.
     */
    @Test
    fun `the date is de-emphasised with the token and the price is not`() =
        assertCardLabelTokens("light")

    @Test
    @Config(qualifiers = "w411dp-h891dp-night-420dpi")
    fun `the card's labels take the same tokens in dark mode`() =
        assertCardLabelTokens("dark")

    private fun assertCardLabelTokens(scheme: String) {
        showScreenWithSixFigureChfPrices()
        holdScrub()

        val date = dateNode().layout().layoutInput.style.color
        val price = composeRule.onNodeWithTag(TestID.Value.graphValueLabel)
            .layout().layoutInput.style.color

        println("GRAPH CARD colours ($scheme): date=$date price=$price")

        assertEquals(
            "$scheme: the date is drawn at full strength, so the card has no " +
                "caption/value hierarchy — iOS dims it to 0.4 and this port's " +
                "equivalent is the token.",
            BittrLightColorsExtended.onChartSurfaceMuted,
            date,
        )
        assertEquals(
            "$scheme: the price is the value in this card. It takes the chart card's " +
                "own ink rather than the canvas's, because the card is a fixed light " +
                "surface and the canvas's ink is white in dark.",
            BittrLightColorsExtended.onChartSurface,
            price,
        )
    }

    /**
     * The card is a card in dark mode — measured off the render, not off the tokens.
     *
     * `TokenContrastTest` proves the chosen fill has an edge on the canvas. It cannot
     * prove the call site picked that fill, and that is exactly what went wrong: the
     * card filled with `scrim1`, which is right in light and is `blue1` in dark, where
     * the canvas is also `blue1`. **The rendered card was byte-identical to the page
     * behind it**, and every contrast assertion in the theme stayed green.
     *
     * So this samples the pixels. A pixel inside the card and a pixel on the canvas
     * beside it, at the same height, and they have to differ — the single check that
     * the BIT-155 render would have failed.
     */
    @Test
    @Config(qualifiers = "w411dp-h891dp-night-420dpi")
    fun `the scrub card is distinguishable from the dark canvas it floats on`() {
        showScreenWithSixFigureChfPrices()
        holdScrub()

        val chart = composeRule.onNodeWithTag(TestID.Value.graphView)
        val bounds = chart.fetchSemanticsNode().boundsInRoot
        val card = dateNode().fetchSemanticsNode().boundsInRoot
        val image = chart.captureToImage().asAndroidBitmap()

        // Bitmap coordinates are relative to the captured node, so the chart's own
        // origin comes off both.
        fun sample(x: Float, y: Float) = image.getPixel(
            (x - bounds.left).toInt().coerceIn(0, image.width - 1),
            (y - bounds.top).toInt().coerceIn(0, image.height - 1),
        )

        val inside = sample(card.center.x, card.center.y)
        // Far enough along the row to be outside an 80 dp card wherever it is sitting,
        // and clamped into the chart, so this lands on the canvas at the card's height.
        val beside = sample(
            if (card.center.x < bounds.center.x) bounds.right - 1f else bounds.left + 1f,
            card.center.y,
        )

        println(
            "GRAPH CARD dark fill: inside=#%08X beside=#%08X".format(inside, beside),
        )

        assertNotEquals(
            "The scrub card renders the same pixel as the canvas beside it, so it has " +
                "no edge at all — the labels float over the chart and the curve runs " +
                "through where the card's boundary should be. This is what `scrim1` did " +
                "in dark: it is `blue1`, and so is the canvas.",
            beside,
            inside,
        )

        // The dark render the issue had to be reported with a hand capture for.
        capture("411dp-night")
    }

    /**
     * The curve is stroked in the scheme's own token, checked on the pixels.
     *
     * It was `Color(0x…)`, a near-black literal, so it did not move with the scheme:
     * 10.97 : 1 on the light canvas — which is why nobody noticed — and **2.43 : 1 on
     * the dark one**, under the 3 : 1 WCAG 1.4.11 puts on a graphical object. iOS
     * strokes it with `whiteoryellow` (`GraphView.swift:175`), which DEV-47 merged into
     * `emphasis`.
     *
     * `TokenContrastTest` can measure `emphasis` against both canvases and does. What
     * it cannot do is notice that this `drawPath` went back to a literal, and a literal
     * is what shipped — so the check that matters is this one, on the rendered stroke.
     * A `Canvas` has no semantics to read, which is why it is pixels rather than a
     * layout property. BIT-156.
     */
    @Test
    fun `the curve is stroked in the light scheme's token`() =
        assertCurveIsStrokedWith(BittrLightColorsExtended.emphasis, "light")

    @Test
    @Config(qualifiers = "w411dp-h891dp-night-420dpi")
    fun `the curve is stroked in the dark scheme's token`() =
        assertCurveIsStrokedWith(BittrDarkColorsExtended.emphasis, "dark")

    /**
     * Counts pixels of exactly [expected] in the chart.
     *
     * Exact equality, not a nearest-colour search: the stroke is 4 px wide, so its
     * interior is the unblended colour even though its edges are antialiased. A
     * tolerance would start matching the canvas as the two tokens approach each other,
     * which is the failure this is here to catch.
     *
     * The card is excluded by construction — it is white with ink on it, and neither
     * value of `emphasis` is either.
     */
    private fun assertCurveIsStrokedWith(expected: Color, scheme: String) {
        showScreenWithSixFigureChfPrices()

        val image = composeRule.onNodeWithTag(TestID.Value.graphView)
            .captureToImage().asAndroidBitmap()
        val wanted = expected.toArgb()
        var found = 0
        for (x in 0 until image.width) {
            for (y in 0 until image.height) {
                if (image.getPixel(x, y) == wanted) found++
            }
        }

        println("GRAPH CURVE ($scheme): ${"%,d".format(found)} px of #%08X".format(wanted))

        assertTrue(
            "$scheme: not one pixel of the chart is the scheme's `emphasis` " +
                "(#%08X), so the curve is drawn in something else. It was a near-black "
                    .format(wanted) +
                "literal, which is 2.43 : 1 on the dark canvas.",
            found > 0,
        )
    }

    private fun assertCardFits(label: String) {
        showScreenWithSixFigureChfPrices()
        holdScrub()

        val price = composeRule.onNodeWithTag(TestID.Value.graphValueLabel)
        val priceText = price.text()
        assumeNativeTextMetrics(price.layout(), priceText)

        // The symbol comes from the loaded value, so a wrong currency here would
        // quietly measure the easy case and still be green.
        assertTrue(
            "Expected a six-figure CHF price under the finger, got \"$priceText\"",
            priceText.startsWith("CHF ") && priceText.count { it.isDigit() } >= 6,
        )
        assertFitsOneLine("$label price \"$priceText\"", price.layout())

        // The date moved from iOS's Gilroy-Regular 10 to the scale's 13 sp floor in
        // BIT-151 and has not been rendered since. Same card, so same question.
        val date = dateNode()
        assertFitsOneLine("$label date \"${date.text()}\"", date.layout())

        capture(label)
    }

    private fun showScreenWithSixFigureChfPrices() {
        val loaded = snapshot()
        val repository = object : PriceRepository {
            override suspend fun load(currency: PriceCurrency, today: LocalDate) = loaded
        }

        composeRule.setContent {
            BittrTheme {
                ValueScreen(
                    onBack = {},
                    repository = repository,
                    currency = PriceCurrency.CHF,
                )
            }
        }

        // `profitLabel` is the screen's own "data has landed" signal — the same one
        // `bitcoin_value.yaml` waits for. Scrubbing before it appears drags across an
        // empty chart and produces no card.
        composeRule.waitUntil(TIMEOUT_MS) {
            composeRule.onAllNodesWithTag(TestID.Value.profitLabel)
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    /**
     * Brings the card up and leaves it up.
     *
     * `touchesEnded` tears the card off on iOS and [GraphView] reproduces that, so
     * there is no lifted-finger state in which to measure this — the block ends
     * without an `up()` on purpose. The move has to clear touch slop or
     * `detectDragGestures` never starts.
     */
    private fun holdScrub() {
        composeRule.onNodeWithTag(TestID.Value.graphView).performTouchInput {
            down(center)
            moveTo(Offset(center.x + 120f, center.y))
        }
        composeRule.waitForIdle()
    }

    /** Whether [scrubTo] has already put a finger down in this composition. */
    private var scrubbing = false

    /**
     * Moves the held finger to [fraction] of the chart's width and reads the card back.
     *
     * The finger is put down once and then moved, because the card only exists while it
     * is down. The first move starts from the far end so it clears touch slop in one
     * event whichever way it is heading — a move shorter than slop never reaches
     * `detectDragGestures` and no card appears at all. Inset from the edge rather than
     * on it: `x = width` is one past the last pixel of the chart and the press lands
     * outside it, which is a silent no-gesture rather than an error.
     */
    private fun scrubTo(fraction: Float): ScrubReading {
        composeRule.onNodeWithTag(TestID.Value.graphView).performTouchInput {
            if (!scrubbing) {
                down(Offset(width * if (fraction > 0.5f) 0.05f else 0.95f, center.y))
                scrubbing = true
            }
            moveTo(Offset(width * fraction, center.y))
        }
        composeRule.waitForIdle()

        val node = composeRule.onNodeWithTag(TestID.Value.graphValueLabel)
        val price = node.text().filter { it.isDigit() }.toDouble()
        return ScrubReading(
            price = price,
            priceFraction = priceFractionOf(price),
            top = node.fetchSemanticsNode().boundsInRoot.top,
        )
    }

    /** What the card is showing, and where it is. [top] is the price label's, in px. */
    private data class ScrubReading(
        val price: Double,
        val priceFraction: Float,
        val top: Float,
    )

    /**
     * Where [price] sits in its own span's range.
     *
     * Which span is selected is the screen's business, so the price is looked up across
     * all of them — [snapshot] offsets each span by a different amount, so a price
     * belongs to exactly one. Computed here rather than through `priceFractions()` so
     * that the expectation is independent of the production code it is checking.
     */
    private fun priceFractionOf(price: Double): Float {
        for (series in snapshot().series.values) {
            if (series.none { it.price == price }) continue
            val lowest = series.minOf { it.price }
            return ((price - lowest) / (series.maxOf { it.price } - lowest)).toFloat()
        }
        error("Price $price is in none of the spans this test loaded")
    }

    /**
     * The card's other label, found by the string the card actually puts in it.
     *
     * Which sample the finger lands on is a property of [scrub] and the chart's
     * width, so the date is not known in advance — every date in the series is a
     * candidate and exactly one of them is on screen.
     */
    private fun dateNode(): SemanticsNodeInteraction {
        val candidates = snapshot().series.values.flatten()
            .map { CardDateFormat.format(it.at.atZone(ZoneId.systemDefault())) }
            .distinct()
        for (candidate in candidates) {
            val nodes = composeRule.onAllNodesWithText(candidate)
            if (nodes.fetchSemanticsNodes().isNotEmpty()) return nodes[0]
        }
        error("No date label on screen; candidates were $candidates")
    }

    /**
     * One line, inside the card.
     *
     * **`hasVisualOverflow` and `didOverflowWidth` are deliberately not asserted
     * here, because in this card they are true for everything.** The `Column` is a
     * fixed `width(80.dp)`, so it hands the text an exact-width constraint;
     * `multiParagraph.width` comes back as that constraint (210 px at 411 dp / 2.625,
     * 160 px at 320 dp / 2.0 — both exactly 80 dp) while `size` shrink-wraps the
     * glyphs, and the flag is the comparison of the two. Measured: the date `08 Sep`
     * reports `didOverflowWidth = true` at **42 dp** in an 80 dp card. A fit
     * assertion built on that flag would be red on correct text and could never go
     * green, which is a different way of not measuring anything.
     *
     * [TextLayoutResult.lineCount] and the line's own edges do discriminate — they
     * are what caught the Bold 16 price — so they are what this asserts.
     */
    private fun assertFitsOneLine(what: String, layout: TextLayoutResult) {
        val widestDp = widestLinePx(layout) / composeRule.density.density

        println(
            "GRAPH CARD $what: lines=${layout.lineCount} " +
                "widest=${"%.1f".format(widestDp)}dp of ${CARD_WIDTH_DP.toInt()}dp",
        )

        assertEquals(
            "$what wrapped onto ${layout.lineCount} lines inside the " +
                "${CARD_WIDTH_DP.toInt()} dp card. Nothing raises a layout error here — " +
                "the card is positioned by hand and grows downward — so this assertion " +
                "is the only thing that notices.",
            1,
            layout.lineCount,
        )
        assertTrue(
            "$what measures ${"%.1f".format(widestDp)} dp, wider than the " +
                "${CARD_WIDTH_DP.toInt()} dp card.",
            widestDp <= CARD_WIDTH_DP,
        )
    }

    /**
     * Skips rather than passes when the text metrics are Robolectric's stubs.
     *
     * Real Gilroy at this scale is ~13–18 px per character; `LEGACY` returns ~1. A
     * threshold of 3 px separates them by a wide margin and does not depend on which
     * label is being checked.
     */
    private fun assumeNativeTextMetrics(layout: TextLayoutResult, text: String) {
        val pxPerChar = widestLinePx(layout) / text.length.coerceAtLeast(1)
        assumeTrue(
            "Text metrics look like Robolectric's LEGACY stubs " +
                "(${"%.1f".format(pxPerChar)} px/char for \"$text\") — native graphics is " +
                "unavailable on this host, so a fit assertion would pass without measuring " +
                "anything. Skipping instead of reporting green.",
            pxPerChar > 3f,
        )
    }

    /**
     * There is no `TextLayoutResult.getLineWidth`; a line's width is the difference
     * of its two edges, and the widest line is what has to fit.
     */
    private fun widestLinePx(layout: TextLayoutResult): Float =
        (0 until layout.lineCount).maxOf { layout.getLineRight(it) - layout.getLineLeft(it) }

    /** Evidence for a human. Never the reason this test is red. */
    private fun capture(label: String) {
        val outputDir = System.getProperty("bittr.screenshot.dir") ?: return
        runCatching {
            val bitmap = composeRule.onNodeWithTag(TestID.Value.graphView)
                .captureToImage().asAndroidBitmap()
            val file = File(outputDir).apply { mkdirs() }
                .resolve("graph-scrub-card-$label.png")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            println(
                "GRAPH CARD screenshot ($label): ${file.absolutePath} " +
                    "(${bitmap.width}x${bitmap.height})",
            )
        }.onFailure { println("GRAPH CARD screenshot ($label) unavailable: $it") }
    }

    private fun SemanticsNodeInteraction.layout(): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(results)
        return results.first()
    }

    private fun SemanticsNodeInteraction.text(): String = layout().layoutInput.text.text

    /**
     * Every point six figures, so whichever sample the finger lands on is the wide
     * case rather than a lucky narrow one.
     */
    private fun snapshot(): PriceSnapshot {
        val series = GraphSpan.entries.associateWith { span ->
            (0..9).map { step ->
                PricePoint(
                    at = SNAPSHOT_INSTANT.minusSeconds((10L - step) * 86_400),
                    price = 110_000.0 + step * 1_000 + span.ordinal * 10,
                )
            }
        }
        return PriceSnapshot(series = series, currentPrice = 120_000.0)
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L

        /** From `GraphView.kt`'s `CardWidth`, and iOS's 80 pt constraint. */
        const val CARD_WIDTH_DP = 80f

        /**
         * The card is placed at a rounded pixel and the chart's height is read back
         * through a `Rect`, so two roundings separate the expectation from the
         * measurement. Two pixels covers both and is far under the ~115 px card height
         * that the defect this guards against was worth.
         */
        const val PLACEMENT_TOLERANCE_PX = 2.0

        val SNAPSHOT_INSTANT: Instant = Instant.parse("2026-09-12T12:00:00Z")
    }
}
