package com.bittr.android.core.designsystem

/**
 * Rewrites SVG path data so that every parser reads it the same way.
 *
 * The icon paths in this app are hand-written or copied from the design canvas, which writes
 * arcs the way SVG minifiers do: an arc's two flags run into the next number with no separator,
 * so `a3.1 3.1 0 010 6.2` means large-arc `0`, sweep `1`, then `0 6.2`. The SVG grammar allows
 * that, but Android's parsers do not agree on it — `androidx.core.graphics.PathParser` threw
 * on the map pin's bitcoin glyph and took the app down when the map opened (2026-09-18), and
 * Compose's parser drew the old moon and sun as a sliver and a ring of loose rays.
 *
 * So every path goes through here before it is parsed: commands and numbers come out separated
 * by single spaces, with an arc's two flags split off as the single characters they are.
 * Anything already well-formed comes out equivalent.
 */
fun normalizeSvgPath(pathData: String): String {
    val out = StringBuilder(pathData.length + 16)
    var index = 0
    var command = ' '
    var argument = 0

    fun skipSeparators() {
        while (index < pathData.length && (pathData[index].isWhitespace() || pathData[index] == ',')) index++
    }

    while (true) {
        skipSeparators()
        if (index >= pathData.length) break
        val c = pathData[index]
        if (c.isLetter() && c != 'e' && c != 'E') {
            command = c
            argument = 0
            out.append(c).append(' ')
            index++
            continue
        }
        val isArc = command == 'a' || command == 'A'
        val slot = argument % ARC_ARGUMENTS
        if (isArc && (slot == LARGE_ARC_FLAG || slot == SWEEP_FLAG)) {
            // A flag is exactly one character, 0 or 1, whatever follows it.
            out.append(c).append(' ')
            index++
        } else {
            val end = numberEnd(pathData, index)
            require(end > index) { "Not a number at $index in \"$pathData\"" }
            out.append(pathData, index, end).append(' ')
            index = end
        }
        argument++
    }
    return out.toString().trimEnd()
}

/** The end of the number starting at [start]: sign, digits, one point, exponent. */
private fun numberEnd(s: String, start: Int): Int {
    var i = start
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++
    var sawPoint = false
    while (i < s.length) {
        val ch = s[i]
        when {
            ch.isDigit() -> i++
            ch == '.' && !sawPoint -> {
                sawPoint = true
                i++
            }
            else -> break
        }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
        var j = i + 1
        if (j < s.length && (s[j] == '-' || s[j] == '+')) j++
        if (j < s.length && s[j].isDigit()) {
            i = j
            while (i < s.length && s[i].isDigit()) i++
        }
    }
    return i
}

private const val ARC_ARGUMENTS = 7
private const val LARGE_ARC_FLAG = 3
private const val SWEEP_FLAG = 4
