package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.OnchainDrainClamp
import com.bittr.android.core.wallet.ldk.onchain.OnchainDrainPreview
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * One read of the wallet's money, and the cache writes it asks for.
 *
 * Includes the two hand-offs this issue owed other code: the `ldkSpendableSats`
 * the drain clamp has been waiting for, and the `openChannelFundingTxIds` the
 * closure scan has been waiting for.
 */
class WalletBalanceSnapshotTest {

    private val fundingTxo = TxOutpoint(txId = "funding-tx", vout = 1u)

    @Test
    fun `the snapshot is the four figures iOS applies to bittrWallet`() {
        val snapshot = WalletBalanceSnapshot.of(
            channels = listOf(
                channel(
                    channelId = "open",
                    fundingTxo = fundingTxo,
                    outboundCapacityMsat = 30_000_000uL,
                    unspendablePunishmentReserveSats = 1_000uL,
                ),
            ),
            balances = balances(
                totalOnchainBalanceSats = 250_000uL,
                spendableOnchainBalanceSats = 248_000uL,
                pendingBalancesFromChannelClosures = listOf(
                    PendingSweepView.PendingBroadcast(amountSatoshis = 5_000uL),
                ),
            ),
            payments = listOf(payment(id = "a"), payment(id = "b")),
        )

        assertEquals(31_000L, snapshot.satoshisLightning)
        assertEquals(250_000L, snapshot.satoshisOnchain)
        assertEquals(248_000L, snapshot.satoshisOnchainSpendable)
        assertEquals(5_000L, snapshot.pendingClosureSatoshis)
        assertEquals(2, snapshot.paymentCount)
    }

    // ---- The hand-off to OnchainDrainClamp. ----

    /**
     * The `null`-vs-`0` row, asserted through the seam rather than only inside
     * the clamp.
     *
     * `OnchainDrainClampTest` already proves the clamp treats them differently.
     * What this proves is that the *only* way to produce the null is to have no
     * snapshot — so a caller cannot reach the wrong one by writing `?: 0` on a
     * `Long` it already holds.
     */
    @Test
    fun `no snapshot means no clamp, and a zero snapshot means clamp to zero`() {
        val preview = OnchainDrainPreview(sendableSats = 40_000uL, feeSats = 500uL, vsize = 140uL)

        val neverRead: WalletBalanceSnapshot? = null
        assertNull(neverRead.ldkSpendableSats())
        assertEquals(
            "Before the first balance read there is nothing to clamp against, so the " +
                "BDK preview stands. Collapsing this to 0 stops the user emptying their " +
                "own wallet for the whole window between node start and first read.",
            preview,
            OnchainDrainClamp.clampToLdkSpendable(preview, neverRead.ldkSpendableSats()),
        )

        val readAndEmpty: WalletBalanceSnapshot? = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(totalOnchainBalanceSats = 0uL, spendableOnchainBalanceSats = 0uL),
            payments = emptyList(),
        )
        assertEquals(0L, readAndEmpty.ldkSpendableSats())
        assertEquals(
            0uL,
            OnchainDrainClamp
                .clampToLdkSpendable(preview, readAndEmpty.ldkSpendableSats())
                .sendableSats,
        )
    }

    @Test
    fun `the clamp is fed LDK's spendable balance, which is net of the anchor reserve`() {
        val snapshot = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(
                totalOnchainBalanceSats = 100_000uL,
                spendableOnchainBalanceSats = 99_000uL,
                totalAnchorChannelsReserveSats = 1_000uL,
            ),
            payments = emptyList(),
        )

        assertEquals(
            "Spendable, not total. BDK would offer the whole 100 000 because it does " +
                "not know the anchor reserve exists.",
            99_000L,
            snapshot.ldkSpendableSats(),
        )
        assertNotEquals(snapshot.satoshisOnchain, snapshot.ldkSpendableSats())
    }

    // ---- The hand-off to ChannelClosureScan. ----

    @Test
    fun `open channel funding txids include pending channels, not only ready ones`() {
        val snapshot = WalletBalanceSnapshot.of(
            channels = listOf(
                channel(channelId = "ready", fundingTxo = TxOutpoint("tx-ready", 0u)),
                channel(
                    channelId = "pending",
                    isChannelReady = false,
                    fundingTxo = TxOutpoint("tx-pending", 0u),
                ),
                channel(channelId = "unfunded", fundingTxo = null),
            ),
            balances = balances(),
            payments = emptyList(),
        )

        assertEquals(
            "A pending channel's funding output has not been spent by a closure. " +
                "Leaving it out would start the closure scan on a channel that is opening.",
            listOf("tx-ready", "tx-pending"),
            snapshot.openChannelFundingTxIds,
        )
    }

    // ---- The cache writes. ----

    @Test
    fun `the funding outpoint is offered for caching only when there is an active channel`() {
        val withChannel = WalletBalanceSnapshot.of(
            channels = listOf(channel(fundingTxo = fundingTxo)),
            balances = balances(),
            payments = emptyList(),
        )
        assertEquals(fundingTxo, withChannel.channelFundingOutpointToStore)

        val pendingOnly = WalletBalanceSnapshot.of(
            channels = listOf(channel(isChannelReady = false, fundingTxo = fundingTxo)),
            balances = balances(),
            payments = emptyList(),
        )
        assertNull(
            "No active channel, so nothing to write. Null means do not write — not " +
                "write null, which would lose the outpoint the closure scan needs.",
            pendingOnly.channelFundingOutpointToStore,
        )
    }

    @Test
    fun `a force-close clears the cached funding outpoint, a quiet wallet does not`() {
        val quiet = WalletBalanceSnapshot.of(
            channels = listOf(channel(fundingTxo = fundingTxo)),
            balances = balances(),
            payments = emptyList(),
        )
        assertFalse(quiet.clearChannelFundingOutpoint)

        val forceClosed = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(
                lightningBalances = listOf(
                    LightningBalanceView.ClaimableAwaitingConfirmations(
                        channelId = "closed",
                        amountSatoshis = 10_000uL,
                        source = BalanceSourceView.HolderForceClosed,
                    ),
                ),
            ),
            payments = emptyList(),
        )
        assertTrue(
            "iOS: `if pendingBalancesFromChannelClosures > 0 { removeChannelFundingOutpoint() }`.",
            forceClosed.clearChannelFundingOutpoint,
        )
    }

    @Test
    fun `closure spending txids come from the broadcast sweeps`() {
        val snapshot = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(
                pendingBalancesFromChannelClosures = listOf(
                    PendingSweepView.PendingBroadcast(1_000uL),
                    PendingSweepView.AwaitingThresholdConfirmations(2_000uL, "sweep-tx"),
                ),
            ),
            payments = emptyList(),
        )

        assertEquals(listOf("sweep-tx"), snapshot.closureSpendingTxIds)
    }

    // ---- The light-sync comparison. ----

    @Test
    fun `a light sync reports a change when the on-chain total, closures or payment count move`() {
        val base = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(totalOnchainBalanceSats = 10_000uL),
            payments = listOf(payment()),
        )

        assertFalse("Nothing moved.", base.differsFrom(base))
        assertTrue("Nothing has been applied yet, so anything is a change.", base.differsFrom(null))

        val moreOnchain = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(totalOnchainBalanceSats = 11_000uL),
            payments = listOf(payment()),
        )
        assertTrue(moreOnchain.differsFrom(base))

        val morePayments = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(totalOnchainBalanceSats = 10_000uL),
            payments = listOf(payment(id = "a"), payment(id = "b")),
        )
        assertTrue(morePayments.differsFrom(base))

        val closing = WalletBalanceSnapshot.of(
            channels = emptyList(),
            balances = balances(
                totalOnchainBalanceSats = 10_000uL,
                pendingBalancesFromChannelClosures = listOf(
                    PendingSweepView.PendingBroadcast(500uL),
                ),
            ),
            payments = listOf(payment()),
        )
        assertTrue(closing.differsFrom(base))
    }

    /**
     * iOS's comparison does not include the Lightning balance
     * (`BitcoinManager.swift:496`). Ported as-is, and asserted so that the
     * omission is a recorded decision rather than something to "fix" later: a
     * Lightning receive changes the payment count too, so the third clause
     * already catches it.
     */
    @Test
    fun `a Lightning-only balance move is not itself a change`() {
        val payments = listOf(payment())
        val before = WalletBalanceSnapshot.of(
            channels = listOf(channel(outboundCapacityMsat = 1_000_000uL)),
            balances = balances(),
            payments = payments,
        )
        val after = WalletBalanceSnapshot.of(
            channels = listOf(channel(outboundCapacityMsat = 2_000_000uL)),
            balances = balances(),
            payments = payments,
        )

        assertNotEquals(before.satoshisLightning, after.satoshisLightning)
        assertFalse(after.differsFrom(before))
    }
}

/**
 * Whether the wallet may be deleted.
 *
 * The most expensive decision in the package: a wipe taken too early deletes
 * channel monitors a BIP39 seed cannot reconstruct, and a force-closed channel's
 * `to_local` output is then unsweepable for good.
 */
class WipeSafetyTest {

    @Test
    fun `an empty, channel-free wallet may be wiped`() {
        assertTrue(
            WipeSafety.channelsFullyClosedAndSwept(
                channels = emptyList(),
                balances = balances(),
            ),
        )
    }

    @Test
    fun `an open channel refuses the wipe`() {
        assertFalse(
            WipeSafety.channelsFullyClosedAndSwept(
                channels = listOf(channel()),
                balances = balances(),
            ),
        )
    }

    @Test
    fun `a channel that is not even ready still refuses the wipe`() {
        assertFalse(
            "listChannels().isEmpty(), not activeChannel() == null. A channel still " +
                "opening has a funding transaction on-chain and monitors to keep.",
            WipeSafety.channelsFullyClosedAndSwept(
                channels = listOf(channel(isChannelReady = false)),
                balances = balances(),
            ),
        )
    }

    @Test
    fun `lightning funds still held refuse the wipe`() {
        assertFalse(
            WipeSafety.channelsFullyClosedAndSwept(
                channels = emptyList(),
                balances = balances(totalLightningBalanceSats = 1uL),
            ),
        )
    }

    @Test
    fun `a sweep still settling refuses the wipe`() {
        assertFalse(
            "This is the CSV-delayed to_local output. Wiping now loses it permanently.",
            WipeSafety.channelsFullyClosedAndSwept(
                channels = emptyList(),
                balances = balances(
                    pendingBalancesFromChannelClosures = listOf(
                        PendingSweepView.AwaitingThresholdConfirmations(50_000uL, "sweep"),
                    ),
                ),
            ),
        )
    }

    /**
     * iOS: `guard let node = self.ldkNode else { return false }`.
     *
     * On Android a null node is routine — process death, service restart, a wipe
     * already under way — so this is the case the function sees most, and it has
     * to fail towards "do not wipe".
     */
    @Test
    fun `no node means no answer, and no answer means no wipe`() {
        assertFalse(WipeSafety.channelsFullyClosedAndSwept(channels = null, balances = balances()))
        assertFalse(WipeSafety.channelsFullyClosedAndSwept(channels = emptyList(), balances = null))
        assertFalse(WipeSafety.channelsFullyClosedAndSwept(channels = null, balances = null))
    }
}
