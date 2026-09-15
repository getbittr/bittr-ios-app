package com.bittr.android.feature.map

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog

/**
 * The one-place sheet with its name at the size the storyboard picked.
 *
 * `placeNameLabel` is Gilroy-Bold **22** (`33m-oo-gb6`, `Main.storyboard:2805`) and
 * BIT-152 moved it there from `titleMedium`'s 18. The question that move raises is
 * whether the sheet still holds together four sp larger, and it is a real question
 * rather than a formality: the name shares a `Row` with a 48 dp close button, takes
 * `weight(1f)` of what is left, and wraps for as many lines as it needs — iOS caps
 * it at two with `numberOfLines="2"` and tail truncation, so a long name grows this
 * sheet where it would not grow iOS's.
 *
 * ### What this asserts, and why that and not the obvious thing
 *
 * The gate is **every id `bitcoin_map.yaml` taps on this sheet is still displayed**.
 * The flow taps `websiteButton` and `goToMapsButton`, both below the name, and a
 * sheet that grew past the screen puts them out of reach while still looking correct
 * in a screenshot. `assertIsDisplayed` is bounds-aware, so it sees that. Proved
 * discriminating rather than assumed: a name repeated out to 24 lines fails this
 * with `map.onePlace.websiteButton is not displayed`.
 *
 * The obvious assertion — widest rendered line against the width the name was given
 * — is **deliberately absent, because it cannot fail.** Compose's line breaker falls
 * back to breaking inside a word rather than letting a line exceed its constraint:
 * `Donaudampfschiffahrtsgesellschaftskapitaen`, one unbreakable 42-character token,
 * comes back as three lines at 230.6 dp of 232 dp available. No string makes that
 * comparison true, so asserting it would be decoration. The line counts are printed
 * instead, as the measurement of how much the sheet grew.
 *
 * Measured under `@GraphicsMode(NATIVE)`: Robolectric's default `LEGACY` mode has no
 * font rasterisation and reports about one pixel per character, which makes any
 * text-fit answer fiction. [assumeNativeTextMetrics] reports *skipped* rather than
 * green where that is what is happening.
 *
 * PNGs land in `feature/map/build/screenshots/`; they are evidence for a human and
 * the assertions are what fails the build. Two things the capture is not: there is
 * no scrim, because a dialog's dim is a window attribute rather than drawn content,
 * and there is no map behind the sheet, because only the sheet is composed here.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class OnePlaceNameFitTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun `the sheet holds a short name on a 411 dp screen`() =
        assertSheetHolds("411dp-short", SHORT_NAME)

    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun `the sheet holds a long name on a 411 dp screen`() =
        assertSheetHolds("411dp-long", LONG_NAME)

    @Test
    @Config(qualifiers = "w320dp-h568dp-320dpi")
    fun `the sheet holds a short name on a 320 dp screen`() =
        assertSheetHolds("320dp-short", SHORT_NAME)

    /**
     * The worst case the port actually has to survive: the narrowest supported screen
     * and a name long enough to wrap, on the shortest sheet.
     */
    @Test
    @Config(qualifiers = "w320dp-h568dp-320dpi")
    fun `the sheet holds a long name on a 320 dp screen`() =
        assertSheetHolds("320dp-long", LONG_NAME)

    /**
     * One unbreakable token, on the narrow screen. Swiss and German place names do
     * this, and at Bold 22 a compound is where the extra four sp is felt hardest.
     */
    @Test
    @Config(qualifiers = "w320dp-h568dp-320dpi")
    fun `the sheet holds a single long compound word on a 320 dp screen`() =
        assertSheetHolds("320dp-compound", COMPOUND_NAME)

    private fun assertSheetHolds(label: String, name: String) {
        composeRule.setContent {
            BittrTheme {
                OnePlaceSheet(place = place(name), onClose = {}, onOpenWebsite = {})
            }
        }
        composeRule.waitForIdle()

        val nameNode = composeRule.onNodeWithTag(TestID.Map.OnePlace.nameLabel)
        val layout = nameNode.layout()
        assumeNativeTextMetrics(layout, name)

        assertEquals(
            "The sheet is showing a different name than it was given.",
            name,
            layout.layoutInput.text.text,
        )

        val density = composeRule.density.density
        val widestLineDp = (0 until layout.lineCount)
            .maxOf { layout.getLineRight(it) - layout.getLineLeft(it) } / density
        println(
            "ONE PLACE $label: lines=${layout.lineCount} " +
                "widest=${"%.1f".format(widestLineDp)}dp " +
                "of ${"%.1f".format(nameNode.fetchSemanticsNode().size.width / density)}dp given",
        )

        listOf(
            TestID.Map.OnePlace.nameLabel,
            TestID.Map.OnePlace.closeButton,
            TestID.Map.OnePlace.websiteButton,
            TestID.Map.OnePlace.goToMapsButton,
        ).forEach { tag ->
            composeRule.onNodeWithTag(tag).assertIsDisplayed()
        }

        capture(label)
    }

    /**
     * Skips rather than passes when the text metrics are Robolectric's stubs. Real
     * Gilroy-Bold 22 is ~10–20 px per character; `LEGACY` returns ~1.
     *
     * Per *rendered line*, not per whole string: a wrapped name puts only part of its
     * characters on the widest line, so dividing by the full length would undercount
     * and could skip a run that is measuring real glyphs.
     */
    private fun assumeNativeTextMetrics(layout: TextLayoutResult, text: String) {
        val widest = (0 until layout.lineCount)
            .maxOf { layout.getLineRight(it) - layout.getLineLeft(it) }
        val charsOnWidestLine = (0 until layout.lineCount)
            .maxOf { layout.getLineEnd(it, visibleEnd = true) - layout.getLineStart(it) }
        val pxPerChar = widest / charsOnWidestLine.coerceAtLeast(1)
        assumeTrue(
            "Text metrics look like Robolectric's LEGACY stubs " +
                "(${"%.1f".format(pxPerChar)} px/char for \"$text\") — native graphics is " +
                "unavailable on this host, so a text-fit answer here would be fiction. " +
                "Skipping instead of reporting green.",
            pxPerChar > 3f,
        )
    }

    /**
     * Evidence for a human. Never the reason this test is red.
     *
     * The sheet is a `Dialog`, so its window's decor view is what holds the pixels —
     * and with `usePlatformDefaultWidth = false` that decor is the full screen, so it
     * needs no compositing onto anything. Capturing Compose roots instead does not
     * work here: the host activity contributes a **0 × 0** root alongside the
     * dialog's, and `captureToImage` on it throws `width and height must be > 0`
     * before any "pick the biggest root" step gets to run.
     */
    private fun capture(label: String) {
        val outputDir = System.getProperty("bittr.screenshot.dir") ?: return
        runCatching {
            val decor = ShadowDialog.getLatestDialog()
                ?.takeIf { it.isShowing }
                ?.window
                ?.decorView
                ?.takeIf { it.width > 0 && it.height > 0 }
                ?: error("No dialog decor view to capture")

            val bitmap = Bitmap.createBitmap(decor.width, decor.height, Bitmap.Config.ARGB_8888)
            decor.draw(Canvas(bitmap))

            val file = File(outputDir).apply { mkdirs() }.resolve("one-place-$label.png")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            println(
                "ONE PLACE screenshot ($label): ${file.absolutePath} " +
                    "(${bitmap.width}x${bitmap.height})",
            )
        }.onFailure { println("ONE PLACE screenshot ($label) unavailable: $it") }
    }

    private fun SemanticsNodeInteraction.layout(): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(results)
        return results.first()
    }

    /**
     * A place with every optional row filled, so the sheet is at its tallest and the
     * two buttons below the name are as far down as they ever get.
     */
    private fun place(name: String) = BitcoinPlace(
        id = 1,
        lat = 46.9480,
        lon = 7.4474,
        icon = "local_cafe",
        name = name,
        address = "Bahnhofstrasse 1, 8001 Zürich",
        updatedAt = null,
        deletedAt = null,
        website = "https://www.example.com/",
        openingHours = "Mo-Fr 08:00-18:00, Sa 09:00-17:00",
    )

    private companion object {
        /** A name from the flow's own fixtures. */
        const val SHORT_NAME = "Café Satoshi"

        /**
         * Names come from OpenStreetMap, where this length is unremarkable. iOS
         * truncates it after two lines; Android wraps, so this is the case that
         * decides whether the sheet grows past the screen.
         */
        const val LONG_NAME = "Restaurant Zum Goldenen Löwen am Bundesplatz"

        /** 42 characters with nowhere to break. */
        const val COMPOUND_NAME = "Donaudampfschiffahrtsgesellschaftskapitaen"
    }
}
