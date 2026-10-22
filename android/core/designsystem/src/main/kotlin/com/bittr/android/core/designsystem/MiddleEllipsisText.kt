package com.bittr.android.core.designsystem

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints

/**
 * Text over [maxLines] lines that gives way in the middle of its last line — UIKit's
 * `.byTruncatingMiddle` on a multi-line label — so an invoice or address keeps its end, which is
 * what a user checks it by. Compose's [TextOverflow.MiddleEllipsis] covers one line only.
 *
 * The lines before the last are kept whole; the last holds as much of what follows them as fits,
 * then "…", then as much of the string's end.
 *
 * What the screen shows is shortened; what it says is not: the node's text is [readAs], the whole
 * string unless a caller says otherwise, as a truncated UILabel's is, so the flows' `copyTextFrom`
 * and text assertions read it all.
 * [modifier] goes on that node, so a test tag there names it.
 */
@Composable
fun MiddleEllipsisText(
    text: String,
    style: TextStyle,
    maxLines: Int,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    textAlign: TextAlign? = null,
    readAs: String = text,
) {
    BoxWithConstraints(modifier.clearAndSetSemantics { this.text = AnnotatedString(readAs) }) {
        val measurer = rememberTextMeasurer()
        val width = constraints.maxWidth
        val shown = remember(text, style, maxLines, width) {
            middleEllipsized(measurer, text, style, maxLines, width)
        }
        Text(
            shown,
            style = style,
            color = color,
            textAlign = textAlign,
            maxLines = maxLines,
            overflow = TextOverflow.Clip,
        )
    }
}

/** [text] as it fits [maxLines] lines of [width] px, shortened in the middle of the last line. */
private fun middleEllipsized(measurer: TextMeasurer, text: String, style: TextStyle, maxLines: Int, width: Int): String {
    if (width == Constraints.Infinity || maxLines < 1) return text
    val constraints = Constraints(maxWidth = width)
    fun measure(candidate: String) = measurer.measure(candidate, style, maxLines = maxLines, constraints = constraints)
    val full = measure(text)
    if (!full.multiParagraph.didExceedMaxLines) return text

    // Everything up to the last line stays as it is.
    val lastLineStart = if (maxLines > 1) full.getLineEnd(maxLines - 2) else 0
    // [kept] characters around the ellipsis on the last line: the extra one, if odd, before it.
    fun candidate(kept: Int) =
        text.substring(0, lastLineStart + (kept + 1) / 2) + ELLIPSIS + text.substring(text.length - kept / 2)

    var lo = 0
    var hi = text.length - lastLineStart
    while (lo < hi) {
        val mid = (lo + hi + 1) / 2
        if (measure(candidate(mid)).multiParagraph.didExceedMaxLines) hi = mid - 1 else lo = mid
    }
    return candidate(lo)
}

private const val ELLIPSIS = "…"
