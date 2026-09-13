package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.ManagedNodeFactory
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.node.NodeStartErrorClassifier
import com.bittr.android.core.wallet.ldk.node.NodeStartOutcome
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The host's ordering rules, each named by what it costs to get backwards.
 *
 * These run on the JVM against a real [NodeLifecycle] driven by fake nodes,
 * rather than against a mocked lifecycle, because half of what is being asserted
 * is the *interaction* between the two — that an `AlreadyRunning` outcome does
 * not relaunch a live pump, that a failed start discards the previous node's
 * runners along with the node. A double for the lifecycle would let those pass
 * by construction.
 *
 * The foreground service is a [RecordingPresence]. That is the whole reason
 * [ForegroundPresence] exists as an interface: `startForegroundService` is
 * unanswerable without a device, and the decisions worth proving —
 * promote-before-start, demote-only-on-a-definite-failure — are about *order*,
 * not about the platform call.
 */
class WalletNodeHostTest {

    /** Never retryable: every failure below should fail on the first attempt. */
    private val neverRetry = NodeStartErrorClassifier { false }

    private class Unretryable : Exception("start failed")

    private class FakeNode(
        private val log: MutableList<String>,
        private val onStart: () -> Unit = {},
    ) : ManagedNode {
        private var running = false
        var closes = 0
            private set

        override fun start() {
            onStart()
            log += "node started"
            running = true
        }

        override fun isRunning() = running

        override fun stop() {
            log += "node stopped"
            running = false
        }

        override fun close() {
            closes++
        }
    }

    private class RecordingPresence : ForegroundPresence {
        val events = mutableListOf<String>()
        val promotions get() = events.count { it == "promote" }
        val demotions get() = events.count { it == "demote" }

        override fun promote() {
            events += "promote"
        }

        override fun demote() {
            events += "demote"
        }
    }

    /** Runs until cancelled, recording each life. */
    private class ForeverRunner(
        override val name: String = "pump",
        private val log: MutableList<String>? = null,
    ) : NodeRunner {
        val lives = AtomicInteger()

        override suspend fun run() {
            lives.incrementAndGet()
            try {
                awaitCancellation()
            } finally {
                log?.add("runner stopped")
            }
        }
    }

    /** Stops on its own, the way `EventPump` does on `ReadFailed`. */
    private class SelfStoppingRunner(override val name: String = "pump") : NodeRunner {
        val lives = AtomicInteger()

        override suspend fun run() {
            lives.incrementAndGet()
        }
    }

    private fun lifecycleOf(
        scope: CoroutineScope,
        factory: ManagedNodeFactory,
        classifier: NodeStartErrorClassifier = neverRetry,
        wait: suspend (Long) -> Unit = {},
    ) = NodeLifecycle(
        scope = scope,
        factory = factory,
        classifier = classifier,
        elapsedRealtimeMillis = { 0L },
        wait = wait,
    )

    /**
     * **The promotion happens before the start, not after it.**
     *
     * A node start is tens of seconds of network round trips. The case this
     * exists for is the user backgrounding the app one second into it — and a
     * host that promoted once the node was up would already have missed it,
     * because by then the process has been a cached process for the whole start.
     */
    @Test
    fun `the process is held up before the node start begins, not after`() =
        runTest(UnconfinedTestDispatcher()) {
            val log = mutableListOf<String>()
            val presence = RecordingPresence()
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(this, { FakeNode(log) { log += "promote?" } }),
                presence = object : ForegroundPresence {
                    override fun promote() {
                        log += "promoted"
                        presence.promote()
                    }

                    override fun demote() {
                        log += "demoted"
                        presence.demote()
                    }
                },
            )

            host.start()

            assertEquals(listOf("promoted", "promote?", "node started"), log)
        }

    /**
     * **A start that failed leaves nothing holding the process up.**
     *
     * The notification is not decoration: it is the user's only signal that the
     * wallet is running. One that outlives a failed start is a permanent,
     * undismissable claim that something is happening when nothing is.
     */
    @Test
    fun `a failed start releases the process`() = runTest(UnconfinedTestDispatcher()) {
        val presence = RecordingPresence()
        val host = WalletNodeHost(
            scope = this,
            lifecycle = lifecycleOf(
                this,
                { FakeNode(mutableListOf()) { throw Unretryable() } },
            ),
            presence = presence,
        )

        val result = host.start()

        assertEquals(NodeStartOutcome.Failed, result.outcome)
        assertEquals(1, presence.promotions)
        assertEquals(1, presence.demotions)
    }

    /**
     * **A caller going away is not a failed start, and must not release the
     * process.**
     *
     * This is the case `NodeStartGate` was built for, arriving one layer up. The
     * start runs in the host's scope; a rotation cancels the *caller*, and the
     * node keeps coming up. A host that demoted on that cancellation would drop
     * the foreground protection out from under a start that is still running —
     * turning the rotation into the freeze the service exists to prevent.
     */
    @Test
    fun `a cancelled caller does not release the process the start still needs`() =
        runTest(UnconfinedTestDispatcher()) {
            val presence = RecordingPresence()
            val released = CompletableDeferred<Unit>()
            val attempts = AtomicInteger()
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(
                    scope = this,
                    factory = {
                        FakeNode(mutableListOf()) {
                            // Fails once, so the retry schedule is entered and
                            // the start is still in flight when the caller goes.
                            if (attempts.incrementAndGet() == 1) throw Unretryable()
                        }
                    },
                    classifier = { true },
                    wait = { released.await() },
                ),
                presence = presence,
            )

            val caller = launch { host.start() }
            assertTrue("the start should be in flight", caller.isActive)

            caller.cancel()
            caller.join()

            assertEquals(1, presence.promotions)
            assertEquals(
                "the start is still running in the host's scope; nothing should have " +
                    "been released",
                0,
                presence.demotions,
            )

            released.complete(Unit)
        }

    /**
     * **A new node means new runners.**
     *
     * `EventPump` says it: it is deliberately terminal on a read failure, and
     * the host restarts it when the host restarts the node. Leaving the old
     * pump attached would point it at a `Node` that `NodeLifecycle.buildAndStart`
     * has already closed — and two pumps over one queue is worse: both read, one
     * acknowledges, and an event the other was still handling is dropped.
     */
    @Test
    fun `every node start gets its own runners`() = runTest(UnconfinedTestDispatcher()) {
        val runner = ForeverRunner()
        val host = WalletNodeHost(
            scope = this,
            lifecycle = lifecycleOf(this, { FakeNode(mutableListOf()) }),
            presence = ForegroundPresence.None,
            runners = listOf(runner),
        )

        host.start()
        assertEquals(1, runner.lives.get())

        host.stop()
        host.start()
        assertEquals("the second node should have got its own pump", 2, runner.lives.get())

        host.stop()
    }

    /**
     * **A start that failed starts no runners, and stops the ones it had.**
     *
     * The second half is the one that is easy to miss. `buildAndStart` discards
     * the node it was holding *before* it builds a replacement, so a failed
     * start leaves the previous node closed — and its pump reading a freed
     * handle. That is the `ReadFailed` path, reached by a route nobody wrote.
     */
    @Test
    fun `a failed start leaves no runner attached to a node that is gone`() =
        runTest(UnconfinedTestDispatcher()) {
            val log = mutableListOf<String>()
            val runner = ForeverRunner(log = log)
            val attempts = AtomicInteger()
            var nodeAlive = true
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(this, {
                    if (attempts.incrementAndGet() == 1) {
                        object : ManagedNode {
                            override fun start() = Unit
                            override fun isRunning() = nodeAlive
                            override fun stop() = Unit
                            override fun close() = Unit
                        }
                    } else {
                        FakeNode(log) { throw Unretryable() }
                    }
                }),
                presence = ForegroundPresence.None,
                runners = listOf(runner),
            )

            host.start()
            assertEquals(1, runner.lives.get())

            // The node died without anyone stopping it — an ldk-node internal
            // failure, a service restart finding a stale object. Nobody called
            // `stop`, so the pump for it is still running. The next start finds
            // it not running, discards it, and fails to build a replacement.
            nodeAlive = false
            log.clear()
            val result = host.start()

            assertEquals(NodeStartOutcome.Failed, result.outcome)
            assertEquals("no runner should have been launched", 1, runner.lives.get())
            assertTrue(
                "the pump for the discarded node is still reading a handle " +
                    "`buildAndStart` has closed",
                "runner stopped" in log,
            )
        }

    /**
     * **A dead pump is revived by the next start, even when the node is already
     * up.**
     *
     * `EventPumpStop.ReadFailed` is terminal on purpose — spinning on a failing
     * FFI read burns the battery — so nothing inside the pump brings it back.
     * Without this branch, a caller who asks for a working wallet and gets
     * `AlreadyRunning` is handed a node whose event loop died silently: payments
     * arrive and nothing notices.
     */
    @Test
    fun `a start against a live node revives a runner that stopped`() =
        runTest(UnconfinedTestDispatcher()) {
            val runner = SelfStoppingRunner()
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(this, { FakeNode(mutableListOf()) }),
                presence = ForegroundPresence.None,
                runners = listOf(runner),
            )

            assertEquals(NodeStartOutcome.Started, host.start().outcome)
            assertEquals(1, runner.lives.get())

            val second = host.start()

            assertEquals(NodeStartOutcome.AlreadyRunning, second.outcome)
            assertEquals("the stopped runner should have been given another life", 2, runner.lives.get())

            host.stop()
        }

    /**
     * **Runners leave the FFI before the node does.**
     *
     * A pump cancelled after the node stops may be inside `eventHandled()` when
     * the handle under it is freed. Cancelling is not enough either — the host
     * joins, so "stopped" means the runner has finished unwinding rather than
     * has been asked to.
     */
    @Test
    fun `stop takes the runners down before the node`() = runTest(UnconfinedTestDispatcher()) {
        val log = mutableListOf<String>()
        val host = WalletNodeHost(
            scope = this,
            lifecycle = lifecycleOf(this, { FakeNode(log) }),
            presence = ForegroundPresence.None,
            runners = listOf(ForeverRunner(log = log)),
        )

        host.start()
        log.clear()
        host.stop()

        assertEquals(listOf("runner stopped", "node stopped"), log)
    }

    /**
     * **A node stop that throws still releases the process.**
     *
     * `NodeLifecycle.stop` clears its field before stopping, so after a throw
     * the wallet already believes it has no node. A host that skipped the demote
     * on that path would leave a foreground service running forever, with a
     * notification the user cannot dismiss and nothing at all behind it.
     */
    @Test
    fun `a stop that throws still releases the process`() = runTest(UnconfinedTestDispatcher()) {
        val presence = RecordingPresence()
        val host = WalletNodeHost(
            scope = this,
            lifecycle = lifecycleOf(this, {
                object : ManagedNode {
                    override fun start() = Unit
                    override fun isRunning() = true
                    override fun stop() = throw IllegalStateException("persistence failed")
                    override fun close() = Unit
                }
            }),
            presence = presence,
        )

        host.start()
        runCatching { host.stop() }

        assertEquals(1, presence.demotions)
    }

    /**
     * **`withWalletDown` runs its block with nothing running, and leaves it that
     * way.**
     *
     * This is `removeWallet`'s ordering. A wipe that ran beside a live node
     * would delete the seed out from under the thing holding the state
     * directory open.
     */
    @Test
    fun `withWalletDown erases with the node down and does not bring it back`() =
        runTest(UnconfinedTestDispatcher()) {
            val runner = ForeverRunner()
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(this, { FakeNode(mutableListOf()) }),
                presence = ForegroundPresence.None,
                runners = listOf(runner),
            )

            host.start()
            assertTrue(host.isRunning)

            var sawRunningNode = true
            host.withWalletDown { sawRunningNode = host.isRunning }

            assertFalse("the block must not see a node", sawRunningNode)
            assertFalse("the wallet stays down afterwards", host.isRunning)
        }

    /**
     * **A removal cannot land in the middle of a start.**
     *
     * The expensive case, and the reason every entry point takes the mutex. A
     * wipe that erased the seed between `LdkNodeFactory.build()` and
     * `Node.start()` produces a node running against key material that no longer
     * exists — and, on the next launch, LDK state whose discriminator matches
     * nothing.
     */
    @Test
    fun `withWalletDown waits for a start already in flight`() =
        runTest(UnconfinedTestDispatcher()) {
            val released = CompletableDeferred<Unit>()
            val attempts = AtomicInteger()
            val host = WalletNodeHost(
                scope = this,
                lifecycle = lifecycleOf(
                    scope = this,
                    factory = {
                        FakeNode(mutableListOf()) {
                            if (attempts.incrementAndGet() == 1) throw Unretryable()
                        }
                    },
                    classifier = { true },
                    wait = { released.await() },
                ),
                presence = ForegroundPresence.None,
            )

            val starting = launch { host.start() }
            var wiped = false
            val removing = launch { host.withWalletDown { wiped = true } }

            assertFalse("the wipe must not run while a start is in flight", wiped)

            released.complete(Unit)
            starting.join()
            removing.join()

            assertTrue(wiped)
            assertFalse(host.isRunning)
        }
}
