package com.bittr.android.core.wallet.ldk.node

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The three things [NodeStartGate] exists to guarantee, each with the failure it
 * prevents named.
 *
 * 1. **One start.** Two node objects over one storage directory is two writers
 *    over one SQLite file holding channel state. This is the fund-loss shape,
 *    not a tidiness concern.
 * 2. **Every caller gets an outcome.** iOS's own comment calls the alternative
 *    "a silent dead end"; the user-visible form is a spinner that never clears,
 *    and on the post-lockout path there is no other way forward.
 * 3. **A caller going away does not take the start with it.** The Android-only
 *    one. `lifecycleScope` and `viewModelScope` are cancelled by rotation and by
 *    backgrounding, both of which happen *during* a node start routinely.
 */
class NodeStartGateTest {

    @Test
    fun `a node already running is not started again`() = runTest(UnconfinedTestDispatcher()) {
        val starts = AtomicInteger()
        val gate = NodeStartGate(
            scope = backgroundScope,
            isRunning = { true },
            start = { starts.incrementAndGet(); true },
        )

        val result = gate.startOnce()

        assertEquals(NodeStartOutcome.AlreadyRunning, result.outcome)
        assertEquals("The node was up; nothing should have been started.", 0, starts.get())
        assertFalse(result.ownedStart)
    }

    @Test
    fun `a caller that loses the race still gets the outcome`() =
        runTest(UnconfinedTestDispatcher()) {
            val release = CompletableDeferred<Unit>()
            val starts = AtomicInteger()
            val gate = NodeStartGate(
                scope = backgroundScope,
                isRunning = { false },
                start = { starts.incrementAndGet(); release.await(); true },
            )

            val owner = async { gate.startOnce() }
            val attached = async { gate.startOnce() }
            release.complete(Unit)

            val results = listOf(owner, attached).awaitAll()

            assertEquals("Exactly one start for two callers.", 1, starts.get())
            results.forEach { assertEquals(NodeStartOutcome.Started, it.outcome) }
            assertEquals(
                "Exactly one caller should report owning the start.",
                1,
                results.count { it.ownedStart },
            )
        }

    @Test
    fun `a failure reaches every caller, with the cause`() =
        runTest(UnconfinedTestDispatcher()) {
            val release = CompletableDeferred<Unit>()
            val failure = IllegalStateException("chain source unreachable")
            val gate = NodeStartGate(
                scope = backgroundScope,
                isRunning = { false },
                start = { release.await(); throw failure },
            )

            val owner = async { gate.startOnce() }
            val attached = async { gate.startOnce() }
            release.complete(Unit)
            val results = listOf(owner, attached).awaitAll()

            results.forEach {
                assertEquals(NodeStartOutcome.Failed, it.outcome)
                assertFalse("A failed start is not usable.", it.isUsable)
                assertSame(
                    "The cause has to survive the hop to an attached caller — it is what " +
                        "the retry decision and the Sentry report are made from.",
                    failure,
                    it.cause,
                )
            }
        }

    @Test
    fun `a start that returns false is a failure, not a success without a cause`() =
        runTest(UnconfinedTestDispatcher()) {
            val gate = NodeStartGate(
                scope = backgroundScope,
                isRunning = { false },
                start = { false },
            )

            val result = gate.startOnce()

            assertEquals(NodeStartOutcome.Failed, result.outcome)
            assertNull(result.cause)
        }

    @Test
    fun `the gate reopens once a start has finished`() = runTest(UnconfinedTestDispatcher()) {
        // `invokeOnCompletion` clears the in-flight slot. If it did not, the
        // second call would attach to the finished first start and report
        // success without the node being up — which, after a stop() or a reset,
        // is the app believing it has a node it does not have.
        val starts = AtomicInteger()
        val gate = NodeStartGate(
            scope = backgroundScope,
            isRunning = { false },
            start = { starts.incrementAndGet(); true },
        )

        assertEquals(NodeStartOutcome.Started, gate.startOnce().outcome)
        yield()
        assertEquals(NodeStartOutcome.Started, gate.startOnce().outcome)

        assertEquals("Two sequential calls, two starts.", 2, starts.get())
    }

    @Test
    fun `cancelling an attached caller does not cancel the start`() =
        runTest(UnconfinedTestDispatcher()) {
            val release = CompletableDeferred<Unit>()
            val gate = NodeStartGate(
                scope = backgroundScope,
                isRunning = { false },
                start = { release.await(); true },
            )

            val owner = async { gate.startOnce() }
            val attachedThenGone = launch { gate.startOnce() }
            attachedThenGone.cancelAndJoin()

            release.complete(Unit)

            assertEquals(
                "The owner's start must survive an attached caller walking away.",
                NodeStartOutcome.Started,
                owner.await().outcome,
            )
        }

    @Test
    fun `cancelling the owner does not cancel the start`() = runTest(UnconfinedTestDispatcher()) {
        // The Android-specific case, and the reason NodeStartGate takes a scope
        // rather than using the caller's. The owner here is a screen: the user
        // rotates the device, or backgrounds the app, mid-start. If the start
        // died with it, every other caller attached to that start would be left
        // awaiting a cancelled Deferred — and the node would be half-built over
        // live channel state.
        val release = CompletableDeferred<Unit>()
        val startCompleted = CompletableDeferred<Unit>()
        val gate = NodeStartGate(
            scope = backgroundScope,
            isRunning = { false },
            start = { release.await(); startCompleted.complete(Unit); true },
        )

        val owner = launch { gate.startOnce() }
        val survivor = async { gate.startOnce() }
        owner.cancelAndJoin()

        release.complete(Unit)

        assertEquals(NodeStartOutcome.Started, survivor.await().outcome)
        assertTrue("The start itself ran to completion.", startCompleted.isCompleted)
    }

    @Test
    fun `no two starts ever overlap, under real parallelism`() = runBlocking {
        // The tests above run on a single test thread, where a broken lock still
        // looks correct. This one is the lock's actual test: 64 callers arriving
        // on the default dispatcher's thread pool at once, which is the real
        // shape — a foreground screen, a push wake and a sync worker can all
        // reach the wallet within the same millisecond.
        //
        // The invariant asserted is *overlap*, not a start count. Callers that
        // arrive after a start has finished are entitled to a fresh one (see
        // `the gate reopens once a start has finished`), so "exactly one start
        // for 64 callers" would be a statement about timing rather than about
        // the lock. Two starts *at the same time* is the thing that must never
        // happen: two node objects over one SQLite file holding channel state.
        val concurrent = AtomicInteger()
        val highWaterMark = AtomicInteger()

        val gate = NodeStartGate(
            scope = this,
            isRunning = { false },
            start = {
                val now = concurrent.incrementAndGet()
                highWaterMark.getAndUpdate { maxOf(it, now) }
                yield()
                concurrent.decrementAndGet()
                true
            },
        )

        val results = (1..64).map { async(Dispatchers.Default) { gate.startOnce() } }.awaitAll()

        assertEquals(
            "Two node starts were in flight at the same time. Each of them builds a " +
                "Node over the same storage directory, so this is two writers over the " +
                "channel state — the fund-loss shape this gate exists to prevent.",
            1,
            highWaterMark.get(),
        )
        assertEquals(
            "Every caller has to come back with the outcome.",
            64,
            results.count { it.outcome == NodeStartOutcome.Started },
        )
        // Deliberately no assertion on the *number* of starts: that is a
        // statement about thread scheduling, and it is already proved
        // deterministically by `a caller that loses the race still gets the
        // outcome`. A flaky guard on a fund-critical invariant gets muted.
    }
}
