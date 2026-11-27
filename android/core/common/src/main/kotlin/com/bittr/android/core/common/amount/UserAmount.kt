package com.bittr.android.core.common.amount

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormatSymbols

/** iOS's `Decimal.satoshis()`: rounded half up to a whole, and null when below zero or above all bitcoin. */
fun wholeSatoshis(satoshis: BigDecimal): Long? {
    if (satoshis.signum() < 0) return null
    val rounded = satoshis.setScale(0, RoundingMode.HALF_UP)
    return if (rounded > BigDecimal.valueOf(MAXIMUM_SATOSHIS)) null else rounded.longValueExact()
}

/**
 * The entered number, as iOS's `String.parsedUserAmount(allowingFraction:)` reads it.
 *
 * Spaces and apostrophes that group thousands are dropped. Of `.` and `,`, the last is the decimal
 * point when both appear; a single one is the decimal point when it is the locale's, or is not
 * followed by exactly three digits, and otherwise groups thousands if the groups are well formed.
 * A repeated one only groups. Without [allowingFraction], as for satoshis, every separator groups.
 * Null when what is left is not a number.
 */
fun parsedUserAmount(
    text: String,
    allowingFraction: Boolean = true,
    decimalSeparator: Char = DecimalFormatSymbols.getInstance().decimalSeparator,
): BigDecimal? {
    val characters = text.filterNot { it in GROUPING_CHARACTERS }.trim()
    if (characters.isEmpty()) return null
    val separatorPositions = characters.indices.filter { characters[it] in SEPARATORS }

    val decimalPosition: Int? = when {
        !allowingFraction || separatorPositions.isEmpty() -> null
        separatorPositions.size == 1 -> {
            val position = separatorPositions[0]
            val fractionDigits = characters.length - position - 1
            when {
                characters[position] == decimalSeparator || fractionDigits != 3 -> position
                groupsAreWellFormed(characters, listOf(position), decimalPosition = null) -> null
                else -> position
            }
        }
        // Both kinds appear, so the last is the decimal point and the other kind groups: "1,234.56" and "1.234,56".
        separatorPositions.map { characters[it] }.toSet().size > 1 -> separatorPositions.last()
        // The same one repeated can only group, as a number has one decimal point at most.
        else -> null
    }

    val groupingPositions = separatorPositions.filter { it != decimalPosition }
    if (!groupsAreWellFormed(characters, groupingPositions, decimalPosition)) return null
    val number = buildString {
        characters.forEachIndexed { index, character ->
            when (index) {
                decimalPosition -> append('.')
                in groupingPositions -> Unit
                else -> append(character)
            }
        }
    }
    return parsedNumber(number)
}

/** iOS's `String.parsedNumber()`: an optional sign, then digits with one decimal point at most and one digit at least. */
private fun parsedNumber(text: String): BigDecimal? {
    var body = text.trim()
    if (body.isEmpty()) return null
    val negative = body.first() == '-'
    if (body.first() == '-' || body.first() == '+') body = body.drop(1)
    if (!body.all { it in '0'..'9' || it in SEPARATORS }) return null
    if (body.none { it in '0'..'9' } || body.count { it in SEPARATORS } > 1) return null
    val magnitude = body.replace(',', '.').toBigDecimalOrNull() ?: return null
    return if (negative) magnitude.negate() else magnitude
}

/** iOS's `NumberParsing.groupsAreWellFormed`: every group after the first is three digits, and the first one to three. */
private fun groupsAreWellFormed(characters: String, groupingPositions: List<Int>, decimalPosition: Int?): Boolean {
    if (groupingPositions.isEmpty()) return true
    val end = decimalPosition ?: characters.length
    if (groupingPositions[0] !in 1..3) return false
    return groupingPositions.indices.all { index ->
        val next = groupingPositions.getOrNull(index + 1) ?: end
        next - groupingPositions[index] - 1 == 3
    }
}

/** The two characters that act as a decimal point. */
private const val SEPARATORS = ".,"

/** Characters that group thousands: spaces, narrow and no-break ones included, and apostrophes. */
private const val GROUPING_CHARACTERS = "\u0020\u00A0\u202F\u2009'\u2019"

/** iOS's `Bitcoin.maximumSatoshis`: 21 million bitcoin. */
const val MAXIMUM_SATOSHIS = 2_100_000_000_000_000L
