package com.bittr.android.feature.receive

import com.bittr.android.core.designsystem.inGroupsOfFour
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormatSymbols

/** iOS's `TransactionType`, in the order the type picker lists them. */
enum class ReceiveType {
    Onchain,
    Lightning,
    BitcoinQr,
    Lnurl,
    ;

    /** Types whose label and QR carry an on-chain address. */
    val usesOnchainAddress: Boolean get() = this == Onchain || this == BitcoinQr

    /** Types that need a Lightning invoice. */
    val usesInvoice: Boolean get() = this == Lightning || this == BitcoinQr

    companion object {

        /**
         * `viewDidLoad`'s default: no channel → the address; a channel and a lightning
         * address → the lightning address; a channel without one → the Bitcoin QR.
         */
        fun default(lightningAvailable: Boolean, lightningAddress: String?): ReceiveType = when {
            !lightningAvailable -> Onchain
            lightningAddress != null -> Lnurl
            else -> BitcoinQr
        }
    }
}

/** iOS's `SelectedCurrency`. Satoshis is the default on open. */
enum class ReceiveCurrency { Satoshis, Bitcoin, Fiat }

/**
 * Which of the four cards under the address are shown — `updateCards(for:)`.
 *
 * @property copyLabel the copy card shows "Copy"; without it the card is an icon only.
 */
data class ReceiveCards(
    val copyLabel: Boolean,
    val refresh: Boolean,
    val edit: Boolean,
    val more: Boolean,
) {
    companion object {
        fun forType(type: ReceiveType, hasChannel: Boolean): ReceiveCards = when (type) {
            // With no channel there are no other types to switch to, so no More.
            ReceiveType.Onchain -> ReceiveCards(copyLabel = false, refresh = true, edit = true, more = hasChannel)
            ReceiveType.Lightning, ReceiveType.BitcoinQr ->
                ReceiveCards(copyLabel = true, refresh = false, edit = true, more = true)
            // The lightning address has no amount, so no Add amount.
            ReceiveType.Lnurl -> ReceiveCards(copyLabel = true, refresh = false, edit = false, more = true)
        }
    }
}

/**
 * What the address box and the QR show — the label half of `setLabels(for:newAddress:)`.
 *
 * @property label `receive.addressLabel`, under the title for every type.
 * @property monospaced [label] is an address or invoice in groups of four, shown monospaced so they line up.
 * @property qrPayload null when there is nothing to encode — data that is missing, or an amount that can't be read.
 * @property copyText null when there is nothing to copy or share, for the same reasons.
 * @property showBolt the lightning bolt before the title.
 */
data class ReceiveDisplay(
    val title: String,
    val showBolt: Boolean,
    val label: String,
    val monospaced: Boolean,
    val qrPayload: String?,
    val copyText: String?,
)

/**
 * `setLabels`, as a pure function of what it gathered.
 *
 * The Bitcoin QR's parameters follow a single `?`, with or without an amount. Older versions of
 * the iOS app handed out `bitcoin:<address>&lightning=<invoice>` when there was no amount, so the
 * Send parser on both platforms still accepts that.
 *
 * @param onchainAddress null when there is none to show; nothing stands in for it in a code.
 * @param invoice null when none could be created, likewise.
 * @param amountSats null when no amount was entered.
 * @param amountInvalid an amount was entered but can't be read, so no code is shown rather than one without it.
 */
fun receiveDisplay(
    type: ReceiveType,
    onchainAddress: String?,
    invoice: String?,
    lightningAddress: String?,
    amountSats: Long?,
    description: String,
    amountInvalid: Boolean = false,
): ReceiveDisplay {
    val amount = amountSats?.let(::bitcoinAmount)
    val amountText = amount?.let { "?amount=$it" }.orEmpty()
    val bitcoinQr = if (onchainAddress != null && invoice != null) {
        val parameters = listOfNotNull(
            amount?.let { "amount=$it" },
            description.takeIf { it.isNotEmpty() }?.let { "label=${percentEncoded(it)}" },
            "lightning=$invoice",
        )
        "bitcoin:$onchainAddress?" + parameters.joinToString("&")
    } else {
        null
    }

    val title = when (type) {
        ReceiveType.Onchain, ReceiveType.Lnurl -> ReceiveStrings.ADDRESS
        ReceiveType.Lightning -> ReceiveStrings.INVOICE
        ReceiveType.BitcoinQr -> ReceiveStrings.BITCOIN_QR
    }
    val showBolt = type == ReceiveType.Lightning || type == ReceiveType.Lnurl
    val missing = ReceiveDisplay(
        title = title,
        showBolt = showBolt,
        label = if (amountInvalid) ReceiveStrings.INVALID_AMOUNT else ReceiveStrings.UNAVAILABLE,
        monospaced = false,
        qrPayload = null,
        copyText = null,
    )
    if (amountInvalid) return missing

    return when (type) {
        ReceiveType.Onchain -> if (onchainAddress == null) missing else ReceiveDisplay(
            title = title,
            showBolt = showBolt,
            label = inGroupsOfFour(onchainAddress) + amountText,
            monospaced = true,
            qrPayload = "bitcoin:$onchainAddress$amountText".uppercase(),
            copyText = if (amountText.isEmpty()) onchainAddress else "bitcoin:$onchainAddress$amountText",
        )
        ReceiveType.Lightning -> if (invoice == null) missing else ReceiveDisplay(
            title = title,
            showBolt = showBolt,
            label = inGroupsOfFour(invoice),
            monospaced = true,
            qrPayload = "lightning:$invoice".uppercase(),
            copyText = invoice,
        )
        ReceiveType.BitcoinQr -> if (bitcoinQr == null) missing else ReceiveDisplay(
            title = title,
            showBolt = showBolt,
            // A word joiner after "?" so the label does not wrap at the query mark.
            label = bitcoinQr.replace("?", "?⁠"),
            monospaced = false,
            qrPayload = bitcoinQr,
            copyText = bitcoinQr,
        )
        ReceiveType.Lnurl -> if (lightningAddress == null) missing else ReceiveDisplay(
            title = title,
            showBolt = showBolt,
            label = lightningAddress,
            monospaced = false,
            qrPayload = lightningAddress,
            copyText = lightningAddress,
        )
    }
}

/**
 * [text] as UTF-8 with everything but the unreserved characters percent-encoded, so no label can end
 * its parameter or the URI early — a `#`, `&`, `=` or `?` — or make it invalid, as a space or an emoji would.
 */
fun percentEncoded(text: String): String = buildString {
    for (byte in text.toByteArray(Charsets.UTF_8)) {
        val value = byte.toInt() and 0xFF
        val character = value.toChar()
        if (character in 'A'..'Z' || character in 'a'..'z' || character in '0'..'9' || character in "-._~") {
            append(character)
        } else {
            append('%').append(HEX_DIGITS[value shr 4]).append(HEX_DIGITS[value and 0x0F])
        }
    }
}

private const val HEX_DIGITS = "0123456789ABCDEF"

/**
 * Satoshis as a bitcoin amount for a BIP-21 `amount=`: up to eight decimals, no grouping,
 * a dot separator, no trailing zeros — `5000` → `0.00005`.
 */
fun bitcoinAmount(satoshis: Long): String =
    BigDecimal.valueOf(satoshis).movePointLeft(8).stripTrailingZeros().toPlainString()

/**
 * Whether Done should accept the text: blank, which means no amount, or a number that is not
 * negative, read as [parsedUserAmount] reads it. Too large, or fiat without a price, still shows
 * Invalid amount, but is a number.
 */
fun isWellFormedAmount(text: String, currency: ReceiveCurrency): Boolean =
    text.isBlank() || (parsedUserAmount(text, allowingFraction = currency != ReceiveCurrency.Satoshis)?.signum() ?: -1) >= 0

/**
 * The entered amount as whole satoshis, or null when nothing (or nothing readable) was
 * entered — `setLabels`' `amountInSatoshis`.
 *
 * Read as iOS reads it, through [parsedUserAmount]. Fiat converts through [fiatPricePerBitcoin]
 * and is null without it. Null too below zero or above 21 million bitcoin, as iOS's `satoshis()`.
 */
fun parseAmountSats(text: String, currency: ReceiveCurrency, fiatPricePerBitcoin: Double?): Long? {
    val amount = parsedUserAmount(text, allowingFraction = currency != ReceiveCurrency.Satoshis) ?: return null
    val satoshis = when (currency) {
        ReceiveCurrency.Satoshis -> amount
        ReceiveCurrency.Bitcoin -> amount.movePointRight(8)
        ReceiveCurrency.Fiat -> {
            val price = fiatPricePerBitcoin?.takeIf { it > 0 && it.isFinite() } ?: return null
            amount.divide(BigDecimal.valueOf(price), 16, RoundingMode.HALF_UP).movePointRight(8)
        }
    }
    return wholeSatoshis(satoshis)
}

/** iOS's `Decimal.satoshis()`: rounded half up to a whole, and null when below zero or above all bitcoin. */
private fun wholeSatoshis(satoshis: BigDecimal): Long? {
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
private const val MAXIMUM_SATOSHIS = 2_100_000_000_000_000L
