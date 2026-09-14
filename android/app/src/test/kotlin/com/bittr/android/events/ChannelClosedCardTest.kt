package com.bittr.android.events

import com.bittr.android.core.wallet.ldk.lightning.ClosureReasonView
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChannelClosedCardTest {

    @Test
    fun `a known reason is told after "We've been notified that"`() {
        val answer = ChannelClosedCard.answer(NodeEvent.ChannelClosed("c", ClosureReasonView.CounterpartyForceClosed))
        assertTrue(answer.startsWith("Your lightning connection has been closed. We've been notified that the counterparty force closed the connection.\n\n"))
        assertFalse(answer.contains("<reason>"))
    }

    @Test
    fun `a processing error shows its own text lower-cased`() {
        val answer = ChannelClosedCard.answer(NodeEvent.ChannelClosed("c", ClosureReasonView.ProcessingError, "Peer Sent Garbage"))
        assertTrue(answer.contains("We've been notified that peer sent garbage"))
    }

    @Test
    fun `no reason leaves the sentence out`() {
        val answer = ChannelClosedCard.answer(NodeEvent.ChannelClosed("c", reason = null))
        assertTrue(answer.startsWith("Your lightning connection has been closed.\n\n"))
    }
}
