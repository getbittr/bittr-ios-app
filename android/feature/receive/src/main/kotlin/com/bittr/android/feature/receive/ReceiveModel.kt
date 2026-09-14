package com.bittr.android.feature.receive

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
 * @property addressLabel `receive.addressLabel`, beside the title (on-chain, lightning address).
 * @property lowerLabel `receive.invoiceLabel`, the full-width text under the title (invoice, Bitcoin QR).
 * @property qrPayload null when there is nothing to encode — an unavailable lightning address.
 * @property showBolt the lightning bolt before the title.
 */
data class ReceiveDisplay(
    val title: String,
    val showBolt: Boolean,
    val addressLabel: String,
    val lowerLabel: String,
    val qrPayload: String?,
    val copyText: String,
)

/**
 * `setLabels`, as a pure function of what it gathered.
 *
 * Ported as iOS builds it, including one quirk worth knowing: the Bitcoin QR appends
 * `&label=` and `&lightning=` directly after the address when there is no amount, so it
 * reads `bitcoin:<address>&lightning=<invoice>` with no `?`. The Send parser on both
 * platforms has to accept that, because that is what the iOS app hands out.
 *
 * @param amountSats null when no amount was entered.
 */
fun receiveDisplay(
    type: ReceiveType,
    onchainAddress: String,
    invoice: String,
    lightningAddress: String?,
    amountSats: Long?,
    description: String,
): ReceiveDisplay {
    val amountText = amountSats?.let { "?amount=${bitcoinAmount(it)}" }.orEmpty()
    val labelText = if (description.isNotEmpty()) "&label=$description" else ""
    val bitcoinQr = "bitcoin:$onchainAddress$amountText$labelText&lightning=$invoice"

    return when (type) {
        ReceiveType.Onchain -> ReceiveDisplay(
            title = ReceiveStrings.ADDRESS,
            showBolt = false,
            addressLabel = onchainAddress + amountText,
            lowerLabel = "",
            qrPayload = "bitcoin:$onchainAddress$amountText".uppercase(),
            copyText = if (amountText.isEmpty()) onchainAddress else "bitcoin:$onchainAddress$amountText",
        )
        ReceiveType.Lightning -> ReceiveDisplay(
            title = ReceiveStrings.INVOICE,
            showBolt = true,
            addressLabel = "",
            lowerLabel = invoice,
            qrPayload = "lightning:$invoice".uppercase(),
            copyText = invoice,
        )
        ReceiveType.BitcoinQr -> ReceiveDisplay(
            title = ReceiveStrings.BITCOIN_QR,
            showBolt = false,
            addressLabel = "",
            // A word joiner after "?" so the label does not wrap at the query mark.
            lowerLabel = bitcoinQr.replace("?", "?⁠"),
            qrPayload = bitcoinQr,
            copyText = bitcoinQr,
        )
        ReceiveType.Lnurl -> ReceiveDisplay(
            title = ReceiveStrings.ADDRESS,
            showBolt = true,
            addressLabel = lightningAddress ?: ReceiveStrings.UNAVAILABLE,
            lowerLabel = "",
            // No QR for an unavailable address — it would encode the word "Unavailable".
            qrPayload = lightningAddress,
            copyText = lightningAddress ?: ReceiveStrings.UNAVAILABLE,
        )
    }
}

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
