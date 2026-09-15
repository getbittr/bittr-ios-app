package com.bittr.android.feature.value

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrDarkColorsExtended
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
 * Which span button looks selected, measured on the pixels.
 *
 * The four buttons say which one is active twice: the selected one swaps its short
 * title for the long one (`showSelectedSpan`, and `bitcoin_value.yaml` depends on
 * that), and it fills differently from the other three. This is about the fill.
 *
 * ### Why this is rendered rather than read off the tokens
 *
 * `TokenContrastTest` can prove the selected fill stands further off the canvas than
 * the unselected one. It cannot prove these four call sites picked those two tokens,
 * and that is precisely what went wrong: the port filled selected with `scrim1` and
 * unselected with `scrim2`, which are **byte-identical in light mode** — so light had
 * no fill signal at all and every contrast assertion in the theme was green — while in
 * dark `scrim1` is `blue1`, which is also the canvas. The *selected* pill was the
 * invisible one and the three unselected ones were the ones with an edge. An inverted
 * affordance, reached by measuring the tokens and never the screen. BIT-156.
 *
 * Runs in dark because that is the scheme where the two fills differ most, and where
 * the collision with the canvas lives.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-night-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SpanButtonAffordanceTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `the selected span button is filled, and not with the canvas behind it`() {
        showValueScreen()

        val selected = fillOf(TestID.Value.weekButton)
        val unselected = fillOf(TestID.Value.yearButton)
        val canvas = BittrDarkColorsExtended.canvas.toArgb()

        println(
            "SPAN FILLS: selected=#%08X unselected=#%08X canvas=#%08X"
                .format(selected, unselected, canvas),
        )

        assertNotEquals(
            "The selected span button renders the canvas's own colour, so it has no " +
                "edge — it is the page. `scrim1` is `blue1` in dark and so is `canvas`, " +
                "which is how this shipped.",
            canvas,
            selected,
        )
        assertNotEquals(
            "The selected and unselected span buttons render the same fill, so the fill " +
                "says nothing about which span is active. `scrim1` and `scrim2` are " +
                "byte-identical in light mode, which is how that half went unnoticed.",
            unselected,
            selected,
        )
        // The direction, which is the part that was backwards rather than missing:
        // the selected pill is the opaque one, the other three are the wash.
        assertEquals(
            "The selected span button is not the opaque fill, so the two are the wrong " +
                "way round — the unselected pills are the ones standing off the canvas.",
            BittrDarkColorsExtended.chartSurface.toArgb(),
            selected,
        )
    }

    /** The centre of a button, inset from its own text by sampling the top-left area. */
    private fun fillOf(testTag: String): Int {
        val image = composeRule.onNodeWithTag(testTag).captureToImage().asAndroidBitmap()
        // Inside the rounded corner and clear of the centred label: a quarter in
        // horizontally, a sixth down. The button is a 48 dp touch target, so this is
        // fill in every density this test runs at.
        return image.getPixel(image.width / 4, image.height / 6)
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
        // Same "data has landed" signal the flow waits on. The span buttons exist
        // before it, but taps are dropped while the fetch is in flight.
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
