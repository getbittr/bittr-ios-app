package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The event loop's acknowledgement order, which is the durability contract.
 *
 * > An event consumed but not acknowledged is replayed. An event acknowledged
 * > but not persisted is lost.
 *
 * Every test below is one half of that sentence. The fake queue models ldk-node
 * the way ldk-node actually behaves — the head of the queue stays put until
 * `eventHandled()` is called — so "replayed" is something the test can observe
 * rather than something the assertions have to take on trust.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EventPumpTest {

    /**
     * ldk-node's event queue, as a fake that keeps the replay semantics.
     *
     * A queue that popped on read would make every test here pass without
     * proving anything: the pump would look correct no matter where the
     * acknowledgement went. So [nextEvent] *peeks*, and only [eventHandled]
     * advances.
     */
    private class FakeQueue(
        events: List<String>,
        /** Null at the end of the list means "the node has gone", not "wait forever". */
        private val endsWithNodeGone: Boolean = true,
    ) : EventPumpPort<String> {

        private val queue = ArrayDeque(events)
        val reads = mutableListOf<String>()
        var acknowledgements = 0
        var acknowledgeFailure: Exception? = null
        var nodeGoneAfter: Int? = null

        /** Events still queued. What a restarted node would deliver again. */
        val remaining: List<String> get() = queue.toList()

        override suspend fun nextEvent(): String? {
            if (nodeGoneAfter != null && reads.size >= nodeGoneAfter!!) return null
            val head = queue.firstOrNull()
                ?: return if (endsWithNodeGone) null else error("unexpected read")
            reads += head
            return head
        }

        override fun eventHandled() {
            acknowledgeFailure?.let { throw it }
            queue.removeFirstOrNull()
            acknowledgements++
        }
    }

    private class RecordingLedger(
        /** Events the ledger claims to have seen before — the other reader's writes. */
        seen: Set<String> = emptySet(),
    ) : EventLedger<String> {
        private val handled = seen.toMutableSet()
        val recorded = mutableListOf<String>()

        override fun hasHandled(event: String) = event in handled

        override fun recordHandled(event: String) {
            handled += event
            recorded += event
        }
    }

    @Test
    fun `every event is handled once, in order, and acknowledged after`() = runTest {
        val queue = FakeQueue(listOf("a", "b", "c"))
        val ledger = RecordingLedger()
        val handled = mutableListOf<String>()

        val outcome = EventPump(queue, ledger, { handled += it }).run()

        assertEquals(listOf("a", "b", "c"), handled)
        assertEquals(3, outcome.acknowledged)
        assertEquals(EventPumpStop.NodeGone, outcome.stop)
        assertEquals("Nothing left to replay.", emptyList<String>(), queue.remaining)
    }

    /**
     * Point 2 of [EventPump]'s comment, and a deliberate divergence from iOS's
     * unconditional `try? node.eventHandled()`.
     *
     * The handler failed, so the app did not record the payment. Acknowledging
     * anyway would drop the event from ldk-node's queue and the payment would
     * never be seen again — the "lost" branch of the contract. Replay is the
     * recoverable direction.
     */
    @Test
    fun `a handler that throws does not acknowledge, so the event is replayed`() = runTest {
        val queue = FakeQueue(listOf("payment-received"))
        val failure = IllegalStateException("cache write failed")

        val thrown = runCatching {
            EventPump<String>(queue, RecordingLedger(), { throw failure }).run()
        }.exceptionOrNull()

        assertSame(failure, thrown)
        assertEquals("Never acknowledged.", 0, queue.acknowledgements)
        assertEquals(
            "Still at the head of ldk-node's queue, so the next start delivers it again.",
            listOf("payment-received"),
            queue.remaining,
        )
    }

    /**
     * Point 3. `eventHandled()` throws when the node is on its way down, which is
     * exactly when the loop is about to exit anyway. iOS's `try?` is right and is
     * kept; the consequence is a replay, which the contract permits.
     */
    @Test
    fun `a failed acknowledgement is swallowed and the loop continues`() = runTest {
        val queue = FakeQueue(listOf("a", "b"))
        queue.acknowledgeFailure = IllegalStateException("node stopping")
        val swallowed = mutableListOf<Throwable>()
        val handled = mutableListOf<String>()
        queue.nodeGoneAfter = 2

        val outcome = EventPump(
            port = queue,
            ledger = RecordingLedger(),
            handler = { handled += it },
            onAcknowledgeFailure = { swallowed += it },
        ).run()

        assertEquals(EventPumpStop.NodeGone, outcome.stop)
        assertEquals(0, outcome.acknowledged)
        assertEquals(2, swallowed.size)
        assertTrue("Both events stay queued for replay.", queue.remaining.size == 2)
    }

    /**
     * Point 4: the ledger is written *before* the handler, matching iOS
     * (`HandlePaymentNotification.swift:313`).
     *
     * It looks backwards until you notice what the ledger is for. It is not the
     * replay guarantee — ldk-node's queue is — it is what stops the *user* being
     * shown the same payment twice when this loop and the push-notification
     * service extension race for the same event. A ledger written after a handler
     * that posts a notification cannot do that job.
     */
    @Test
    fun `the ledger is recorded before the handler runs`() = runTest {
        val queue = FakeQueue(listOf("payment"))
        val ledger = RecordingLedger()
        val order = mutableListOf<String>()

        EventPump<String>(
            port = queue,
            ledger = object : EventLedger<String> {
                override fun hasHandled(event: String) = ledger.hasHandled(event)
                override fun recordHandled(event: String) {
                    order += "record"
                    ledger.recordHandled(event)
                }
            },
            handler = { order += "handle" },
        ).run()

        assertEquals(listOf("record", "handle"), order)
    }

    /**
     * An event the other reader already showed is acknowledged without being
     * handled again — iOS's `if hasHandledEvent(...) { log } else { ... }`, which
     * falls through to `eventHandled()` either way.
     */
    @Test
    fun `an already-handled event is acknowledged but not handled twice`() = runTest {
        val queue = FakeQueue(listOf("seen", "fresh"))
        val handled = mutableListOf<String>()

        val outcome = EventPump(
            port = queue,
            ledger = RecordingLedger(seen = setOf("seen")),
            handler = { handled += it },
        ).run()

        assertEquals(listOf("fresh"), handled)
        assertEquals(
            "Both are acknowledged. A duplicate that is never acked is a queue that " +
                "never drains.",
            2,
            outcome.acknowledged,
        )
    }

    @Test
    fun `a read failure stops the pump rather than spinning on it`() = runTest {
        val failure = IllegalStateException("ffi read failed")
        val port = object : EventPumpPort<String> {
            var reads = 0
            override suspend fun nextEvent(): String {
                reads++
                throw failure
            }
            override fun eventHandled() = error("not reached")
        }

        val outcome = EventPump<String>(port, RecordingLedger(), { }).run()

        assertEquals(EventPumpStop.ReadFailed, outcome.stop)
        assertSame(failure, outcome.cause)
        assertEquals(
            "Once, not in a loop. Spinning on a failing FFI read burns the battery " +
                "until the user notices.",
            1,
            port.reads,
        )
    }

    /**
     * iOS's `guard let node = self.ldkNode else { return }`
     * (`BitcoinManager.swift:709`) — a wipe nulled the node while the loop was
     * suspended inside the read.
     */
    @Test
    fun `the node going away is an ordinary stop`() = runTest {
        val queue = FakeQueue(listOf("a"))
        queue.nodeGoneAfter = 0

        val outcome = EventPump<String>(queue, RecordingLedger(), { }).run()

        assertEquals(EventPumpStop.NodeGone, outcome.stop)
        assertEquals(0, outcome.acknowledged)
    }

    /**
     * Cancellation between the read and the acknowledgement is the case Android
     * has and iOS does not: the service is being torn down, or the process is
     * going. The event must stay queued.
     */
    @Test
    fun `cancellation mid-handle leaves the event queued for replay`() = runTest {
        val queue = FakeQueue(listOf("a"), endsWithNodeGone = false)
        val insideHandler = CompletableDeferred<Unit>()
        val blockForever = CompletableDeferred<Unit>()

        val pump = async {
            EventPump<String>(
                port = queue,
                ledger = RecordingLedger(),
                handler = {
                    insideHandler.complete(Unit)
                    blockForever.await()
                },
            ).run()
        }

        insideHandler.await()
        pump.cancel()

        assertEquals("Never acknowledged.", 0, queue.acknowledgements)
        assertEquals(listOf("a"), queue.remaining)
        assertFalse(
            "A cancelled pump does not return an outcome; it propagates the " +
                "cancellation, so nothing downstream mistakes it for a clean stop.",
            pump.isCompleted && !pump.isCancelled,
        )
    }
}
