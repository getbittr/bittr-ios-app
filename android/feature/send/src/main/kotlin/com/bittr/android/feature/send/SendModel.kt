package com.bittr.android.feature.send

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale
import kotlin.math.floor

/** `OnchainOrLightning`: Regular or Instant. */
enum class SendMode { Onchain, Lightning }

/** `SelectedCurrency`: what the amount field is entered in. */
enum class AmountCurrency { Satoshis, Bitcoin, Fiat }

/** `SelectedFee`: the three tiles on the confirm page, fastest first. */
enum class FeeTier { High, Medium, Low }

/** mempool.space's recommended rates in sat/vB, rounded and at least 1 — `FeeEstimates`. */
data class FeeEstimates(val fastest: Double, val hour: Double, val economy: Double)

/** A drain of the whole on-chain wallet, already clamped to what ldk-node will let leave. */
data class DrainQuote(val sendableSats: Long, val feeSats: Long, val vsize: Long)

/** The user's display currency: its code for the currency label, its symbol after amounts. */
data class FiatCurrency(val code: String, val symbol: String)

/** The arithmetic and formatting iOS spreads over `String`, `Int` and `Double` extensions. */
internal object SendMath {

    private const val SATS_PER_BITCOIN = 100_000_000L
    private const val MAX_SATS = 2_100_000_000_000_000L

    /**
     * `getSatoshisFrom(enteredAmount:)`. Satoshis take whole numbers only; bitcoin and fiat
     * take one decimal separator, `.` or `,`. Spaces (this app's own grouping) are ignored.
     * Null when the text is not a number or the fiat price is missing.
     */
    fun parseSats(text: String, currency: AmountCurrency, pricePerBitcoin: Double?): Long? {
        val stripped = text.filterNot { it.isWhitespace() || it == ' ' }
        if (stripped.isEmpty()) return null
        return when (currency) {
            AmountCurrency.Satoshis -> if (stripped.all { it.isDigit() }) toSats(BigDecimal(stripped)) else null
            AmountCurrency.Bitcoin -> decimal(stripped)?.let { toSats(it.multiply(BigDecimal(SATS_PER_BITCOIN))) }
            AmountCurrency.Fiat -> {
                val price = pricePerBitcoin?.takeIf { it > 0 && it.isFinite() } ?: return null
                decimal(stripped)?.let {
                    toSats(it.divide(BigDecimal(price), 12, RoundingMode.HALF_UP).multiply(BigDecimal(SATS_PER_BITCOIN)))
                }
            }
        }
    }

    private fun decimal(text: String): BigDecimal? {
        val normalised = text.replace(',', '.')
        if (normalised.count { it == '.' } > 1) return null
        if (!normalised.all { it.isDigit() || it == '.' } || normalised == ".") return null
        return runCatching { BigDecimal(normalised) }.getOrNull()
    }

    private fun toSats(value: BigDecimal): Long? {
        val rounded = value.setScale(0, RoundingMode.HALF_UP)
        if (rounded.signum() < 0 || rounded > BigDecimal(MAX_SATS)) return null
        return rounded.toLong()
    }

    /** `SatPerVb.wholeSatPerVb`: whole sats per vbyte, never below 1. */
    fun wholeSatPerVb(rate: Double): Long = if (!rate.isFinite() || rate <= 1.0) 1L else floor(rate).toLong()

    /** `feeSats(forVsize:)`. */
    fun feeSats(rate: Double, vsize: Long): Long = if (vsize <= 0) 0L else wholeSatPerVb(rate) * vsize

    /**
     * `getLightningFeesInSatoshis()` — the most routing may cost, which iOS reads off LDK's
     * route parameters for the invoice: LDK's default cap, 1 % of the amount plus 50 sats.
     */
    fun maxRoutingFeeSats(amountSats: Long): Long = (amountSats * 1000 / 100 + 50_000) / 1000

    /** `addSpaces()`. */
    fun group(value: Long): String = value.toString().reversed().chunked(3).joinToString(" ").reversed()

    /** `formattedAmount()`: "50 000 sats". */
    fun formattedAmount(sats: Long): String = "${group(sats)} ${SendStrings.SATS}"

    /** `formattedFiatAmount()`: two decimals and the symbol, e.g. "4.99 €". Null with no price. */
    fun formattedFiat(sats: Long, pricePerBitcoin: Double?, symbol: String): String? =
        pricePerBitcoin?.let { String.format(Locale.US, "%.2f", sats.toDouble() / SATS_PER_BITCOIN * it) + " " + symbol }

    /** `youcansend` with the amount grouped. */
    fun availableLabel(sats: Long): String = SendStrings.YOU_CAN_SEND.replace("<amount>", group(maxOf(sats, 0L)))

    /** The `<b>` tags iOS renders as bold, removed for a plain-text alert. */
    fun plain(text: String): String = text.replace(Regex("</?b>"), "")

    private val EMAIL = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")

    /** A Lightning address or an LNURL — `isValidEmail() || hasPrefix("lnurl")`. */
    fun isLnurl(text: String): Boolean = EMAIL.matches(text) || text.lowercase().startsWith("lnurl")
}
