package com.bittr.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.res.ResourcesCompat
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.BittrLightColors
import com.bittr.android.core.designsystem.BittrLightColorsExtended
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The design half of `shared/docs/swap-live-activity-spec.md` §6 — the decisions BIT-115 made
 * about how the swap Live Update *looks*, as opposed to [SwapLiveUpdateContractTest], which pins
 * how it is *built*.
 *
 * §6 item 5 said the colorized treatment "wants a real device". It turns out it does not, and
 * that is most of why this file exists. Three framework entry points are public, and between
 * them they decide the entire rendered appearance off-device:
 *
 *  - `Notification.Colors#resolvePalette(context, rawColor, colorized, nightMode)` — the exact
 *    background and text colours the platform will draw, for a given requested colour.
 *  - `Notification.ProgressStyle#sanitizeProgressColor(segment, background, default)` — the
 *    platform rewrites segment colours that do not clear its own contrast floor, so the colour
 *    a segment is *declared* as is not necessarily the colour it renders as.
 *  - The drawables themselves, rasterised.
 *
 * Both of the first two are `@hide`, so they are reached by reflection and the failure messages
 * say so: if a future platform release moves them, this file should be re-derived rather than
 * deleted — the decisions it guards do not stop being true, they stop being *checked*.
 *
 * Nothing here needs the Live Update to exist. It is about the palette and the assets, both of
 * which are decidable before Phase 4 item 12 is built.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SwapLiveUpdatePresentationTest {

    private companion object {
        /** The one tint, for all five phases. Spec §6.5. */
        val TINT = BittrLightColorsExtended.canvas.toArgb()

        /** Segment colour for the three in-flight phases. Spec §4.3. */
        val INK = BittrLightColorsExtended.actionFill.toArgb()

        /** Terminal segment colours. Spec §4.3. */
        val GREEN = BittrLightColorsExtended.profit.toArgb()
        val RED = BittrLightColors.error.toArgb()

        val ICONS = listOf(
            "ic_stat_swap_preparing",
            "ic_stat_swap_confirming",
            "ic_stat_swap_completing",
            "ic_stat_swap_complete",
            "ic_stat_swap_failed",
        )

        /** The three glyphs whose meaning is carried by a knocked-out interior. */
        val DISCS = listOf(
            "ic_stat_swap_confirming",
            "ic_stat_swap_complete",
            "ic_stat_swap_failed",
        )
    }

    // -----------------------------------------------------------------------
    // The tint — spec §6.5
    // -----------------------------------------------------------------------

    private class Palette(ctx: Context, rawColor: Int, nightMode: Boolean) {
        private val cls = Class.forName("android.app.Notification\$Colors")
        private val instance = cls.getDeclaredConstructor().newInstance()

        init {
            cls.getMethod(
                "resolvePalette",
                Context::class.java,
                Int::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
            ).invoke(instance, ctx, rawColor, /* colorized = */ true, nightMode)
        }

        private fun get(name: String) = cls.getMethod(name).invoke(instance) as Int

        val background get() = get("getBackgroundColor")
        val primaryText get() = get("getPrimaryTextColor")
        val secondaryText get() = get("getSecondaryTextColor")
    }

    /**
     * BIT-94 and BIT-95 both turned on a token that was checked in one scheme and broken in the
     * other, so the standing rule on this board is to check both. Here the answer is that there
     * is only one: a colorized notification's palette is derived from the requested colour alone
     * and does not consult the night-mode flag at all.
     *
     * That is worth pinning rather than just knowing, because it is the reason the rest of this
     * file gets away with a single set of numbers, and the reason the surface needs no dark
     * variant of the tint.
     */
    @Test
    @Config(sdk = [36])
    fun `the colorized palette is the same in both schemes`() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val light = Palette(ctx, TINT, nightMode = false)
        val dark = Palette(ctx, TINT, nightMode = true)

        assertEquals("background differs by scheme", light.background, dark.background)
        assertEquals("primary text differs by scheme", light.primaryText, dark.primaryText)
        assertEquals("secondary text differs by scheme", light.secondaryText, dark.secondaryText)
    }

    /**
     * The brand colour survives as the background byte-for-byte — the platform does not lighten
     * or darken a colorized background to suit itself — and the text it then picks clears AA on
     * it comfortably.
     *
     * The background being opaque is the other half of the §6.5 answer: a lock-screen render of
     * this surface does not composite the user's wallpaper, so "does it read over a wallpaper"
     * is not a contrast question about this notification at all.
     */
    @Test
    @Config(sdk = [36])
    fun `the brand tint renders as itself and carries its text`() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val palette = Palette(ctx, TINT, nightMode = false)

        assertEquals(
            "the platform moved the colorized background off the brand token",
            TINT,
            palette.background,
        )
        val ratio = contrast(palette.primaryText, palette.background)
        assertTrue(
            "primary text on the tint is $ratio : 1, below the 4.5 : 1 body-text floor",
            ratio >= 4.5,
        )
        assertTrue(
            "secondary text on the tint is below 4.5 : 1",
            contrast(palette.secondaryText, palette.background) >= 4.5,
        )
    }

    // -----------------------------------------------------------------------
    // The progress bar — spec §4.3
    // -----------------------------------------------------------------------

    private fun sanitize(segment: Int, background: Int): Int =
        Class.forName("android.app.Notification\$ProgressStyle")
            .getMethod(
                "sanitizeProgressColor",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
            )
            .invoke(null, segment, background, 0) as Int

    /**
     * Why the in-flight segments are ink and not the brand colour.
     *
     * The platform rewrites any segment that does not clear 3 : 1 against the background, so a
     * segment declared in the brand colour — which is also the background — does not render in
     * the brand colour. It renders as whatever the rewrite lands on, which is a dark olive that
     * appears in no design token. Ink is the one choice that comes back unmodified.
     *
     * This is the trap in the shape of §3.2's: nothing fails, and the bar is simply not the
     * colour the code says it is.
     */
    @Test
    @Config(sdk = [36])
    fun `in-flight segments must be ink because the brand colour does not survive`() {
        assertEquals(
            "ink no longer passes through the platform's segment rewrite unmodified",
            INK,
            sanitize(INK, TINT),
        )
        assertNotEquals(
            "the brand colour now survives as a segment on the brand background — if that is " +
                "real, §4.3 can be simplified; until then do not declare a segment in it",
            TINT,
            sanitize(TINT, TINT),
        )
    }

    /**
     * The two terminal phases are the only place colour does any work, and what they render as
     * is not the token — the platform pulls both to its 3 : 1 floor against the tint. So the
     * bar says "finished, and this is how it finished" in a green and a red that are recognisably
     * the brand's without being equal to it. Recorded here so nobody re-derives the tokens from a
     * screenshot and concludes they have drifted.
     */
    @Test
    @Config(sdk = [36])
    fun `terminal segments are pulled to the platform contrast floor`() {
        for ((name, token) in listOf("profit green" to GREEN, "error red" to RED)) {
            val rendered = sanitize(token, TINT)
            assertNotEquals("$name unexpectedly survived unmodified", token, rendered)
            val ratio = contrast(rendered, TINT)
            assertTrue(
                "$name renders at $ratio : 1 against the tint, under the 3 : 1 non-text floor",
                ratio >= 2.99,
            )
        }
    }

    // -----------------------------------------------------------------------
    // The icons — spec §6.3
    // -----------------------------------------------------------------------

    /**
     * Material Symbols are authored on a y-up grid, so each of these drawables carries a group
     * that translates the path back into the viewport. Drop that group — the obvious tidy-up when
     * re-syncing a glyph from upstream — and the icon renders entirely outside its own bounds:
     * no crash, no warning, just a blank space in the status bar where the small icon was.
     *
     * So this asserts the glyph is actually *in* the frame, and that the three disc glyphs still
     * have their interior knocked out. The cut-out is the whole meaning of those three — a
     * `check_circle` whose check has filled in is an indistinguishable solid disc, and that is
     * what a wrong fill rule produces.
     */
    @Test
    @Config(sdk = [34])
    fun `every phase icon renders as a silhouette inside its own bounds`() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        for (name in ICONS) {
            val mask = rasterise(ctx, name)
            val ink = mask.sumOf { row -> row.count { it } }
            val coverage = 100.0 * ink / (SIZE * SIZE)
            assertTrue(
                "$name rendered $coverage% ink — a glyph translated out of its own viewport " +
                    "renders blank, which is silent in the status bar",
                coverage in 10.0..70.0,
            )
            val rows = mask.indices.filter { y -> mask[y].any { it } }
            val cols = (0 until SIZE).filter { x -> mask.any { it[x] } }
            assertTrue(
                "$name occupies rows ${rows.first()}..${rows.last()} — not vertically centred",
                rows.first() <= 4 && rows.last() >= SIZE - 5,
            )
            assertTrue(
                "$name occupies columns ${cols.first()}..${cols.last()} — not horizontally centred",
                cols.first() <= 6 && cols.last() >= SIZE - 7,
            )
        }
    }

    @Test
    @Config(sdk = [34])
    fun `the disc glyphs keep their knocked-out interior`() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        for (name in DISCS) {
            val mask = rasterise(ctx, name)
            // Transparent pixels that are enclosed by ink on all four sides. A solid disc has
            // none; a disc with a glyph knocked out of it has a cluster of them.
            var enclosed = 0
            for (y in 1 until SIZE - 1) {
                for (x in 1 until SIZE - 1) {
                    if (mask[y][x]) continue
                    val left = (0 until x).any { mask[y][it] }
                    val right = (x + 1 until SIZE).any { mask[y][it] }
                    val up = (0 until y).any { mask[it][x] }
                    val down = (y + 1 until SIZE).any { mask[it][x] }
                    if (left && right && up && down) enclosed++
                }
            }
            assertTrue(
                "$name has only $enclosed enclosed transparent pixels — its interior has filled " +
                    "in, so it now reads as a plain disc",
                enclosed >= 20,
            )
        }
    }

    // -----------------------------------------------------------------------

    private fun rasterise(ctx: Context, name: String): Array<BooleanArray> {
        val id = ctx.resources.getIdentifier(name, "drawable", ctx.packageName)
        assertTrue("no drawable named $name", id != 0)
        val drawable = ResourcesCompat.getDrawable(ctx.resources, id, null)!!
        val bitmap = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, SIZE, SIZE)
        drawable.draw(Canvas(bitmap))
        return Array(SIZE) { y ->
            BooleanArray(SIZE) { x -> (bitmap.getPixel(x, y) ushr 24) and 0xFF > 128 }
        }
    }

    /** WCAG 2.x relative luminance, rounded to two places so failure messages read as ratios. */
    private fun contrast(a: Int, b: Int): Double {
        fun luminance(color: Int): Double {
            fun channel(shift: Int): Double {
                val v = ((color shr shift) and 0xFF) / 255.0
                return if (v <= 0.03928) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        val (hi, lo) = listOf(luminance(a), luminance(b)).sortedDescending()
        return Math.round((hi + 0.05) / (lo + 0.05) * 100.0) / 100.0
    }
}

private const val SIZE = 30
