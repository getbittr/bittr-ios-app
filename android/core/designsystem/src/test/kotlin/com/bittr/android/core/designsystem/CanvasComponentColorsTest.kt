package com.bittr.android.core.designsystem

import androidx.compose.material3.SwitchColors
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Which token a canvas component reads — the half `TokenContrastTest` says it cannot see.
 *
 * That file's own header is explicit: *"What this cannot check: whether a call site uses
 * the right token."* BIT-95 is what that sentence costs when the call site is the bug.
 * `bittrSwitchColors()` set `checkedBorderColor = SwitchOn`, the same value as
 * `checkedTrackColor`, so the checked switch had no edge of its own — and because the
 * colour was a `private val` in `Canvas.kt` and the wiring was inside a `@Composable`,
 * neither the arithmetic guard nor any screenshot of the arc could reach it. Revert the
 * one line that caused it and `TokenContrastTest` still passes all thirty-five.
 *
 * So this asserts the wiring. It needs a composition because `BittrTheme.colors` is a
 * composition local, which is also the reason the defect was invisible — and it is
 * Robolectric only for that, not for pixels. Contrast numbers stay in
 * `TokenContrastTest`, where they belong; nothing here does arithmetic.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class CanvasComponentColorsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private data class Probe(val switch: SwitchColors, val tokens: BittrColors)

    /**
     * Both schemes out of one composition.
     *
     * `setContent` may only be called once per rule, so the two themes are composed
     * side by side rather than in a loop of set-ups — which is also closer to the truth
     * being checked: these are two readings of the same component, not two components.
     */
    private val probes: Map<Boolean, Probe> by lazy {
        val out = mutableMapOf<Boolean, Probe>()
        composeRule.setContent {
            for (dark in listOf(false, true)) {
                BittrTheme(darkTheme = dark) {
                    out[dark] = Probe(bittrSwitchColors(), BittrTheme.colors)
                }
            }
        }
        composeRule.waitForIdle()
        out
    }

    private fun probe(darkTheme: Boolean): Probe =
        probes.getValue(darkTheme)

    @Test
    fun `BIT-95 the checked switch border is the muted token and not the track`() {
        for (dark in listOf(false, true)) {
            val name = if (dark) "dark" else "light"
            val (switch, tokens) = probe(dark)

            // The regression, named. A control whose border is its own fill has no
            // boundary, which is the 1.4.11 failure BIT-95 filed — 1.32 : 1 against the
            // card in dark mode. `TokenContrastTest` measures what this pairing means;
            // this line is what stops the pairing coming back.
            assertNotEquals(
                "$name checked border must not be the checked track",
                switch.checkedTrackColor,
                switch.checkedBorderColor,
            )
            assertEquals(
                "$name checked border should be mutedOnCanvas — the token the unchecked " +
                    "state already used, and the one the contrast guard measures",
                tokens.mutedOnCanvas,
                switch.checkedBorderColor,
            )
            // Both states share the border, so the outline stays put across the toggle
            // and only the fill and the thumb move.
            assertEquals(
                "$name the two states should share one border",
                switch.checkedBorderColor,
                switch.uncheckedBorderColor,
            )
        }
    }

    @Test
    fun `BIT-95 the switch reads its fill and thumb from the theme, not from literals`() {
        for (dark in listOf(false, true)) {
            val name = if (dark) "dark" else "light"
            val (switch, tokens) = probe(dark)

            // `switchAccent` lived as a `private val` in `Canvas.kt` and the thumb was a
            // bare `Color.White`. Both are tokens now, which is the only reason
            // `TokenContrastTest` can hold them at all — see `BittrColors.switchOn`.
            assertEquals("$name checked track", tokens.switchOn, switch.checkedTrackColor)
            assertEquals("$name checked thumb", tokens.onSwitchOn, switch.checkedThumbColor)
            assertEquals("$name unchecked thumb", tokens.mutedOnCanvas, switch.uncheckedThumbColor)
            // Unchecked is deliberately see-through: the canvas shows through the track,
            // which is what makes the border the only thing outlining it.
            assertEquals(
                "$name unchecked track", Color.Transparent, switch.uncheckedTrackColor,
            )
        }
    }
}
