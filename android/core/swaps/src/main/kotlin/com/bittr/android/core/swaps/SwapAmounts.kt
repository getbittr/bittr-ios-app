package com.bittr.android.core.swaps

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.floor

/**
 * The arithmetic of a swap — iOS's `SendableAmount.calculateSendableAmount`,
 * `BoltzRefund.calculateClaimOrRefundTransactionFee` and the fee lines in `SwapManager`,
 * ported formula for formula.
 */
object SwapAmounts {

    /** Claim and refund transactions are always this size (`claimOrRefundTransactionVBytes`). */
    const val CLAIM_OR_REFUND_VBYTES = 99L

    /** The rate used when there is neither a fresh nor a cached estimate. */
    const val FALLBACK_FEE_RATE_SAT_PER_VB = 50L

    /**
     * Our claim (or refund) fee: fastest rate × 99 vB, else the last known rate × 99, else 50 × 99.
     * `Int(fastest * 99)` truncates, as here.
     */
    fun claimOrRefundFee(fastestSatPerVb: Double?, lastKnownSatPerVb: Long?): Long = when {
        fastestSatPerVb != null -> (fastestSatPerVb * CLAIM_OR_REFUND_VBYTES).toLong()
        lastKnownSatPerVb != null -> lastKnownSatPerVb * CLAIM_OR_REFUND_VBYTES
        else -> FALLBACK_FEE_RATE_SAT_PER_VB * CLAIM_OR_REFUND_VBYTES
    }

    /**
     * The most a lightning-to-onchain swap can deliver: outbound less ~1 % routing headroom, less
     * Boltz's percentage (0.5 % without a quote) and lockup miner fee, less our claim fee.
     */
    fun maxLightningToOnchain(outboundSats: Long, quote: BoltzFeeQuote?, claimFeeSats: Long): Long {
        val routingHeadroom = outboundSats * 0.01
        val maxInvoice = outboundSats - routingHeadroom
        val percentage = quote?.percentage ?: DEFAULT_PERCENTAGE
        val lockupFee = quote?.minerFeeSats ?: 0
        val maxOnchainLockup = maxInvoice * (1.0 - percentage / 100.0) - lockupFee
        return maxOf(maxOnchainLockup.toLong() - claimFeeSats, 0L)
    }

    /** Room left in the channel to receive: value − outbound − both reserves. */
    fun availableChannelSpace(channelValueSats: Long, outboundSats: Long, reserveSats: Long?, counterpartyReserveSats: Long): Long =
        channelValueSats - outboundSats - (reserveSats ?: 0) - counterpartyReserveSats

    /**
     * The most an onchain-to-lightning swap can move: the drainable balance less Boltz's miner fee,
     * divided back through its percentage, less a 2-sat margin for Boltz's own rounding — and never
     * more than the channel can take.
     */
    fun maxOnchainToLightning(drainableSats: Long, quote: BoltzFeeQuote?, channelSpaceSats: Long): Long {
        val percentage = quote?.percentage ?: DEFAULT_PERCENTAGE
        val minerFee = quote?.minerFeeSats ?: 0
        val invertible = maxOf(drainableSats - minerFee, 0L) / (1.0 + percentage / 100.0)
        val lightningMax = maxOf(floor(invertible).toLong() - 2, 0L)
        return minOf(channelSpaceSats, lightningMax)
    }

    /**
     * LDK's default cap on routing fees for a payment of [amountSats]: 1 % plus 50 sats — what
     * iOS's `getLightningFeesInSatoshis` reads from `RouteParameters`. The same formula as Send's.
     */
    fun maxRoutingFeeSats(amountSats: Long): Long = (amountSats * 1000 / 100 + 50_000) / 1000

    /** `createDateId()`: `yyyyMMddHHmmss`, local time. */
    fun createDateId(now: Date = Date()): String = SimpleDateFormat("yyyyMMddHHmmss", Locale.US).format(now)

    /** `addSpaces()`: "75 000". */
    fun group(value: Long): String {
        val digits = kotlin.math.abs(value).toString().reversed().chunked(3).joinToString(" ").reversed()
        return if (value < 0) "-$digits" else digits
    }

    private const val DEFAULT_PERCENTAGE = 0.5
}
