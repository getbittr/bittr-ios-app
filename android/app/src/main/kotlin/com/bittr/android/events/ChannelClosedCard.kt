package com.bittr.android.events

import androidx.lifecycle.ViewModel
import com.bittr.android.core.wallet.ldk.lightning.ClosureReasonView
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.di.WalletComposition
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharedFlow

/** How the navigation graph reaches the node's events. */
@HiltViewModel
class NodeEventsViewModel @Inject constructor(composition: WalletComposition) : ViewModel() {
    val events: SharedFlow<NodeEvent> = composition.nodeEvents.events
}

/**
 * The "closed lightning connection" Question card — the `.channelClosed` branch of iOS's event
 * handler (`HandlePaymentNotification.swift:330–366`), copy word for word.
 */
object ChannelClosedCard {

    /** `closedlightningchannel`. */
    const val TITLE = "closed lightning connection"

    /** `closedlightningchannel2`, before `<reason>` is filled in. */
    private const val ANSWER =
        "Your lightning connection has been closed.<reason>\n\nAny funds that were in this connection are " +
            "deposited into your bitcoin wallet.\n\nTo open a new connection with bittr, buy bitcoin worth up " +
            "to 100 CHF/EUR. Check your wallet's Buy section or getbittr.com for all information."

    /** `closedlightningchannel3`. */
    private const val NOTIFIED = " We've been notified that "

    fun answer(event: NodeEvent.ChannelClosed): String {
        val why = when (event.reason) {
            null -> null
            ClosureReasonView.ProcessingError -> event.processingError?.lowercase()
            else -> REASONS[event.reason]
        }
        return ANSWER.replace("<reason>", why?.let { NOTIFIED + it } ?: "")
    }

    private val REASONS = mapOf(
        ClosureReasonView.CounterpartyForceClosed to "the counterparty force closed the connection.",
        ClosureReasonView.HolderForceClosed to "you force closed the connection.",
        ClosureReasonView.LegacyCooperativeClosure to "the connection was closed cooperatively (legacy).",
        ClosureReasonView.CounterpartyInitiatedCooperativeClosure to
            "the connection was closed cooperatively (counterparty-iniated).",
        ClosureReasonView.LocallyInitiatedCooperativeClosure to "the connection was closed cooperatively (locally).",
        ClosureReasonView.CommitmentTxConfirmed to "the commitment transaction was confirmed.",
        ClosureReasonView.FundingTimedOut to "the funding of the connection timed out.",
        ClosureReasonView.DisconnectedPeer to "a peer connection could not be established.",
        ClosureReasonView.OutdatedChannelManager to "the channel manager was outdated.",
        ClosureReasonView.CounterpartyCoopClosedUnfundedChannel to
            "the unfunded connection was cooperatively closed (counterparty-initiated).",
        ClosureReasonView.LocallyCoopClosedUnfundedChannel to
            "the connection was closed cooperatively (locally, unfunded channel).",
        ClosureReasonView.FundingBatchClosure to "the funding batch was closed.",
        ClosureReasonView.HtlcsTimedOut to "the hashed timelock contracts timed out.",
        ClosureReasonView.PeerFeerateTooLow to "the proposed fee rate was too low.",
    )
}
