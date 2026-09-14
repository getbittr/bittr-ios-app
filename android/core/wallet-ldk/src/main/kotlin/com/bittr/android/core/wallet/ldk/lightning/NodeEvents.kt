package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * A node event the UI reacts to, with no ldk-node type in it.
 *
 * Only what a screen needs today. iOS handles every event in `CoreViewController`'s event
 * listener (`HandlePaymentNotification.swift`); the rest of those branches are still the event
 * pump's log line on Android.
 */
sealed interface NodeEvent {

    /**
     * `Event.channelClosed` — iOS launches the "closed lightning connection" Question card.
     *
     * @property reason null when ldk-node gave none.
     * @property processingError `ClosureReason.processingError(err:)`'s text, which iOS shows
     *   lower-cased in place of a fixed sentence.
     */
    data class ChannelClosed(
        val channelId: String,
        val reason: ClosureReasonView?,
        val processingError: String? = null,
    ) : NodeEvent
}

/** `ClosureReason`, one case per sentence iOS has for it. */
enum class ClosureReasonView {
    CounterpartyForceClosed,
    HolderForceClosed,
    LegacyCooperativeClosure,
    CounterpartyInitiatedCooperativeClosure,
    LocallyInitiatedCooperativeClosure,
    CommitmentTxConfirmed,
    FundingTimedOut,
    ProcessingError,
    DisconnectedPeer,
    OutdatedChannelManager,
    CounterpartyCoopClosedUnfundedChannel,
    LocallyCoopClosedUnfundedChannel,
    FundingBatchClosure,
    HtlcsTimedOut,
    PeerFeerateTooLow,
}

/**
 * Where the event pump hands UI-relevant events, and where the app listens.
 *
 * One instance per wallet composition. A buffer rather than a replay: an event nobody was
 * listening for when it happened has already been logged and recorded in the event ledger, and
 * replaying a "connection closed" card to the next screen that subscribes would show it twice.
 */
class NodeEvents {

    private val _events = MutableSharedFlow<NodeEvent>(extraBufferCapacity = 16)
    val events: SharedFlow<NodeEvent> = _events.asSharedFlow()

    fun emit(event: NodeEvent) {
        _events.tryEmit(event)
    }
}
