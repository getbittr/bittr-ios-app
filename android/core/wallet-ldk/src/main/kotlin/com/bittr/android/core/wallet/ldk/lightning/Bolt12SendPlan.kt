package com.bittr.android.core.wallet.ldk.lightning

/**
 * What a BOLT12 send is allowed to cost.
 *
 * Port of the five lines at the top of `sendBolt12Payment`
 * (`BitcoinManager.swift:609–619`):
 *
 * ```swift
 * let maxFeeMsat = ((amount*1000)/100) + 50_000 // 1% of amount, plus 50 satoshis.
 * let routeConfig = RouteParametersConfig(
 *     maxTotalRoutingFeeMsat: UInt64(maxFeeMsat),
 *     maxTotalCltvExpiryDelta: 1008,
 *     maxPathCount: 10,
 *     maxChannelSaturationPowerOfHalf: 2)
 * ```
 *
 * This is a fee limit, which makes it a fund-handling decision and not a struct
 * literal: too low and the user's payment fails for no reason they can see, too
 * high and they overpay routing fees on a payment they already authorised. It
 * belongs outside `adapter/` with a named test, and the test is what pins the
 * shape of the formula.
 *
 * ## The formula is 1% *plus 50 sats*, and the flat part dominates
 *
 * `(amountSats * 1000) / 100` is `amountSats * 10` msat — one percent of the
 * amount, expressed in millisatoshis. The `+ 50_000` msat is a flat 50 sats on
 * top. At a 1 000-sat payment that is 10 + 50 = 60 sats of allowance, or 6%; at
 * 1 000 000 sats it is 10 050 sats, or just over 1%. So the limit is generous for
 * small payments on purpose — a 1% cap alone would reject most small BOLT12 sends
 * outright, because routing has a floor cost that does not scale down.
 *
 * Reading the iOS comment as "1% plus 50 000 msat = 50 sats" is the correct
 * reading, and the reason to write it out: `50_000` next to an amount already in
 * millisatoshis is exactly the constant somebody later "fixes" to `50`.
 *
 * ## Negative and absurd amounts
 *
 * iOS takes `amount: Int` and wraps the result in `UInt64(...)`, which **traps**
 * on a negative. Kotlin's `toULong()` would instead wrap to something near
 * `ULong.MAX_VALUE` and hand ldk-node an unlimited fee allowance — the failure
 * being silent and unbounded in the direction that spends the user's money. So a
 * negative amount is rejected here with [IllegalArgumentException], which is the
 * same refusal iOS makes, minus the crash.
 *
 * Proved by `Bolt12SendPlanTest`.
 */
object Bolt12SendPlan {

    /** `maxTotalCltvExpiryDelta: 1008` — 1008 blocks, about a week. */
    const val MAX_TOTAL_CLTV_EXPIRY_DELTA: UInt = 1008u

    /** `maxPathCount: 10`. */
    const val MAX_PATH_COUNT: UByte = 10u

    /** `maxChannelSaturationPowerOfHalf: 2` — no path may use more than a quarter of a channel. */
    const val MAX_CHANNEL_SATURATION_POWER_OF_HALF: UByte = 2u

    /** `+ 50_000` msat. Fifty satoshis, written where the unit is unambiguous. */
    const val FLAT_FEE_ALLOWANCE_MSAT: ULong = 50_000uL

    /**
     * The routing fee ceiling for a payment of [amountSats].
     *
     * @throws IllegalArgumentException if [amountSats] is negative — see the class
     *   comment.
     */
    fun maxTotalRoutingFeeMsat(amountSats: Long): ULong {
        require(amountSats >= 0L) {
            "A BOLT12 send of $amountSats sats is not a payment. iOS traps here rather " +
                "than converting; converting it would hand ldk-node a fee allowance near " +
                "ULong.MAX_VALUE."
        }
        // `amountSats * 10`, written as iOS writes it so the two read the same.
        // Cannot overflow: `require` above bounds it below, and an amount large
        // enough to overflow a signed 64-bit multiply by 1000 is four orders of
        // magnitude past the money supply.
        return ((amountSats * 1000L) / 100L).toULong() + FLAT_FEE_ALLOWANCE_MSAT
    }

    /** The whole `RouteParametersConfig` iOS builds. */
    fun routeLimits(amountSats: Long): RouteLimitsView = RouteLimitsView(
        maxTotalRoutingFeeMsat = maxTotalRoutingFeeMsat(amountSats),
        maxTotalCltvExpiryDelta = MAX_TOTAL_CLTV_EXPIRY_DELTA,
        maxPathCount = MAX_PATH_COUNT,
        maxChannelSaturationPowerOfHalf = MAX_CHANNEL_SATURATION_POWER_OF_HALF,
    )

    /**
     * `amountMsat: UInt64(amount*1000)` — the amount actually sent.
     *
     * Separate from [routeLimits] because the two conversions are easy to
     * transpose and only one of them is a limit. Same refusal on negatives, same
     * reason.
     */
    fun amountMsat(amountSats: Long): ULong {
        require(amountSats >= 0L) { "A send of $amountSats sats is not a payment." }
        return (amountSats * 1000L).toULong()
    }
}
