package com.bittr.android.core.wallet.ldk.onchain

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * iOS's own fee-rounding assertions, run against the Kotlin port.
 *
 * The first four cases are `bittrTests.swift:159–162` verbatim, including their
 * comments. Keeping them recognisable is the point: if iOS's suite changes these
 * numbers, the diff should be obvious here too.
 */
class SatPerVbTest {

    @Test
    fun `matches the iOS suite's four assertions`() {
        assertEquals(2uL, SatPerVb.wholeSatPerVb(2.9))   // floored to what is broadcast
        assertEquals(10uL, SatPerVb.wholeSatPerVb(10.0))
        assertEquals(1uL, SatPerVb.wholeSatPerVb(1.0))   // minimum one
        assertEquals(1uL, SatPerVb.wholeSatPerVb(0.5))   // below one clamps to one
    }

    @Test
    fun `non-finite and negative rates clamp to one rather than to zero`() {
        // A 0 sat/vB rate is a transaction that never confirms, so every path
        // that could produce one has to land on 1 instead. In Kotlin
        // `Double.NaN.toULong()` is 0 and `(-1.0).toULong()` is 0, so without the
        // guard in `wholeSatPerVb` all three of these would be exactly that.
        assertEquals(1uL, SatPerVb.wholeSatPerVb(Double.NaN))
        assertEquals(1uL, SatPerVb.wholeSatPerVb(Double.NEGATIVE_INFINITY))
        assertEquals(1uL, SatPerVb.wholeSatPerVb(-42.0))
        assertEquals(1uL, SatPerVb.wholeSatPerVb(0.0))
    }

    @Test
    fun `positive infinity clamps to one, not to a saturated rate`() {
        // `floor(inf).toULong()` saturates to ULong.MAX_VALUE in Kotlin, which
        // would then be handed to FeeRate.fromSatPerVb. The isFinite guard is
        // what keeps it at the floor.
        assertEquals(1uL, SatPerVb.wholeSatPerVb(Double.POSITIVE_INFINITY))
    }

    @Test
    fun `the boundary above one floors rather than taking the early return`() {
        // iOS's guard is `> 1`, so 1.0 early-returns and 1.9 floors. Both give 1;
        // this pins that they agree, because a port that "fixed" the guard to
        // `>= 1` would also give 1 and the difference would never show up.
        assertEquals(1uL, SatPerVb.wholeSatPerVb(1.9))
        assertEquals(2uL, SatPerVb.wholeSatPerVb(2.0))
    }

    @Test
    fun `fee is quoted at the broadcast rate over rounded vsize`() {
        // 3 sat/vB over 141 vB.
        assertEquals(423L, SatPerVb.feeSats(satPerVb = 3.4, vsize = 141.0))
        // The rate floors to 3 first, so 3.9 quotes the same as 3.0.
        assertEquals(423L, SatPerVb.feeSats(satPerVb = 3.9, vsize = 141.0))
    }

    @Test
    fun `vsize ties round away from zero, as Swift does and kotlin-math does not`() {
        // `kotlin.math.round(2.5)` is 2.0 (half-to-even); Swift's `(2.5).rounded()`
        // is 3.0 (half-away-from-zero). At 1 sat/vB that is a one-satoshi
        // difference in a quoted fee, and at 50 sat/vB it is fifty. This asserts
        // the Swift rule.
        assertEquals(3L, SatPerVb.feeSats(satPerVb = 1.0, vsize = 2.5))
        assertEquals(4L, SatPerVb.feeSats(satPerVb = 1.0, vsize = 3.5))
        assertEquals(3L, SatPerVb.feeSats(satPerVb = 1.0, vsize = 3.4))
    }

    @Test
    fun `a non-positive or non-finite vsize quotes no fee`() {
        assertEquals(0L, SatPerVb.feeSats(satPerVb = 10.0, vsize = 0.0))
        assertEquals(0L, SatPerVb.feeSats(satPerVb = 10.0, vsize = -5.0))
        assertEquals(0L, SatPerVb.feeSats(satPerVb = 10.0, vsize = Double.NaN))
        assertEquals(0L, SatPerVb.feeSats(satPerVb = 10.0, vsize = Double.POSITIVE_INFINITY))
    }

    @Test
    fun `a large vsize does not wrap the fee negative`() {
        // The multiplication is done in Long precisely so this cannot come back
        // negative. `Int` is 32-bit in Kotlin and 64-bit in Swift, so the literal
        // port of `Int(...) * Int(...)` is the one that wraps.
        val fee = SatPerVb.feeSats(satPerVb = 100.0, vsize = 50_000_000.0)
        assertEquals(5_000_000_000L, fee)
    }
}
