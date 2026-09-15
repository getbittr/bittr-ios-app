package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.ClosureReasonView
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.core.wallet.ldk.lightning.PaymentFailureReasonView
import org.lightningdevkit.ldknode.PaymentFailureReason
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
        is Event.ChannelPending -> NodeEvent.ChannelPending(event.channelId, event.fundingTxo.txid)
        is Event.PaymentFailed -> NodeEvent.PaymentFailed(event.paymentHash, event.reason?.let(::failureReason))
        else -> null
    }

    private fun failureReason(reason: PaymentFailureReason): PaymentFailureReasonView = when (reason) {
        PaymentFailureReason.RECIPIENT_REJECTED -> PaymentFailureReasonView.RecipientRejected
        PaymentFailureReason.USER_ABANDONED -> PaymentFailureReasonView.UserAbandoned
        PaymentFailureReason.RETRIES_EXHAUSTED -> PaymentFailureReasonView.RetriesExhausted
        PaymentFailureReason.PAYMENT_EXPIRED -> PaymentFailureReasonView.PaymentExpired
        PaymentFailureReason.ROUTE_NOT_FOUND -> PaymentFailureReasonView.RouteNotFound
        PaymentFailureReason.UNEXPECTED_ERROR -> PaymentFailureReasonView.UnexpectedError
        PaymentFailureReason.UNKNOWN_REQUIRED_FEATURES -> PaymentFailureReasonView.UnknownRequiredFeatures
        PaymentFailureReason.INVOICE_REQUEST_EXPIRED -> PaymentFailureReasonView.InvoiceRequestExpired
        PaymentFailureReason.INVOICE_REQUEST_REJECTED -> PaymentFailureReasonView.InvoiceRequestRejected
        PaymentFailureReason.BLINDED_PATH_CREATION_FAILED -> PaymentFailureReasonView.BlindedPathCreationFailed
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
