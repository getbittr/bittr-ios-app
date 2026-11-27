package com.bittr.android.feature.send

import com.bittr.android.core.common.amount.parsedUserAmount
import com.bittr.android.core.common.amount.wholeSatoshis
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

    /**
     * Whether Next should accept the text: blank, as whether an amount is needed is decided later,
     * or a number that is not negative, read as [parsedUserAmount] reads it.
     */
    fun isWellFormedAmount(text: String, currency: AmountCurrency): Boolean =
        text.isBlank() || (parsedUserAmount(text, allowingFraction = currency != AmountCurrency.Satoshis)?.signum() ?: -1) >= 0

    /**
     * `getSatoshisFrom(enteredAmount:)`, read through [parsedUserAmount] as iOS reads it. Null when the
     * text is not a number, the fiat price is missing, or it is below zero or above 21 million bitcoin.
     */
    fun parseSats(text: String, currency: AmountCurrency, pricePerBitcoin: Double?): Long? {
        val amount = parsedUserAmount(text, allowingFraction = currency != AmountCurrency.Satoshis) ?: return null
        val satoshis = when (currency) {
            AmountCurrency.Satoshis -> amount
            AmountCurrency.Bitcoin -> amount.movePointRight(8)
            AmountCurrency.Fiat -> {
                val price = pricePerBitcoin?.takeIf { it > 0 && it.isFinite() } ?: return null
                amount.divide(BigDecimal.valueOf(price), 16, RoundingMode.HALF_UP).movePointRight(8)
            }
        }
        return wholeSatoshis(satoshis)
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
