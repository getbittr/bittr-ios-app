package com.bittr.android.core.wallet.ldk.onchain

import kotlin.math.floor

/**
 * The whole sat/vB rate a transaction is actually broadcast at.
 *
 * Port of `Double.wholeSatPerVb` and `Double.feeSats(forVsize:)`
 * (`Extensions/CGFloat.swift:69–82`). Six call sites on iOS pass a fee estimate
 * through this before it reaches BDK or the user, so the rounding *is* the quoted
 * fee — [SendOnchain, SendViewController, SendableAmount, ConfirmSend].
 *
 * Small enough to look like it needs no port and no test. It needs both, because
 * Kotlin and Swift disagree about rounding in two places that each move real money:
 *
 * 1. **`kotlin.math.round` is half-to-even; Swift's `.rounded()` is
 *    half-away-from-zero.** `round(2.5)` is `2.0` in Kotlin and `3.0` in Swift.
 *    [feeSats] therefore spells the rule out as `floor(x + 0.5)` rather than
 *    calling either language's `round`, so the quoted fee cannot drift a
 *    satoshi-per-vbyte away from what iOS quotes for the same estimate.
 * 2. **`UInt64(aDouble)` traps on a negative or non-finite value in Swift; Kotlin
 *    silently saturates.** `(-1.0).toULong()` is `0` in Kotlin and a crash in
 *    Swift. The guard below makes the question moot instead of relying on either
 *    behaviour — but had it been left out, a NaN fee estimate would become a
 *    0 sat/vB rate on Android and a crash on iOS, and 0 sat/vB is the worse of
 *    the two outcomes: it is a transaction that never confirms.
 *
 * Proved by `SatPerVbTest`, which carries iOS's own four assertions
 * (`bittrTests.swift:159–162`) verbatim plus the cases those four do not reach.
 */
object SatPerVb {

    /** iOS's floor, and the reason it exists: a rate below 1 is not relayed. */
    const val MINIMUM: ULong = 1uL

    /**
     * The rate to hand BDK's `FeeRate.fromSatPerVb`.
     *
     * iOS: `guard self.isFinite, self > 1 else { return 1 }` then
     * `UInt64(self.rounded(.down))`. Note the guard is `> 1`, not `>= 1`, which
     * makes an exact `1.0` take the early return — the same answer the floor
     * would give, so the two branches agree and this port keeps the shape rather
     * than "simplifying" it into something that differs at the boundary.
     */
    fun wholeSatPerVb(satPerVb: Double): ULong {
        if (!satPerVb.isFinite() || satPerVb <= 1.0) return MINIMUM
        return floor(satPerVb).toULong()
    }

    /**
     * Fee in whole satoshis for this rate over `vsize` virtual bytes, quoted at
     * the rate that will actually be broadcast.
     *
     * iOS: `guard vsize.isFinite, vsize > 0 else { return 0 }` then
     * `Int(self.wholeSatPerVb) * Int(vsize.rounded())`. The multiplication is
     * done in `Long` here: `Int` is 64-bit in Swift and 32-bit in Kotlin, and
     * while no real vsize overflows 32 bits, a garbage vsize would wrap to a
     * *negative* fee rather than a large one, and a negative fee is the kind of
     * number that gets clamped into looking reasonable somewhere downstream.
     */
    fun feeSats(satPerVb: Double, vsize: Double): Long {
        if (!vsize.isFinite() || vsize <= 0.0) return 0L
        // Not `round(vsize)`: see the class comment, point 1.
        val roundedVsize = floor(vsize + 0.5).toLong()
        return wholeSatPerVb(satPerVb).toLong() * roundedVsize
    }
}
