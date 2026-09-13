package com.bittr.android.core.wallet.ldk.lightning

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `satoshisLightning` — the number beside the on-chain balance, and the ceiling
 * on every Lightning send.
 *
 * The two branches and the underflow are the whole test. Everything else about
 * `LoadWalletData.swift:23–34` is addition.
 */
class ChannelBalanceTest {

    // ---- Branch one: outbound capacity, plus the reserve it excludes. ----

    @Test
    fun `the reserve is added back to outbound capacity`() {
        val balance = ChannelBalance.spendableSatoshis(
            channel(
                outboundCapacityMsat = 90_000_000uL, // 90 000 sats
                unspendablePunishmentReserveSats = 1_000uL,
            ),
        )

        assertEquals(
            "The punishment reserve is the user's money; LDK just will not route it. " +
                "Reporting only outboundCapacity understates the balance by the reserve.",
            91_000L,
            balance,
        )
    }

    @Test
    fun `a channel with no reserve reported is the outbound capacity alone`() {
        val balance = ChannelBalance.spendableSatoshis(
            channel(
                outboundCapacityMsat = 5_000_000uL,
                unspendablePunishmentReserveSats = null,
            ),
        )

        assertEquals(5_000L, balance)
    }

    /**
     * iOS divides to satoshis *before* comparing to zero
     * (`LoadWalletData.swift:28`), so 999 msat outbound takes the second branch.
     * Porting the comparison as `outboundCapacityMsat != 0` would take the first
     * and add the whole reserve back on a channel that is at its reserve.
     */
    @Test
    fun `sub-satoshi outbound capacity takes the second branch, as iOS does`() {
        val balance = ChannelBalance.spendableSatoshis(
            channel(
                channelValueSats = 100_000uL,
                outboundCapacityMsat = 999uL,
                inboundCapacityMsat = 98_000_000uL,
                unspendablePunishmentReserveSats = 1_000uL,
                counterpartyUnspendablePunishmentReserveSats = 1_000uL,
            ),
        )

        assertEquals(
            "999 msat is zero satoshis. Taking the first branch here would report " +
                "1 000 sats — the reserve — for a channel that has nothing spendable.",
            1_000L,
            balance,
        )
    }

    // ---- Branch two: what is left after the counterparty's share. ----

    @Test
    fun `at the reserve, the balance is computed from the counterparty's side`() {
        val balance = ChannelBalance.spendableSatoshis(
            channel(
                channelValueSats = 200_000uL,
                outboundCapacityMsat = 0uL,
                inboundCapacityMsat = 197_000_000uL, // 197 000 sats
                counterpartyUnspendablePunishmentReserveSats = 1_000uL,
            ),
        )

        assertEquals(2_000L, balance)
    }

    /**
     * The port hazard this function exists for.
     *
     * On iOS these are `UInt64`s inside `Int(...)`, and Swift **traps** on
     * unsigned underflow — the app crashes. Kotlin's `ULong` wraps silently to
     * about 1.8e19, which then flows into the send screen as a spendable
     * maximum. Neither is acceptable on a balance read, so the arithmetic is done
     * in `Long` and floored. Flagged as a deliberate divergence in
     * [ChannelBalance]'s comment.
     */
    @Test
    fun `an impossible channel reads zero, not eighteen quintillion`() {
        val balance = ChannelBalance.spendableSatoshis(
            channel(
                channelValueSats = 100_000uL,
                outboundCapacityMsat = 0uL,
                inboundCapacityMsat = 100_000_000uL, // the whole channel
                counterpartyUnspendablePunishmentReserveSats = 1_000uL,
            ),
        )

        assertEquals(
            "channelValue - inbound - counterpartyReserve is negative here. In ULong " +
                "that is ${ULong.MAX_VALUE}; the user would be offered 184 billion " +
                "bitcoin to spend.",
            0L,
            balance,
        )
        assertTrue("A balance is never negative.", balance >= 0L)
    }

    // ---- Which channel is read. ----

    @Test
    fun `the active channel is the first one that is ready`() {
        val channels = listOf(
            channel(channelId = "pending", isChannelReady = false, outboundCapacityMsat = 1_000_000uL),
            channel(channelId = "ready-1", outboundCapacityMsat = 2_000_000uL),
            channel(channelId = "ready-2", outboundCapacityMsat = 4_000_000uL),
        )

        assertEquals("ready-1", channels.activeChannel()?.channelId)
        assertEquals(
            "iOS reads one channel, not the sum and not the largest. A wallet holding " +
                "two ready channels must not report 6 000 here.",
            2_000L,
            ChannelBalance.spendableSatoshis(channels),
        )
    }

    @Test
    fun `a channel that is not ready is not active`() {
        val channels = listOf(channel(isChannelReady = false, outboundCapacityMsat = 9_000_000uL))

        assertNull(channels.activeChannel())
        assertEquals(0L, ChannelBalance.spendableSatoshis(channels))
    }

    @Test
    fun `no channels is zero`() {
        assertEquals(0L, ChannelBalance.spendableSatoshis(emptyList()))
    }
}
