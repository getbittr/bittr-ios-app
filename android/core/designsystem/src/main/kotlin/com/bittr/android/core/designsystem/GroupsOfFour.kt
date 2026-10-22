package com.bittr.android.core.designsystem

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.em
import kotlin.math.ceil

/**
 * [text] in groups of four characters, a space between them — iOS's `String.inGroupsOfFour()` — as
 * wallets show an address or invoice, so it can be checked group by group.
 */
fun inGroupsOfFour(text: String): String = text.chunked(4).joinToString(" ")

/**
 * Text already in groups of four ([inGroupsOfFour]), in a monospaced [style] so the groups line up
 * in columns, over at most [maxLines] lines — iOS's `String.inGroupsOfFour(width:lines:font:color:)`.
 *
 * Text that needs more lines is shortened between whole groups: the last line keeps groups from
 * both ends, with "…" centred in the slot of the groups in between, so every group after it stays
 * in its column. The tail is grouped from the end, so its last group is never cut short.
 *
 * With [trailing], the text is as wide as its longest line, so a parent aligning it to its end puts
 * that line against the edge while the lines stay left-aligned in their columns.
 *
 * What the screen shows is grouped; what it says is [readAs], so TalkBack and the flows' text
 * assertions and `copyTextFrom` read the string whole. [modifier] goes on that node, so a test tag
 * there names it.
 */
@Composable
fun GroupsOfFourText(
    text: String,
    readAs: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
    trailing: Boolean = false,
) {
    BoxWithConstraints(modifier.clearAndSetSemantics { this.text = AnnotatedString(readAs) }) {
        val measurer = rememberTextMeasurer()
        val fontSizePx = with(LocalDensity.current) { style.fontSize.toPx() }
        val width = constraints.maxWidth
        val shown = remember(measurer, text, style, fontSizePx, maxLines, width) {
            shortenedInGroups(measurer, text, style, fontSizePx, maxLines, width)
        }
        val longestLine = remember(measurer, shown, style, width, trailing) {
            if (trailing && width != Constraints.Infinity) longestLine(measurer, shown, style, width) else null
        }
        Text(
            shown,
            style = style,
            color = color,
            maxLines = maxLines,
            overflow = TextOverflow.Clip,
            modifier = if (longestLine != null) Modifier.width(with(LocalDensity.current) { longestLine.toDp() }) else Modifier,
        )
    }
}

/**
 * [text] as it fits [maxLines] lines of [width] px, shortened between whole groups if it does not.
 *
 * The slot for the ellipsis is measured to be exactly as wide as a group, and the result is measured
 * again, a group fewer at the start each time, until it fits, so no line ever wraps out of sight.
 */
internal fun shortenedInGroups(
    measurer: TextMeasurer,
    text: String,
    style: TextStyle,
    fontSizePx: Float,
    maxLines: Int,
    width: Int,
): AnnotatedString {
    if (width == Constraints.Infinity) return AnnotatedString(text)
    val constraints = Constraints(maxWidth = width)
    val layout = measurer.measure(text, style, constraints = constraints)
    if (layout.lineCount <= maxLines) return AnnotatedString(text)

    // As many groups as the first line holds, which every full line does: each group is as wide as the next.
    val groupsPerLine = text.substring(0, layout.getLineEnd(0)).trim().split(' ').size
    val tailCount = (groupsPerLine - 1) / 2
    val groups = text.split(' ')
    val tail = if (tailCount == 0) emptyList() else inGroupsOfFour(text.replace(" ", "").takeLast(tailCount * 4)).split(' ')

    // The two spaces either side of the ellipsis widen equally until the slot is four characters wide.
    fun right(run: String) = measurer.measure(run, style, softWrap = false).getLineRight(0)
    // Measured between two visible characters, so a space at the end of the line still counts.
    fun advance(run: String) = (right("0" + run.repeat(MEASURED_RUN) + "0") - right("00")) / MEASURED_RUN
    val spacingPx = (4 * advance("0") - advance(ELLIPSIS) - 2 * advance(NO_BREAK_SPACE)) / 2
    val slotSpacing = (spacingPx / fontSizePx).em

    fun arranged(headCount: Int) = buildAnnotatedString {
        (groups.take(headCount) + ELLIPSIS_SLOT + tail).forEachIndexed { index, group ->
            if (index > 0) append(if (index % groupsPerLine == 0) "\n" else " ")
            if (group == ELLIPSIS_SLOT) {
                withStyle(SpanStyle(letterSpacing = slotSpacing)) { append(NO_BREAK_SPACE) }
                append(ELLIPSIS)
                withStyle(SpanStyle(letterSpacing = slotSpacing)) { append(NO_BREAK_SPACE) }
            } else {
                append(group)
            }
        }
    }
    fun fits(candidate: AnnotatedString) = measurer.measure(candidate, style, constraints = constraints).lineCount <= maxLines

    var headCount = groupsPerLine * maxLines - 1 - tailCount
    while (headCount > 0 && !fits(arranged(headCount))) headCount--
    return arranged(headCount)
}

/** The widest of [shown]'s lines at [width] px, rounded up to whole pixels so none of them wraps again. */
internal fun longestLine(measurer: TextMeasurer, shown: AnnotatedString, style: TextStyle, width: Int): Int {
    val layout = measurer.measure(shown, style, constraints = Constraints(maxWidth = width))
    return ceil((0 until layout.lineCount).maxOf { layout.getLineRight(it) }).toInt()
}

/** Characters measured together, so one character's width comes out to a fraction of a pixel. */
private const val MEASURED_RUN = 20

private const val ELLIPSIS = "…"
private const val ELLIPSIS_SLOT = "\u0000"
private const val NO_BREAK_SPACE = " "
