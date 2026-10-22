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
import kotlin.math.abs
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import com.bittr.android.core.designsystem.BittrDarkColorsExtended
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
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
 * is where it would invert again: a white selected segment straight on a white card.
 * Pass 2 answered with cream-selected; the third review asked again for white-selected
 * on cream, so the whole control now sits on a cream track and the selected segment is
 * white inside it — see `RangeSelector`. This pins both, and that they differ.
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
    fun `the selected span button is white and the others white at 70 percent`() {
        showValueScreen()

        val selected = fillOf(TestID.Value.weekButton)
        val unselected = fillOf(TestID.Value.yearButton)

        println("SPAN FILLS: selected=#%08X unselected=#%08X".format(selected, unselected))

        assertNotEquals(
            "The selected and unselected buttons render the same fill, so the fill " +
                "says nothing about which range is active.",
            unselected,
            selected,
        )
        assertEquals(
            "The selected button is not white, as `showSelectedSpan` paints it.",
            Color.White.toArgb(),
            selected,
        )
        assertColorNear(
            "The unselected buttons are not white at 70 % over the card. The card follows " +
                "the scheme — blue2 here — and the buttons sit on it.",
            Color.White.copy(alpha = 0.7f).compositeOver(BittrDarkColorsExtended.levelCard).toArgb(),
            unselected,
        )
    }

    /**
     * Each channel within one step of [expected].
     *
     * Skia stores 0.7 alpha as 179 / 255, a shade over 0.7, so its blend comes out one
     * step whiter in some channels than `compositeOver` works out in floats.
     */
    private fun assertColorNear(message: String, expected: Int, actual: Int) {
        val near = listOf(24, 16, 8, 0).all { shift ->
            abs((expected shr shift and 0xFF) - (actual shr shift and 0xFF)) <= 1
        }
        assertTrue(
            // Only the suffix is a format string: the message has a literal "70 %" in it.
            message + " expected:<#%08X> but was:<#%08X>".format(expected, actual),
            near,
        )
    }

    /**
     * A pixel of a button's fill: horizontally centred, 4 dp below its top edge — clear of the
     * label, which is centred in the 30 dp plate, and of the rounded corners at the ends.
     */
    private fun fillOf(testTag: String): Int {
        val image = composeRule.onNodeWithTag(testTag).captureToImage().asAndroidBitmap()
        val down = (4 * composeRule.density.density).toInt()
        return image.getPixel(image.width / 2, down)
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
