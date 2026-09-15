package com.bittr.android.feature.value

import android.graphics.Bitmap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
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
import com.bittr.android.core.designsystem.BittrTheme
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
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

        val SNAPSHOT_INSTANT: Instant = Instant.parse("2026-09-12T12:00:00Z")
    }
}
