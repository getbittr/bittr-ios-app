package com.bittr.android.feature.value

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrLightColorsExtended
import com.bittr.android.core.designsystem.BittrTheme
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Which range segment looks selected, measured on the pixels.
 *
 * The segments say which one is active three ways: the selected one swaps its short
 * title for the long one (`showSelectedSpan`, and `bitcoin_value.yaml` depends on
 * that), it carries a leading check, and it fills differently from the other three.
 * This is about the fill.
 *
 * ### Why this is rendered rather than read off the tokens
 *
 * Token arithmetic cannot prove these call sites picked the right fills, and that is
 * precisely what went wrong once: the port filled selected with `scrim1` and
 * unselected with `scrim2`, which are **byte-identical in light mode** — no fill signal
 * at all — while in dark `scrim1` is `blue1`, also the canvas, so the *selected* pill
 * was the invisible one. An inverted affordance, reached by measuring the tokens and
 * never the screen. BIT-156.
 *
 * The design review (2026-09-18) moved the control onto the white chart card, which
 * is where it would invert again if it kept the old direction: a white selected
 * segment on a white card. So selected is now the cream and unselected the card's own
 * white — see `RangeSelector` — and this pins both, and that they differ.
 *
 * Runs in dark because that is the scheme where a fill that follows the scheme would
 * give itself away: `tonalFill` there is `blue3`.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-night-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SpanButtonAffordanceTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `the selected range segment is the cream and the rest are the card's white`() {
        showValueScreen()

        val selected = fillOf(TestID.Value.weekButton)
        val unselected = fillOf(TestID.Value.yearButton)

        println("SPAN FILLS: selected=#%08X unselected=#%08X".format(selected, unselected))

        assertNotEquals(
            "The selected and unselected segments render the same fill, so the fill " +
                "says nothing about which range is active.",
            unselected,
            selected,
        )
        assertEquals(
            "The selected segment is not the pinned cream. On the white chart card a " +
                "white selected segment is the one that disappears — the inversion " +
                "BIT-156 fixed once on this screen.",
            BittrLightColorsExtended.tonalFill.toArgb(),
            selected,
        )
        assertEquals(
            "The unselected segments are not the chart card's white.",
            BittrLightColorsExtended.chartSurface.toArgb(),
            unselected,
        )
    }

    /**
     * A pixel of a segment's fill: horizontally centred, 15 dp above the middle.
     *
     * The segment is a 48 dp touch target around a 40 dp drawn band, and the label is
     * centred in it at 20 dp tall — so 15 dp up is inside the band and clear of the
     * text, and at the horizontal centre it is clear of the rounded ends and the
     * dividers.
     */
    private fun fillOf(testTag: String): Int {
        val image = composeRule.onNodeWithTag(testTag).captureToImage().asAndroidBitmap()
        val up = (15 * composeRule.density.density).toInt()
        return image.getPixel(image.width / 2, image.height / 2 - up)
    }

    private fun showValueScreen() {
        val loaded = PriceSnapshot(
            series = GraphSpan.entries.associateWith { span ->
                (0..9).map { step ->
                    PricePoint(
                        at = SNAPSHOT_INSTANT.minusSeconds((10L - step) * 86_400),
                        price = 110_000.0 + step * 1_000 + span.ordinal * 10,
                    )
                }
            },
            currentPrice = 120_000.0,
        )
        composeRule.setContent {
            BittrTheme {
                ValueScreen(
                    onBack = {},
                    repository = object : PriceRepository {
                        override suspend fun load(currency: PriceCurrency, today: LocalDate) =
                            loaded
                    },
                )
            }
        }
        // Same "data has landed" signal the flow waits on. The segments exist before
        // it, but are disabled while the fetch is in flight.
        composeRule.waitUntil(TIMEOUT_MS) {
            composeRule.onAllNodesWithTag(TestID.Value.profitLabel)
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        val SNAPSHOT_INSTANT: Instant = Instant.parse("2026-09-12T12:00:00Z")
    }
}
