package com.bittr.android.core.wallet.ldk.onchain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * The clamp that decides the largest amount allowed to leave the wallet.
 *
 * The case this class exists for is `null` vs `0`: they must give different
 * answers, and the Kotlin idiom that collapses them (`ldkSpendableSats ?: 0`)
 * is a one-character edit away at all times.
 */
class OnchainDrainClampTest {

    private fun preview(sendable: ULong, fee: ULong = 500uL) =
        OnchainDrainPreview(sendableSats = sendable, feeSats = fee, vsize = 141uL)

    @Test
    fun `balances not yet read leaves BDK's preview untouched`() {
        // `satoshisOnchainSpendable` is nil until loadWalletData has run
        // (BittrWallet.swift:17). There is nothing to clamp against yet.
        val bdk = preview(sendable = 100_000uL)
        assertEquals(bdk, OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = null))
    }

    @Test
    fun `a spendable balance of zero clamps to zero, unlike a balance not yet read`() {
        // The whole point. Same preview, two inputs that a careless `?: 0` would
        // make identical, and the difference between "you may send 100k sats" and
        // "you may send nothing".
        val bdk = preview(sendable = 100_000uL)

        val notRead = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = null)
        val actuallyZero = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = 0L)

        assertEquals(100_000uL, notRead.sendableSats)
        assertEquals(0uL, actuallyZero.sendableSats)
        assertNotEquals(
            "null and 0 must not collapse: null means 'balances unread', 0 means " +
                "'LDK says nothing may leave'. Collapsing them makes a wallet " +
                "un-emptiable for the whole window between node start and the " +
                "first balance read.",
            notRead,
            actuallyZero,
        )
    }

    @Test
    fun `BDK stands when it is already under LDK's spendable`() {
        // 10_000 + 500 = 10_500, under 50_000. BDK is the more conservative of
        // the two, so it is the answer and the fee is not re-derived.
        val bdk = preview(sendable = 10_000uL)
        val clamped = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = 50_000L)
        assertEquals(bdk, clamped)
    }

    @Test
    fun `the boundary where the two agree exactly is not clamped`() {
        // sendable + fee == spendable. iOS's guard is `>`, so equality returns
        // the preview unchanged; a port using `>=` would shave the fee off an
        // amount that was already correct.
        val bdk = preview(sendable = 49_500uL, fee = 500uL)
        assertEquals(bdk, OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = 50_000L))
    }

    @Test
    fun `BDK draining the anchor reserve is clamped down to LDK's authority`() {
        // This is the real scenario: BDK sees the full UTXO set and knows nothing
        // about the 1000-sat-per-channel anchor reserve, so it offers to drain it.
        val bdk = preview(sendable = 100_000uL, fee = 500uL)
        val clamped = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = 99_000L)

        // spendable - fee.
        assertEquals(98_500uL, clamped.sendableSats)
        // Fee and vsize come from the real PSBT and are not recomputed.
        assertEquals(500uL, clamped.feeSats)
        assertEquals(141uL, clamped.vsize)
    }

    @Test
    fun `a spendable balance below the fee clamps to zero rather than underflowing`() {
        // ULong subtraction would wrap to ~1.8e19 here. iOS's
        // `spendable > fee ? spendable - fee : 0` is what prevents it, and on
        // Kotlin the consequence of omitting it is worse than on Swift: Swift
        // traps on unsigned overflow, Kotlin silently returns an enormous
        // sendable amount.
        val bdk = preview(sendable = 100_000uL, fee = 5_000uL)
        val clamped = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = 3_000L)
        assertEquals(0uL, clamped.sendableSats)
    }

    @Test
    fun `a negative spendable balance is treated as zero`() {
        // iOS carries this as `Int` and clamps at the call sites with
        // `max(loadedSpendable, 0)` (SendViewController.swift:189).
        val bdk = preview(sendable = 100_000uL)
        val clamped = OnchainDrainClamp.clampToLdkSpendable(bdk, ldkSpendableSats = -1_000L)
        assertEquals(0uL, clamped.sendableSats)
    }
}
