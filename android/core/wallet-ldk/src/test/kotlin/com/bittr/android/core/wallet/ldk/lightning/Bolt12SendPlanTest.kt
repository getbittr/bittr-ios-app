package com.bittr.android.core.wallet.ldk.lightning

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The BOLT12 fee ceiling.
 *
 * A fee limit is a decision about the user's money in both directions: too low
 * and their payment fails for no reason they can see, too high and they overpay
 * a route they already authorised. `BitcoinManager.swift:610` is one line of
 * arithmetic with a misleading comment next to it, which is why it is pinned
 * here.
 */
class Bolt12SendPlanTest {

    @Test
    fun `the allowance is one percent of the amount plus fifty satoshis`() {
        // 1 000 sats -> 10 000 msat (1%) + 50 000 msat (50 sats).
        assertEquals(60_000uL, Bolt12SendPlan.maxTotalRoutingFeeMsat(1_000L))

        // 1 000 000 sats -> 10 000 000 msat + 50 000 msat.
        assertEquals(10_050_000uL, Bolt12SendPlan.maxTotalRoutingFeeMsat(1_000_000L))
    }

    /**
     * `50_000` sits next to an amount that is already in millisatoshis, which is
     * exactly the constant somebody later "corrects" to `50`. Asserting the flat
     * part on its own is what makes that correction fail a test rather than a
     * user's payment.
     */
    @Test
    fun `the flat part is fifty satoshis, not fifty millisatoshis`() {
        assertEquals(
            "A zero-amount send still carries the flat allowance, and it is 50 sats.",
            50_000uL,
            Bolt12SendPlan.maxTotalRoutingFeeMsat(0L),
        )
        assertEquals(50_000uL, Bolt12SendPlan.FLAT_FEE_ALLOWANCE_MSAT)
    }

    /**
     * The flat part dominating at small amounts is the design, not a bug: a 1%
     * cap alone would reject most small BOLT12 sends, because routing has a floor
     * cost that does not scale down.
     */
    @Test
    fun `the allowance is proportionally generous for small payments`() {
        val amountSats = 500L
        val allowanceSats = Bolt12SendPlan.maxTotalRoutingFeeMsat(amountSats).toLong() / 1000L

        assertEquals(55L, allowanceSats)
        assertTrue("11% of the amount, on purpose.", allowanceSats > amountSats / 100L)
    }

    @Test
    fun `the other three route limits are iOS's constants`() {
        val limits = Bolt12SendPlan.routeLimits(amountSats = 10_000L)

        assertEquals(1008u, limits.maxTotalCltvExpiryDelta)
        assertEquals(10.toUByte(), limits.maxPathCount)
        assertEquals(2.toUByte(), limits.maxChannelSaturationPowerOfHalf)
        assertEquals(150_000uL, limits.maxTotalRoutingFeeMsat)
    }

    @Test
    fun `the amount sent is the amount, in millisatoshis`() {
        assertEquals(10_000_000uL, Bolt12SendPlan.amountMsat(10_000L))
        assertEquals(0uL, Bolt12SendPlan.amountMsat(0L))
    }

    /**
     * iOS wraps the result in `UInt64(...)`, which **traps** on a negative.
     * Kotlin's `toULong()` would instead wrap to something near `ULong.MAX_VALUE`
     * and hand ldk-node an effectively unlimited fee allowance — silent, and in
     * the direction that spends the user's money.
     */
    @Test
    fun `a negative amount is refused rather than wrapped`() {
        val thrown = assertThrows(IllegalArgumentException::class.java) {
            Bolt12SendPlan.maxTotalRoutingFeeMsat(-1L)
        }
        assertTrue(thrown.message!!.contains("-1"))

        assertThrows(IllegalArgumentException::class.java) {
            Bolt12SendPlan.amountMsat(-1L)
        }
    }
}
