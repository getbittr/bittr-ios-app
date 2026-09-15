package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.ClosureReasonView
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import org.lightningdevkit.ldknode.ClosureReason
import org.lightningdevkit.ldknode.Event

/** ldk-node's [Event] to the [NodeEvent]s the UI reacts to; null for everything else. */
object LdkNodeEvents {

    fun of(event: Event): NodeEvent? = when (event) {
        is Event.ChannelClosed -> NodeEvent.ChannelClosed(
            channelId = event.channelId,
            reason = event.reason?.let(::reason),
            processingError = (event.reason as? ClosureReason.ProcessingError)?.err,
        )
        is Event.PaymentReceived -> NodeEvent.PaymentReceived(event.paymentHash, event.amountMsat.toLong())
        is Event.PaymentSuccessful -> NodeEvent.PaymentSuccessful(event.paymentHash, event.feePaidMsat?.toLong())
        else -> null
    }

    private fun reason(reason: ClosureReason): ClosureReasonView = when (reason) {
        is ClosureReason.CounterpartyForceClosed -> ClosureReasonView.CounterpartyForceClosed
        is ClosureReason.HolderForceClosed -> ClosureReasonView.HolderForceClosed
        is ClosureReason.LegacyCooperativeClosure -> ClosureReasonView.LegacyCooperativeClosure
        is ClosureReason.CounterpartyInitiatedCooperativeClosure -> ClosureReasonView.CounterpartyInitiatedCooperativeClosure
        is ClosureReason.LocallyInitiatedCooperativeClosure -> ClosureReasonView.LocallyInitiatedCooperativeClosure
        is ClosureReason.CommitmentTxConfirmed -> ClosureReasonView.CommitmentTxConfirmed
        is ClosureReason.FundingTimedOut -> ClosureReasonView.FundingTimedOut
        is ClosureReason.ProcessingError -> ClosureReasonView.ProcessingError
        is ClosureReason.DisconnectedPeer -> ClosureReasonView.DisconnectedPeer
        is ClosureReason.OutdatedChannelManager -> ClosureReasonView.OutdatedChannelManager
        is ClosureReason.CounterpartyCoopClosedUnfundedChannel -> ClosureReasonView.CounterpartyCoopClosedUnfundedChannel
        is ClosureReason.LocallyCoopClosedUnfundedChannel -> ClosureReasonView.LocallyCoopClosedUnfundedChannel
        is ClosureReason.FundingBatchClosure -> ClosureReasonView.FundingBatchClosure
        is ClosureReason.HtlCsTimedOut -> ClosureReasonView.HtlcsTimedOut
        is ClosureReason.PeerFeerateTooLow -> ClosureReasonView.PeerFeerateTooLow
    }
}
