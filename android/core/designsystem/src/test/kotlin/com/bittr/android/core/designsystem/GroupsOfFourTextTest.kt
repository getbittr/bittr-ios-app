package com.bittr.android.core.designsystem

import android.content.Context
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Measured with the platform's own text layout, so the widths are the ones a phone gets. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GroupsOfFourTextTest {

    private val measurer = TextMeasurer(
        createFontFamilyResolver(ApplicationProvider.getApplicationContext<Context>()),
        Density(1f),
        LayoutDirection.Ltr,
    )
    private val style = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 16.sp, lineHeight = 18.sp)
    private val invoice = "lnbcrt1500n1pn7xyz0pp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5" +
        "xysxxatsyp3k7enxv4jsxqzpusp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygs9qrsgq" +
        "357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7" +
        "mlcwspyetp5h2tztugp9lfyql"
    private val characterWidth = measurer.measure("0".repeat(40), style, softWrap = false).getLineRight(0) / 40

    @Test
    fun `a shortened invoice keeps three lines, both its ends and its columns, at every width`() {
        for (width in 100..420 step 3) {
            val shown = shortenedInGroups(measurer, inGroupsOfFour(invoice), style, 16f, maxLines = 3, width = width)
            val layout = measurer.measure(shown, style, constraints = Constraints(maxWidth = width))
            val text = shown.text

            assertTrue("Three lines at most at $width px", layout.lineCount <= 3)
            val ellipsis = text.indexOf('…')
            assertTrue("Shortened at $width px", ellipsis > 0)
            assertTrue("The start is the invoice's start at $width px", invoice.startsWith(text.substring(0, ellipsis).filter(Char::isLetterOrDigit)))
            val end = text.substring(ellipsis).filter(Char::isLetterOrDigit)
            assertTrue("The end is the invoice's end at $width px", end.isEmpty() || invoice.endsWith(end))

            assertEquals("The ellipsis line ends where a full line does at $width px", layout.getLineRight(0), layout.getLineRight(layout.lineCount - 1), 0.5f)
            val slotStart = layout.getHorizontalPosition(ellipsis - 1, usePrimaryDirection = true)
            val box = layout.getBoundingBox(ellipsis)
            assertEquals("The ellipsis sits in the middle of its slot at $width px", slotStart + 2 * characterWidth, (box.left + box.right) / 2, 0.5f)
        }
    }

    @Test
    fun `narrowed to its longest line for the trailing edge, the text wraps exactly as before`() {
        val address = inGroupsOfFour("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297")
        for (width in 100..420 step 3) {
            for (shown in listOf(shortenedInGroups(measurer, address, style, 16f, Int.MAX_VALUE, width), shortenedInGroups(measurer, inGroupsOfFour(invoice), style, 16f, 3, width))) {
                val full = measurer.measure(shown, style, constraints = Constraints(maxWidth = width))
                val narrowed = measurer.measure(shown, style, constraints = Constraints(maxWidth = longestLine(measurer, shown, style, width)))
                assertEquals("Lines at $width px", full.lineCount, narrowed.lineCount)
                for (line in 0 until full.lineCount) assertEquals("Line ${line + 1} at $width px", full.getLineEnd(line), narrowed.getLineEnd(line))
            }
        }
    }

    @Test
    fun `text that fits is left as it is`() {
        val address = inGroupsOfFour("bcrt1ql0pkt3du7900avnxcjusmcjgm3fvvtkzm2u6nw")
        assertEquals(address, shortenedInGroups(measurer, address, style, 16f, maxLines = 3, width = 300).text)
    }
}
