package com.bittr.android.core.designsystem

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.LocalTextStyle
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

/**
 * Text [shorten]ed to fit its width, measured in the style `Text` draws it in. What the screen shows
 * is shortened; what it says is [readAs], so TalkBack and the flows' text assertions and
 * `copyTextFrom` read the string whole. [modifier] goes on that node, so a test tag there names it.
 *
 * [shorten] is remembered by the measurer, style, [maxLines], width and [keys].
 */
@Composable
internal fun ShortenedText(
    readAs: String,
    style: TextStyle,
    maxLines: Int,
    modifier: Modifier,
    color: Color,
    vararg keys: Any?,
    textAlign: TextAlign? = null,
    shorten: (measurer: TextMeasurer, style: TextStyle, width: Int) -> AnnotatedString,
) {
    BoxWithConstraints(modifier.clearAndSetSemantics { text = AnnotatedString(readAs) }) {
        val measurer = rememberTextMeasurer()
        val resolved = LocalTextStyle.current.merge(style)
        val width = constraints.maxWidth
        val shown = remember(measurer, resolved, maxLines, width, *keys) { shorten(measurer, resolved, width) }
        Text(
            shown,
            style = resolved,
            color = color,
            textAlign = textAlign,
            maxLines = maxLines,
            overflow = TextOverflow.Clip,
        )
    }
}
