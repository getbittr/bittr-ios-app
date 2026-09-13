package com.bittr.android.core.wallet.ldk.node

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Custody of the node object: who holds it, when it is published, and when it is
 * destroyed.
 *
 * `BitcoinManager` keeps this as `var ldkNode: Node?` and gets three properties
 * free that Android does not give free — see [NodeLifecycle]'s class comment.
 * Each test below is one of them, named by the failure it prevents rather than
 * by the method it calls.
 *
 * The reason these run on the JVM at all is [ManagedNode]: the decision is
 * written against four methods, so a fake supplies them and no native library is
 * loaded. `LdkManagedNode` is the binding, and it is four forwarding methods
 * precisely so there is nothing left in it to get wrong without a device.
 */
class NodeLifecycleTest {

    /** Retryable, so the retry schedule is exercised where a test wants it. */
    private class Connectivity : Exception("connection failed")

    private val retryConnectivity = NodeStartErrorClassifier { it is Connectivity }

    /**
     * A node whose start behaviour the test dictates, recording what was done
     * to it.
     */
    private class FakeNode(
        private val startBehaviour: (attempt: Int) -> Unit = {},
        /** What `isRunning()` reports, independent of whether start threw. */
        private var running: Boolean = false,
        private val isRunningBehaviour: (() -> Boolean)? = null,
    ) : ManagedNode {

        val startAttempts = AtomicInteger()
        var stops = 0
            private set
        var closes = 0
            private set

        override fun start() {
            startBehaviour(startAttempts.incrementAndGet())
            running = true
        }

        override fun isRunning(): Boolean = isRunningBehaviour?.invoke() ?: running

        override fun stop() {
            stops++
            running = false
        }

        override fun close() {
            closes++
        }
    }

    private fun lifecycle(
        scope: kotlinx.coroutines.CoroutineScope,
        factory: ManagedNodeFactory,
        classifier: NodeStartErrorClassifier = retryConnectivity,
        clock: () -> Long = { 0L },
    ) = NodeLifecycle(
        scope = scope,
        factory = factory,
        classifier = classifier,
        elapsedRealtimeMillis = clock,
        // No real waiting: the retry schedule's own timing is
        // NodeStartRetryPolicyTest's subject, not this one's.
        wait = { },
    )

    @Test
    fun `a node that starts is published`() = runTest(UnconfinedTestDispatcher()) {
        val node = FakeNode()
        val lifecycle = lifecycle(backgroundScope, { node })

        val result = lifecycle.startOnce()

        assertEquals(NodeStartOutcome.Started, result.outcome)
        assertSame("The started node must be the one callers can reach.", node, lifecycle.current)
        assertEquals("A node that started must not have been closed.", 0, node.closes)
    }

    @Test
    fun `a node that fails to start is closed and never published`() =
        runTest(UnconfinedTestDispatcher()) {
            // The Android-only half. On iOS the failed node goes out of scope and
            // ARC frees it; here a dropped reference is freed by a cleaner at an
            // unspecified time, and until then it holds ldk-node's handle on the
            // state directory. The next start would then be a second writer over
            // the same SQLite file — which is exactly why LdkNodeStartErrors
            // refuses to retry PersistenceFailed.
            val node = FakeNode(startBehaviour = { throw IllegalStateException("corrupt store") })
            val lifecycle = lifecycle(backgroundScope, { node })

            val result = lifecycle.startOnce()

            assertEquals(NodeStartOutcome.Failed, result.outcome)
            assertNull("A node that did not start must not be reachable.", lifecycle.current)
            assertEquals("The failed node must have been closed, not dropped.", 1, node.closes)
        }

    @Test
    fun `a stale node is closed before its replacement is built`() =
        runTest(UnconfinedTestDispatcher()) {
            // The case a foreground-service restart produces routinely: a node
            // object we hold, from a start that succeeded, over a node that has
            // since died. Building its replacement while the old object is alive
            // puts two `Node`s over one storage directory. Overwriting the field
            // would leak the first one instead of freeing it.
            val dead = FakeNode()
            val fresh = FakeNode()
            val built = mutableListOf<FakeNode>()
            val lifecycle = lifecycle(backgroundScope, {
                (if (built.isEmpty()) dead else fresh).also { built += it }
            })

            assertEquals(NodeStartOutcome.Started, lifecycle.startOnce().outcome)
            dead.stop() // the node dies underneath us; the object stays published

            val second = lifecycle.startOnce()

            assertEquals(NodeStartOutcome.Started, second.outcome)
            assertSame(fresh, lifecycle.current)
            assertEquals("The stale node object must have been closed.", 1, dead.closes)
            assertEquals("The live node must not have been closed.", 0, fresh.closes)
        }

    @Test
    fun `a node that is up is not started twice`() = runTest(UnconfinedTestDispatcher()) {
        val node = FakeNode()
        val builds = AtomicInteger()
        val lifecycle = lifecycle(backgroundScope, { builds.incrementAndGet(); node })

        lifecycle.startOnce()
        val second = lifecycle.startOnce()

        assertEquals(NodeStartOutcome.AlreadyRunning, second.outcome)
        assertEquals("A running node must not be rebuilt.", 1, builds.get())
        assertEquals(1, node.startAttempts.get())
    }

    @Test
    fun `an unanswerable status read does not escape startOnce`() =
        runTest(UnconfinedTestDispatcher()) {
            // `isRunning` is read while the gate's lock is held. If it threw, the
            // caller would get neither a start nor an outcome — the silent dead
            // end NodeStartGate exists to make impossible, arriving through the
            // gate's own status check. It has to fail towards "not running", and
            // the AlreadyRunning path then recovers a node that really was up.
            val unreadable = FakeNode(
                isRunningBehaviour = { throw IllegalStateException("handle freed") },
            )
            val replacement = FakeNode()
            val built = mutableListOf<FakeNode>()
            val lifecycle = lifecycle(backgroundScope, {
                (if (built.isEmpty()) unreadable else replacement).also { built += it }
            })
            assertEquals(NodeStartOutcome.Started, lifecycle.startOnce().outcome)

            val second = lifecycle.startOnce()

            assertEquals(
                "An unreadable status must fail towards 'not running' rather than " +
                    "propagate, so the caller gets an outcome either way.",
                NodeStartOutcome.Started,
                second.outcome,
            )
            assertSame(replacement, lifecycle.current)
            assertEquals("The node with the unreadable handle must be released.", 1, unreadable.closes)
        }

    @Test
    fun `a start recovered by the status check publishes the node`() =
        runTest(UnconfinedTestDispatcher()) {
            // ldk-node signals "already up" by throwing AlreadyRunning rather
            // than returning quietly, so a healthy node reached through a second
            // entry point looks like a failed start. NodeStartRunner's post-hoc
            // check turns it back into a success — and the node it belongs to
            // must be published, or the recovery is a status report nobody can
            // act on.
            val node = FakeNode(
                startBehaviour = { throw IllegalStateException("already running") },
                running = true,
            )
            val lifecycle = lifecycle(backgroundScope, { node })

            val result = lifecycle.startOnce()

            assertEquals(NodeStartOutcome.Started, result.outcome)
            assertSame(node, lifecycle.current)
            assertEquals("A node that turned out to be up must not be closed.", 0, node.closes)
        }

    @Test
    fun `a retryable failure is retried before the node is given up on`() =
        runTest(UnconfinedTestDispatcher()) {
            val node = FakeNode(startBehaviour = { attempt -> if (attempt < 3) throw Connectivity() })
            val lifecycle = lifecycle(backgroundScope, { node })

            val result = lifecycle.startOnce()

            assertEquals(NodeStartOutcome.Started, result.outcome)
            assertEquals("iOS retries twice after the first failure.", 3, node.startAttempts.get())
            assertEquals(
                "The node is built once and started repeatedly — three builds would " +
                    "leave two node objects behind on the way to succeeding.",
                0,
                node.closes,
            )
        }

    @Test
    fun `a missing mnemonic fails the start with a cause rather than a bare false`() =
        runTest(UnconfinedTestDispatcher()) {
            val lifecycle = lifecycle(backgroundScope, {
                throw MnemonicUnavailableException("no mnemonic on this device")
            })

            val result = lifecycle.startOnce()

            assertEquals(NodeStartOutcome.Failed, result.outcome)
            assertTrue(
                "The reason a start failed has to survive to the caller; iOS loses it " +
                    "to a `return false` and reports it to Sentry at the throw site.",
                result.cause is MnemonicUnavailableException,
            )
            assertNull(lifecycle.current)
            assertFalse(
                "MnemonicUnavailableException must not be retryable — waiting one " +
                    "second does not produce a seed.",
                retryConnectivity.isRetryable(MnemonicUnavailableException("x")),
            )
        }

    @Test
    fun `stop takes the node down and releases it`() = runTest(UnconfinedTestDispatcher()) {
        val node = FakeNode()
        val lifecycle = lifecycle(backgroundScope, { node })
        lifecycle.startOnce()

        lifecycle.stop()

        assertEquals(1, node.stops)
        assertEquals("Stopping without closing keeps the native object alive.", 1, node.closes)
        assertNull(lifecycle.current)
    }

    @Test
    fun `stop is safe when nothing is running`() = runTest(UnconfinedTestDispatcher()) {
        // WalletService.stop says so in as many words, and the reset path calls
        // it without asking.
        val lifecycle = lifecycle(backgroundScope, { FakeNode() })

        lifecycle.stop()

        assertNull(lifecycle.current)
    }

    @Test
    fun `a stop that throws still releases the node and unpublishes it`() =
        runTest(UnconfinedTestDispatcher()) {
            // A stop can fail with the channel state half-written. What must not
            // follow is a published reference to a node in an unknown state, or
            // a native object nothing will free.
            val node = object : ManagedNode {
                var closes = 0
                override fun start() = Unit
                override fun isRunning() = true
                override fun stop(): Unit = throw IllegalStateException("could not persist")
                override fun close() { closes++ }
            }
            val lifecycle = lifecycle(backgroundScope, { node })
            lifecycle.startOnce()

            val thrown = runCatching { lifecycle.stop() }.exceptionOrNull()

            assertTrue(
                "A failed stop must reach the caller: it means the state may not be on disk.",
                thrown is IllegalStateException,
            )
            assertEquals(1, node.closes)
            assertNull(lifecycle.current)
        }

    @Test
    fun `a node started then stopped can be started again`() = runTest(UnconfinedTestDispatcher()) {
        // The ordinary Android shape: foreground service down, foreground service
        // back up. The second start must build a new node rather than find a
        // published corpse.
        val nodes = mutableListOf<FakeNode>()
        val lifecycle = lifecycle(backgroundScope, { FakeNode().also { nodes += it } })

        lifecycle.startOnce()
        lifecycle.stop()
        val second = lifecycle.startOnce()

        assertEquals(NodeStartOutcome.Started, second.outcome)
        assertEquals(2, nodes.size)
        assertSame(nodes[1], lifecycle.current)
        assertEquals("The first node was closed by stop, not twice.", 1, nodes[0].closes)
    }
}
