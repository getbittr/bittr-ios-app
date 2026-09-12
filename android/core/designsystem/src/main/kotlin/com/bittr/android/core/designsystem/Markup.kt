package com.bittr.android.core.designsystem

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight

/**
 * Renders the `<b>` / `<br>` markup the shared copy carries.
 *
 * `shared/strings/` stores markup in the iOS convention on purpose — the README is
 * explicit that `<b>` and `<br>` are the storage format and that the eventual
 * generator maps `<br>` to a newline for `strings.xml`. That generator does not
 * exist yet, and the Academy content and the BTCMap alert both ship the raw form
 * today, so something has to interpret it. This is that something, and it is
 * deliberately the same two tags and nothing more: the strings use `<b>` and `<br>`
 * and a general HTML path (`Html.fromHtml`) would quietly start honouring anything
 * a future string happened to contain.
 *
 * Unrecognised angle brackets are left as literal text rather than swallowed — a
 * string containing `Settings > Apps > Bittr` (`locationunavailable`) must survive
 * this intact.
 */
fun bittrMarkup(text: String): AnnotatedString = buildAnnotatedString {
    var index = 0
    var boldDepth = 0

    fun appendPlain(value: String) {
        if (value.isEmpty()) return
        if (boldDepth > 0) {
            withStyleBold { append(value) }
        } else {
            append(value)
        }
    }

    while (index < text.length) {
        val tagStart = text.indexOf('<', index)
        if (tagStart < 0) {
            appendPlain(text.substring(index))
            break
        }

        appendPlain(text.substring(index, tagStart))

        val tag = TAGS.firstOrNull { text.startsWith(it.markup, tagStart) }
        if (tag == null) {
            // Not one of ours — a literal `<`, as in "Settings > Apps".
            appendPlain("<")
            index = tagStart + 1
            continue
        }

        when (tag) {
            Tag.BOLD_OPEN -> boldDepth++
            Tag.BOLD_CLOSE -> if (boldDepth > 0) boldDepth--
            Tag.BREAK -> append('\n')
        }
        index = tagStart + tag.markup.length
    }
}

private enum class Tag(val markup: String) {
    BOLD_OPEN("<b>"),
    BOLD_CLOSE("</b>"),

    /**
     * iOS renders one `<br>` as one line break, so a `<br><br>` paragraph gap is two
     * newlines. Kept literal rather than collapsed — the alert copy's paragraph
     * spacing is what its length budget was measured against.
     */
    BREAK("<br>"),
}

/** Longest first, so `</b>` is not mistaken for an unknown tag after `<b>` misses. */
private val TAGS = listOf(Tag.BOLD_CLOSE, Tag.BOLD_OPEN, Tag.BREAK)

private inline fun AnnotatedString.Builder.withStyleBold(block: () -> Unit) {
    val start = length
    block()
    addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length)
}
