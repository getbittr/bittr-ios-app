package com.bittr.android.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * The accessibility fixes in this theme, as assertions.
 *
 * BIT-4 §5 found twenty contrast failures in the iOS palette and §1.3 fixes the ones
 * that live in the theme. Every one of those fixes is one keystroke from being
 * reverted by someone who thinks a colour looks wrong — this is what makes that
 * revert fail the build instead of shipping.
 *
 * Runs on the JVM. `androidx.compose.ui.graphics.Color` is pure Kotlin for the sRGB
 * path, so no emulator and no Robolectric.
 *
 * **What this cannot check:** whether a call site uses the right token. A screen that
 * hard-codes `Color.White` on `primary` passes every test here. That is caught by the
 * per-screen specs and review, not by arithmetic.
 */
class TokenContrastTest {

    // -----------------------------------------------------------------------
    // WCAG 2.1 relative luminance and contrast — https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
    // -----------------------------------------------------------------------

    private fun linearize(channel: Float): Double {
        val c = channel.toDouble()
        return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
    }

    private fun luminance(color: Color): Double =
        0.2126 * linearize(color.red) + 0.7152 * linearize(color.green) + 0.0722 * linearize(color.blue)

    /**
     * [fg] flattened onto [bg] — in sRGB, which is what Compose does and, per §1.1a,
     * what iOS turns out to match to within 1/255. An opaque [fg] is returned as-is.
     */
    private fun composite(fg: Color, bg: Color): Color =
        if (fg.alpha >= 1f) fg else Color(
            red = fg.red * fg.alpha + bg.red * (1f - fg.alpha),
            green = fg.green * fg.alpha + bg.green * (1f - fg.alpha),
            blue = fg.blue * fg.alpha + bg.blue * (1f - fg.alpha),
        )

    /** Contrast of [fg] over [bg]. A translucent [fg] is composited onto [bg] first. */
    private fun contrast(fg: Color, bg: Color): Double {
        val a = luminance(composite(fg, bg))
        val b = luminance(bg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private fun assertAtLeast(floor: Double, fg: Color, bg: Color, what: String) {
        val actual = contrast(fg, bg)
        assertTrue(
            "$what: %.2f : 1, needs %.1f : 1".format(actual, floor),
            actual >= floor - 0.005,
        )
    }

    /** WCAG AA, body text. */
    private val aa = 4.5

    /** WCAG AA, large text (≥ 18sp, or ≥ 14sp bold) and non-text UI under 1.4.11. */
    private val aaLarge = 3.0

    // -----------------------------------------------------------------------
    // The conversion itself — §1.1a. Six primitives were measured in the capture.
    // -----------------------------------------------------------------------

    @Test
    fun `brand yellow is the sRGB conversion, not the iOS Display P3 hex`() {
        // #F6C744 is what Colors.swift says. Pasting it renders a visibly duller
        // yellow than iOS shows, because that number is P3 and Compose is sRGB.
        // #FFC502 was measured on swap/08_home_final at 41.3 % of the screen. DEV-01.
        assertEquals(0xFFFFC502.toInt(), BittrLightColors.primary.toArgbInt())
    }

    @Test
    fun `dark mode is built on blue1 and blue2, not the converted P3 blue3`() {
        assertEquals(0xFF3A5983.toInt(), BittrDarkColors.surface.toArgbInt())
        assertEquals(0xFF446591.toInt(), BittrDarkColors.surfaceContainer.toArgbInt())
    }

    // -----------------------------------------------------------------------
    // A11Y-01 / A11Y-15 — secondary text
    // -----------------------------------------------------------------------

    @Test
    fun `A11Y-01 light secondary text clears AA on every surface it lands on`() {
        // iOS `transparentblack` is black @50 % — 3.95 : 1 on white, a fail. 60 % is the fix.
        val fg = BittrLightColors.onSurfaceVariant
        assertAtLeast(aa, fg, BittrLightColors.surfaceContainer, "secondary text on white")
        assertAtLeast(aa, fg, BittrLightColors.surface, "secondary text on grey1")
        // A11Y-15: the three escape-hatch controls — "I don't have an IBAN", "Resend
        // code", "Back" — are this token on the brand yellow. 3.63 on iOS, 4.93 here.
        assertAtLeast(aa, fg, BittrLightColors.primary, "secondary text on brand yellow")
    }

    @Test
    fun `A11Y-01 dark secondary text clears AA, and 70 percent would not`() {
        val fg = BittrDarkColors.onSurfaceVariant
        assertAtLeast(aa, fg, BittrDarkColors.surface, "secondary text on blue1")
        assertAtLeast(aa, fg, BittrDarkColors.surfaceContainer, "secondary text on blue2")
        // The reason 80 % is the floor rather than a preference: 70 % reaches only 3.87
        // on blue2. If someone softens this token, this is the line that explains why.
        assertTrue(
            "white @70 % would regress dark secondary text below AA",
            contrast(Color.White.copy(alpha = 0.70f), BittrDarkColors.surfaceContainer) < aa,
        )
    }

    // -----------------------------------------------------------------------
    // A11Y-02 — the dark surface
    // -----------------------------------------------------------------------

    @Test
    fun `A11Y-02 body text clears AA on both dark surfaces`() {
        // iOS uses blue3 here and white on blue3 is 4.44 — it misses, and it ships today.
        assertAtLeast(aa, BittrDarkColors.onSurface, BittrDarkColors.surface, "body on dark surface")
        assertAtLeast(
            aa, BittrDarkColors.onSurface, BittrDarkColors.surfaceContainer,
            "body on dark surfaceContainer",
        )
    }

    // -----------------------------------------------------------------------
    // A11Y-16 / DEV-47 — the merged emphasis token
    // -----------------------------------------------------------------------

    @Test
    fun `A11Y-16 the screen title clears the large-text floor in both modes`() {
        // This is the one that reached furthest: every screen title, all 55 alert titles,
        // the Academy level headers — 16 call sites at 1.59 : 1 before DEV-47.
        assertAtLeast(
            aaLarge, BittrLightColorsExtended.emphasis, BittrLightColors.primary,
            "screen title on brand yellow, light",
        )
        assertAtLeast(
            aaLarge, BittrDarkColorsExtended.emphasis, BittrDarkColors.primary,
            "screen title on primary, dark",
        )
    }

    @Test
    fun `DEV-47 leaves dark mode byte-identical`() {
        // The merge only moves the light value. If this ever fails, the fix has grown
        // into a dark-mode redesign and needs to go back to the founder.
        assertEquals(0xFFFFC502.toInt(), BittrDarkColorsExtended.emphasis.toArgbInt())
    }

    // -----------------------------------------------------------------------
    // A11Y-04 / A11Y-06 — profit, loss, and the dimmed balance
    // -----------------------------------------------------------------------

    @Test
    fun `A11Y-04 profit and loss clear the large-text floor on every surface`() {
        val light = BittrLightColorsExtended
        for ((name, bg) in listOf(
            "white" to BittrLightColors.surfaceContainer,
            "grey1" to BittrLightColors.surface,
            "its own pill" to light.profitBg,
        )) {
            assertAtLeast(aaLarge, light.profit, bg, "profit on $name")
        }
        for ((name, bg) in listOf(
            "white" to BittrLightColors.surfaceContainer,
            "grey1" to BittrLightColors.surface,
            "its own pill" to light.lossBg,
        )) {
            // iOS red3 is 2.37 on its own pill. Darkened at constant hue to match profit.
            assertAtLeast(aaLarge, light.loss, bg, "loss on $name")
        }

        val dark = BittrDarkColorsExtended
        assertAtLeast(aa, dark.profit, BittrDarkColors.surface, "profit on dark surface")
        assertAtLeast(aa, dark.loss, BittrDarkColors.surface, "loss on dark surface")
    }

    @Test
    fun `A11Y-06 the dimmed balance digits clear the large-text floor`() {
        // The balance is 40sp, so 3 : 1 applies — but only while it stays above the 20sp
        // shrink floor. Below that it leaves the large-text band and needs 4.5, which no
        // longer reads as dimmed at all. That is what BittrTokens.Size.balanceMinTextSize
        // is protecting.
        assertAtLeast(
            aaLarge, BittrLightColorsExtended.balanceDimmed, BittrLightColors.surfaceContainer,
            "dimmed balance digits, light",
        )
        assertAtLeast(
            aaLarge, BittrDarkColorsExtended.balanceDimmed, BittrDarkColors.surfaceContainer,
            "dimmed balance digits, dark",
        )
    }

    // -----------------------------------------------------------------------
    // 1.4.11 — non-text
    // -----------------------------------------------------------------------

    @Test
    fun `A11Y-21 outlines clear the 3 to 1 non-text floor on every neutral surface`() {
        // This test is why A11Y-21 exists. The light outline was iOS's `grey2`, 2.59 : 1
        // on white — and §5.2 had already computed that number, for a different token,
        // without noticing that `grey2` *is* the outline and is already shipping at it.
        for ((name, bg) in listOf(
            "white" to BittrLightColors.surfaceContainer,
            "grey3" to BittrLightColors.surfaceBright,
            "grey1" to BittrLightColors.surface,
        )) {
            assertAtLeast(aaLarge, BittrLightColors.outline, bg, "outline on $name, light")
        }
        assertAtLeast(aaLarge, BittrDarkColors.outline, BittrDarkColors.surfaceContainer, "outline, dark")
    }

    @Test
    fun `nothing perceivable on the brand yellow can be an outline`() {
        // The rule in one assertion. No grey that still reads as grey clears 3 : 1 on
        // #FFC502; `onSurfaceVariant` does. If a border or a placeholder is ever needed
        // on a yellow surface — the Send address field and the Swap amount field both
        // have one — it uses onSurfaceVariant, not outline. A11Y-21, DEV-59.
        assertTrue(
            "outline is not usable on the brand yellow — use onSurfaceVariant",
            contrast(BittrLightColors.outline, BittrLightColors.primary) < aaLarge,
        )
        assertAtLeast(
            aa, BittrLightColors.onSurfaceVariant, BittrLightColors.primary,
            "the replacement for outline on yellow",
        )
    }

    // -----------------------------------------------------------------------
    // A11Y-21 / DEV-58 — the placeholder, which is text and not a border
    // -----------------------------------------------------------------------

    /**
     * The fill the Send and Swap placeholders actually sit on, light mode.
     *
     * Neither field is on the raw brand yellow. iOS fills them with `white0.7orblue1`
     * (Send address, Send amount) and `white0.7orblue3` (Swap amount) — [BittrColors.scrim1]
     * and [BittrColors.scrim3], both white @70 % in light mode — over the yellow screen
     * behind them. That composites to **#FFEEB3**, and that, not `primary`, is the surface
     * the placeholder has to be measured against.
     */
    private val lightFieldFill: Color
        get() = composite(BittrLightColorsExtended.scrim1, BittrLightColors.primary)

    @Test
    fun `A11Y-21 the Send and Swap placeholders clear AA as text on the field fill`() {
        // All three placeholders are Gilroy-Regular at pointSize 16 in Main.storyboard, so
        // this is body text: the floor is 4.5, not the 3.0 that applies to the border.
        // iOS uses `grey2` here and lands at 2.23 : 1. DEV-58 moves them to onSurfaceVariant.
        assertAtLeast(aa, BittrLightColors.onSurfaceVariant, lightFieldFill, "placeholder on the light field fill")
        // Dark: the two Send fields fill with scrim1 = blue1.
        assertAtLeast(
            aa, BittrDarkColors.onSurfaceVariant, BittrDarkColorsExtended.scrim1,
            "Send placeholder on the dark field fill",
        )
    }

    @Test
    fun `A11Y-21 outline is not a placeholder colour even where it clears the border floor`() {
        // This is the trap, and it is why the guard above is not enough on its own. On the
        // raw yellow `outline` fails the 3 : 1 border floor (2.27) and is caught. On the
        // *field fill* it reaches 3.11 — it passes the border floor, so nothing else in this
        // file stops someone reaching for it for the placeholder, which is text and needs 4.5.
        assertTrue(
            "outline clears the border floor on the field fill but is still not AA text there",
            contrast(BittrLightColors.outline, lightFieldFill) in aaLarge..aa,
        )
        // And what iOS ships on that fill today, for the record: grey2, 2.23 : 1.
        assertTrue(
            "grey2 is the placeholder colour this fix moves off — it is not AA text either",
            contrast(BittrLightColors.outlineVariant, lightFieldFill) < aa,
        )
    }

    @Test
    fun `the Swap field's dark fill cannot carry AA placeholder text — open on BIT-15`() {
        // scrim3 is blue3, and A11Y-02 demoted blue3 as a surface for precisely this reason:
        // even **pure white** on blue3 is 4.44 : 1. So no white-based token clears AA body
        // text on this fill — onSurfaceVariant reaches 3.47 and stops. The fix is to move
        // scrim3's dark value the way A11Y-02 moved `surface` (blue2 gives exactly 4.50),
        // but that is a visible dark-mode change that arrived after the BIT-15 sign-off, so
        // it is raised there rather than taken here. Asserting the shortfall is what keeps
        // it from reading as covered.
        val fill = BittrDarkColorsExtended.scrim3
        assertTrue(
            "pure white now clears AA on blue3 — the ceiling moved, re-check this whole test",
            contrast(Color.White, fill) < aa,
        )
        assertTrue(
            "the Swap dark placeholder is a known AA shortfall pending the scrim3 decision",
            contrast(BittrDarkColors.onSurfaceVariant, fill) < aa,
        )
    }

    // -----------------------------------------------------------------------
    // Tokens that are documented as failing, and why they are allowed to
    // -----------------------------------------------------------------------

    @Test
    fun `the tokens that do not clear AA are the ones the spec says are decorative`() {
        // `appversion` — 1.84 : 1. It is the build number in the corner of Settings and
        // nothing depends on reading it. Asserting the failure keeps it from being
        // quietly promoted onto something that matters.
        assertTrue(
            "footnote is decorative by design; if it is now readable, check what it is used for",
            contrast(BittrLightColorsExtended.footnote, BittrLightColors.surfaceContainer) < aaLarge,
        )
        // `unconfirmed` — 2.14 : 1, and A11Y-03 is explicit that no colour rescues it.
        // The fix is the "Pending" label beside it, which is a call-site requirement.
        assertTrue(
            "unconfirmed never passes on colour alone — it needs the Pending label (A11Y-03)",
            contrast(BittrLightColorsExtended.unconfirmed, BittrLightColors.surfaceContainer) < aaLarge,
        )
        // A11Y-14: the Question channel bar, 1.58 : 1 against the yellow fill on it.
        // DEV-42 is the fix and it is a component change, not a token change.
        assertTrue(
            "barTrack against the brand fill is a known 1.4.11 failure pending DEV-42",
            contrast(BittrLightColors.primary, BittrLightColorsExtended.barTrack) < aaLarge,
        )
    }

    // -----------------------------------------------------------------------
    // The Android design canvas — `design/screens.jsx`, artboards 01–20
    // -----------------------------------------------------------------------

    private val schemes = listOf(
        "light" to BittrLightColorsExtended,
        "dark" to BittrDarkColorsExtended,
    )

    /** The card is translucent, so its effective background is the canvas beneath it. */
    private fun card(colors: BittrColors): Color = composite(colors.cardWash, colors.canvas)

    @Test
    fun `canvas text clears AA on the canvas and on the card over it`() {
        for ((name, c) in schemes) {
            assertAtLeast(aa, c.onCanvas, c.canvas, "$name body copy on the canvas")
            assertAtLeast(aa, c.onCanvas, card(c), "$name body copy on the card")
            assertAtLeast(aa, c.mutedOnCanvas, c.canvas, "$name muted label on the canvas")
            assertAtLeast(aa, c.mutedOnCanvas, card(c), "$name muted label on the card")
        }
    }

    /**
     * The two values the mock uses that this theme does not, kept as failing
     * assertions so that "just use the mock's number" fails the build rather than
     * shipping.
     */
    @Test
    fun `the mock's muted label and its white headings are the values this theme rejects`() {
        val mockCard = card(BittrLightColorsExtended)

        // `MUTED` in screens.jsx — ink at 42 %.
        assertTrue(
            "ink at 42 % on the card is readable now? re-check before adopting it",
            contrast(Color.Black.copy(alpha = 0.42f), mockCard) < aa,
        )
        // "welcome" and "your wallet", drawn white in the mock. This is DEV-47's
        // `whiteoryellow` under another name — 16 call sites, founder sign-off, gone.
        assertTrue(
            "white on the brand card is still below the large-text floor",
            contrast(Color.White, mockCard) < aaLarge,
        )
    }

    @Test
    fun `the primary pill is visible on the canvas and carries its own label`() {
        for ((name, c) in schemes) {
            assertAtLeast(aaLarge, c.actionFill, c.canvas, "$name pill against the canvas")
            assertAtLeast(
                aa,
                c.onActionFill,
                composite(c.actionFill, c.canvas),
                "$name pill label",
            )
            // A disabled control is exempt from 1.4.3, but a label nobody can read is
            // not a design — 3 : 1 is the floor this one is held to rather than 4.5.
            assertAtLeast(
                aaLarge,
                c.onActionFill,
                composite(c.actionFillDisabled, c.canvas),
                "$name dimmed pill label",
            )
        }
    }

    /**
     * The cream cell holds a dot and, on the tonal button, a bold-16 label — both
     * large-text or non-text. Dark's white-on-blue3 is 4.44 : 1 and would miss AA for
     * body copy, which is why nothing on this fill is body copy.
     */
    @Test
    fun `the tonal fill shows what is on it at the large-text floor`() {
        for ((name, c) in schemes) {
            assertAtLeast(aaLarge, c.onTonalFill, c.tonalFill, "$name content on the tonal fill")
        }
    }

    // -----------------------------------------------------------------------
    // Structural
    // -----------------------------------------------------------------------

    @Test
    fun `both schemes define every slot the app reads`() {
        for ((name, scheme) in listOf("light" to BittrLightColors, "dark" to BittrDarkColors)) {
            for ((slot, color) in scheme.readSlots()) {
                assertTrue("$name.$slot is fully transparent", color.alpha > 0f)
            }
        }
    }

    private fun ColorScheme.readSlots(): List<Pair<String, Color>> = listOf(
        "primary" to primary, "onPrimary" to onPrimary,
        "primaryContainer" to primaryContainer, "onPrimaryContainer" to onPrimaryContainer,
        "surface" to surface, "onSurface" to onSurface,
        "surfaceContainer" to surfaceContainer, "surfaceContainerHigh" to surfaceContainerHigh,
        "surfaceBright" to surfaceBright, "onSurfaceVariant" to onSurfaceVariant,
        "outline" to outline, "outlineVariant" to outlineVariant,
        "error" to error, "onError" to onError, "scrim" to scrim,
    )

    /** `Color.toArgb()` needs `android.graphics`; this does not. */
    private fun Color.toArgbInt(): Int {
        fun ch(v: Float) = (v * 255f + 0.5f).toInt() and 0xFF
        return (ch(alpha) shl 24) or (ch(red) shl 16) or (ch(green) shl 8) or ch(blue)
    }
}
