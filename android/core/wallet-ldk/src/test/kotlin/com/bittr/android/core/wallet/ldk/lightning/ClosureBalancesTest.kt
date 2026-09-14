package com.bittr.android.core.wallet.ldk.lightning

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The pending-closure total, term by term.
 *
 * Every assertion here is "this balance counts" or "this balance does not", and
 * each wrong answer is a specific lie told to the user on the home screen:
 * double-counted money, or money that has vanished while it settles.
 */
class ClosureBalancesTest {

    private companion object {
        const val OPEN = "open-channel"
        const val CLOSED = "closed-channel"
    }

    // ---- forceClosedSatoshis ----

    @Test
    fun `a force-closed balance awaiting confirmations counts`() {
        val total = ClosureBalances.forceClosedSatoshis(
            balances = listOf(
                LightningBalanceView.ClaimableAwaitingConfirmations(
                    channelId = CLOSED,
                    amountSatoshis = 50_000uL,
                    source = BalanceSourceView.HolderForceClosed,
                ),
            ),
            excludingChannels = emptyList(),
        )

        assertEquals(50_000L, total)
    }

    @Test
    fun `a counterparty force-close counts the same as our own`() {
        val total = ClosureBalances.forceClosedSatoshis(
            balances = listOf(
                LightningBalanceView.ClaimableAwaitingConfirmations(
                    channelId = CLOSED,
                    amountSatoshis = 7_000uL,
                    source = BalanceSourceView.CounterpartyForceClosed,
                ),
            ),
            excludingChannels = emptyList(),
        )

        assertEquals(7_000L, total)
    }

    /**
     * The exclusion `LoadWalletData.swift:639–644` comments at length.
     *
     * A cooperative close pays straight to a wallet address, so the money is
     * already inside `totalOnchainBalanceSats`. Counting it here would show it
     * twice — once on-chain and once as "settling" — and the user would read the
     * sum as their balance.
     */
    @Test
    fun `a cooperative close does not count, because it is already on-chain`() {
        val total = ClosureBalances.forceClosedSatoshis(
            balances = listOf(
                LightningBalanceView.ClaimableAwaitingConfirmations(
                    channelId = CLOSED,
                    amountSatoshis = 120_000uL,
                    source = BalanceSourceView.CoopClose,
                ),
            ),
            excludingChannels = emptyList(),
        )

        assertEquals(0L, total)
    }

    @Test
    fun `a live channel's balance does not count`() {
        val total = ClosureBalances.forceClosedSatoshis(
            balances = listOf(
                LightningBalanceView.ClaimableOnChannelClose(
                    channelId = OPEN,
                    amountSatoshis = 300_000uL,
                ),
            ),
            excludingChannels = emptyList(),
        )

        assertEquals(
            "claimableOnChannelClose is the running balance of a channel that has not " +
                "closed. It is already counted as spendable Lightning.",
            0L,
            total,
        )
    }

    /**
     * The second guard, and the one that looks redundant.
     *
     * ldk-node can report an HTLC-shaped balance against a channel that is still
     * in `listChannels()`. Counting it tells the user a channel they can still
     * spend from is closing, and subtracts that amount from what the send screen
     * offers.
     */
    @Test
    fun `a claimable balance on a channel that is still open does not count`() {
        val balances = listOf(
            LightningBalanceView.MaybeTimeoutClaimableHtlc(
                channelId = OPEN,
                amountSatoshis = 9_000uL,
            ),
            LightningBalanceView.MaybePreimageClaimableHtlc(
                channelId = CLOSED,
                amountSatoshis = 4_000uL,
            ),
        )

        assertEquals(
            4_000L,
            ClosureBalances.forceClosedSatoshis(balances, excludingChannels = listOf(OPEN)),
        )
        assertEquals(
            "With nothing excluded both count — which is what makes the line above a " +
                "real filter rather than a no-op.",
            13_000L,
            ClosureBalances.forceClosedSatoshis(balances, excludingChannels = emptyList()),
        )
    }

    @Test
    fun `contentious and revoked-output balances count`() {
        val total = ClosureBalances.forceClosedSatoshis(
            balances = listOf(
                LightningBalanceView.ContentiousClaimable(CLOSED, 1_000uL),
                LightningBalanceView.CounterpartyRevokedOutputClaimable(CLOSED, 2_000uL),
            ),
            excludingChannels = emptyList(),
        )

        assertEquals(3_000L, total)
    }

    // ---- unbroadcastSatoshis / spendingTxIds ----

    /**
     * The two sweep readers pick disjoint subsets, and that is the design.
     *
     * Before broadcast there is money to count and no transaction to name; after
     * broadcast there is a transaction to name and the money is already visible
     * to the on-chain wallet.
     */
    @Test
    fun `only an unbroadcast sweep counts, and only a broadcast one has a txid`() {
        val sweeps = listOf(
            PendingSweepView.PendingBroadcast(amountSatoshis = 11_000uL),
            PendingSweepView.BroadcastAwaitingConfirmation(
                amountSatoshis = 22_000uL,
                latestSpendingTxId = "tx-broadcast",
            ),
            PendingSweepView.AwaitingThresholdConfirmations(
                amountSatoshis = 33_000uL,
                latestSpendingTxId = "tx-threshold",
            ),
        )

        assertEquals(11_000L, ClosureBalances.unbroadcastSatoshis(sweeps))
        assertEquals(
            listOf("tx-broadcast", "tx-threshold"),
            ClosureBalances.spendingTxIds(sweeps),
        )
    }

    @Test
    fun `no sweeps is zero and no txids, not an error`() {
        assertEquals(0L, ClosureBalances.unbroadcastSatoshis(emptyList()))
        assertEquals(emptyList<String>(), ClosureBalances.spendingTxIds(emptyList()))
    }

    // ---- the sum ----

    @Test
    fun `pendingClosureSatoshis adds the force-closed and the unbroadcast halves`() {
        val total = ClosureBalances.pendingClosureSatoshis(
            balances = balances(
                lightningBalances = listOf(
                    LightningBalanceView.ClaimableAwaitingConfirmations(
                        channelId = CLOSED,
                        amountSatoshis = 40_000uL,
                        source = BalanceSourceView.HolderForceClosed,
                    ),
                    // Excluded: still open.
                    LightningBalanceView.ContentiousClaimable(OPEN, 5_000uL),
                    // Excluded: coop close.
                    LightningBalanceView.ClaimableAwaitingConfirmations(
                        channelId = CLOSED,
                        amountSatoshis = 6_000uL,
                        source = BalanceSourceView.CoopClose,
                    ),
                ),
                pendingBalancesFromChannelClosures = listOf(
                    PendingSweepView.PendingBroadcast(amountSatoshis = 2_000uL),
                    // Excluded: already broadcast, so already on-chain.
                    PendingSweepView.BroadcastAwaitingConfirmation(8_000uL, "tx"),
                ),
            ),
            openChannelIds = listOf(OPEN),
        )

        assertEquals(42_000L, total)
    }
}
