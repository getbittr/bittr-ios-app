package com.bittr.android.core.wallet.ldk.lightning

/**
 * How much of a channel is the user's, in satoshis.
 *
 * Port of `LoadWalletData.swift:23–34` — eleven lines that produce
 * `satoshisLightning`, the Lightning half of the balance on the home screen and
 * the ceiling on every Lightning send (`SendLightning.swift:118`,
 * `SendViewController.swift:174`, `:280`).
 *
 * ```swift
 * if Int(activeChannel.outboundCapacityMsat/1000) != 0 {
 *     satoshisLightning += Int((activeChannel.outboundCapacityMsat / 1000)
 *         + (activeChannel.unspendablePunishmentReserve ?? 0))
 * } else {
 *     satoshisLightning += Int(activeChannel.channelValueSats
 *         - activeChannel.inboundCapacityMsat/1000
 *         - activeChannel.counterpartyUnspendablePunishmentReserve)
 * }
 * ```
 *
 * ## Why there are two branches
 *
 * `outboundCapacityMsat` is what LDK will actually let leave the channel, and it
 * excludes the holder's punishment reserve — the amount that must stay put so a
 * revoked commitment can be penalised. That reserve is still the user's money; it
 * just cannot be spent. So the first branch adds it back.
 *
 * When the channel balance has fallen *to or below* the reserve, LDK reports an
 * outbound capacity of zero and the reserve add-back would produce the reserve
 * itself, which overstates it. The second branch computes the same quantity from
 * the other side instead — total value, less what the counterparty holds, less
 * the counterparty's own reserve.
 *
 * ## The second branch is a subtraction, and that is the port hazard
 *
 * On iOS those are `UInt64`s and Swift **traps** on unsigned underflow: if
 * `inboundCapacityMsat/1000 + counterpartyUnspendablePunishmentReserve` ever
 * exceeds `channelValueSats`, the app crashes. Kotlin's `ULong` wraps instead,
 * silently, and the user's balance becomes something near 18 446 744 073 709 551 615
 * satoshis — roughly 184 billion bitcoin — which then flows into the send screen
 * as a spendable maximum.
 *
 * Neither behaviour is acceptable on a balance read, so this is a **deliberate,
 * non-cryptographic divergence from iOS**: the arithmetic is done in `Long` and
 * the result is floored at zero. It touches no key handling and no signing path;
 * it changes only what is displayed when ldk-node reports a combination iOS would
 * have crashed on. Flagged here rather than absorbed silently, per BIT-6's rule
 * about deviations.
 *
 * Whether the inputs can in fact reach that combination is a question about
 * ldk-node's invariants that no JVM test can settle. That is precisely the
 * argument for the floor: the failure is unbounded, the guard is one
 * `coerceAtLeast`, and the cost of being wrong in the other direction is a
 * balance that reads low by the rounding.
 *
 * Proved by `ChannelBalanceTest`.
 */
object ChannelBalance {

    /**
     * `satoshisLightning` for one channel.
     *
     * @return the user's share of [channel], never negative.
     */
    fun spendableSatoshis(channel: ChannelView): Long {
        // iOS divides first and compares the *satoshi* figure to zero, so a
        // channel holding 1–999 msat outbound takes the second branch. Kept:
        // that sub-satoshi case is exactly where the reserve add-back would
        // overstate, and matching the truncation keeps the two platforms on the
        // same branch for the same channel.
        val outboundSats = (channel.outboundCapacityMsat / 1000uL).toLong()

        if (outboundSats != 0L) {
            // `?: 0` is iOS's `?? 0` and it is safe here in a way the identical
            // expression is not in `OnchainDrainClamp`: a null reserve means LDK
            // reported no reserve on this channel, not "not read yet". There is
            // no third state to collapse.
            return outboundSats + (channel.unspendablePunishmentReserveSats?.toLong() ?: 0L)
        }

        // See the class comment. Long, not ULong, and floored.
        val counterpartyShareSats = (channel.inboundCapacityMsat / 1000uL).toLong() +
            channel.counterpartyUnspendablePunishmentReserveSats.toLong()

        return (channel.channelValueSats.toLong() - counterpartyShareSats).coerceAtLeast(0L)
    }

    /**
     * `satoshisLightning` for the wallet.
     *
     * iOS's `+=` inside `if let activeChannel` runs at most once — it reads the
     * *one* active channel, not every ready channel (`LoadWalletData.swift:23`).
     * Written as a sum over `activeChannel()?` rather than over the whole list so
     * that the single-channel assumption is visible here instead of hidden in a
     * `sumOf` that would quietly start counting two.
     */
    fun spendableSatoshis(channels: List<ChannelView>): Long =
        channels.activeChannel()?.let(::spendableSatoshis) ?: 0L
}
