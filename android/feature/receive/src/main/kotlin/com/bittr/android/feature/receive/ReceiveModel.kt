package com.bittr.android.feature.receive

import com.bittr.android.core.designsystem.inGroupsOfFour
import java.math.BigDecimal
import java.math.RoundingMode

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
 * The entered amount as whole satoshis, or null when nothing (or nothing readable) was
 * entered — `setLabels`' `amountInSatoshis`.
 *
 * Satoshis take whole numbers only; bitcoin and fiat accept a comma or a dot as the
 * decimal separator. Fiat converts through [fiatPricePerBitcoin] and is null without it.
 */
/**
 * Android's decimal keyboard offers `-`, `,` and `.`: an amount with a minus sign, or with more
 * than one separator of either kind, is not one. Satoshis are whole, so any separator at all makes
 * a satoshi amount not one — dropped, a pasted "50000.00" would ask for 5 000 000. Spaces are this
 * app's own grouping. Blank is well formed — it means no amount.
 */
fun isWellFormedAmount(text: String, currency: ReceiveCurrency): Boolean =
    if (currency == ReceiveCurrency.Satoshis) {
        text.filterNot(Char::isWhitespace).all(Char::isDigit)
    } else {
        '-' !in text && text.count { it == '.' || it == ',' } <= 1
    }

fun parseAmountSats(text: String, currency: ReceiveCurrency, fiatPricePerBitcoin: Double?): Long? {
    val cleaned = text.trim().replace(" ", "").replace(',', '.')
    if (cleaned.isEmpty()) return null
    return when (currency) {
        ReceiveCurrency.Satoshis -> cleaned.toLongOrNull()?.takeIf { it >= 0 }
        ReceiveCurrency.Bitcoin -> cleaned.toBigDecimalOrNull()?.let(::bitcoinToSats)
        ReceiveCurrency.Fiat -> {
            val price = fiatPricePerBitcoin?.takeIf { it > 0 } ?: return null
            val fiat = cleaned.toBigDecimalOrNull() ?: return null
            bitcoinToSats(fiat.divide(BigDecimal.valueOf(price), 16, RoundingMode.HALF_UP))
        }
    }
}

private fun bitcoinToSats(bitcoin: BigDecimal): Long? =
    bitcoin.takeIf { it.signum() >= 0 }?.movePointRight(8)?.setScale(0, RoundingMode.HALF_UP)?.toLong()
