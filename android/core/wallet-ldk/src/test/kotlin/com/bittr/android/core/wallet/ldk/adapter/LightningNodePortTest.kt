package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.NodeUnavailableException
import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.node.NodeStartErrorClassifier
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [lightningNodePort]'s no-node behaviour, which is the half that is provable
 * on the JVM.
 *
 * BIT-132. `WalletModule` binds a `LightningNodePort` into the graph so that
 * `WalletGraph` — and through it K7 — can reach the node the app started. That
 * binding exists in **every** build, including the unconfigured one that has no
 * `NodeLifecycle` at all, so the question this class answers is: what does a
 * port over no node do?
 *
 * The answer has to be [com.bittr.android.core.wallet.ldk.lightning.LightningNodePort]'s
 * stated contract — reads empty or null, writes throw — and not a crash at
 * injection time or a null binding. An unconfigured APK is what CI assembles,
 * what Maestro installs and what a clone builds; a graph that cannot be created
 * in it is a repository nobody can run.
 *
 * ## What cannot be proved here, said plainly
 *
 * The *other* direction — a lifecycle holding a real `LdkManagedNode`, where
 * the port forwards into ldk-node — needs a `Node`, which needs the native
 * library, which needs a device. `RegtestEnvironmentTest` and the K7 suite are
 * where that is measured. So the cast in [ldkNode] is exercised here only on
 * its null branch, and that is the branch worth pinning: it is the one a
 * refactor can silently make permanent.
 *
 * The fake below is deliberately **not** an `LdkManagedNode`. That is the case
 * the cast is written for — a lifecycle over some other `ManagedNode` has no
 * ldk-node node to reach — and it is also, usefully, the only kind of
 * `ManagedNode` a JVM test can build.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LightningNodePortTest {

    /** A `ManagedNode` that is not an `LdkManagedNode`. See the class comment. */
    private class NotAnLdkNode : ManagedNode {
        var running = false
        override fun start() {
            running = true
        }

        override fun isRunning(): Boolean = running
        override fun stop() {
            running = false
        }

        override fun close() = Unit
    }

    @Test
    fun `a port over no lifecycle answers reads empty`() {
        val port = lightningNodePort(null)

        // The unconfigured build. Every one of these is a screen rendering
        // nothing rather than a screen that failed to render.
        assertEquals(emptyList<Any>(), port.listPeers())
        assertEquals(emptyList<Any>(), port.listChannels())
        assertEquals(emptyList<Any>(), port.listPayments())
        assertNull(port.payment("any-id"))
        assertNull(
            "listBalances() answered a balance with no node behind it. Null means " +
                "'no node' and zero means 'no funds' — WalletBalanceSnapshot says " +
                "what collapsing the two costs.",
            port.listBalances(),
        )
        assertNull(
            "readWalletState() answered a reading with no node behind it. A " +
                "WalletNodeReading of empty lists and zeroed balances is an empty " +
                "wallet, and WalletBalanceReader would write its cache entries on the " +
                "strength of it — clearing the funding outpoint the closure scan needs " +
                "every time the node happened to be down.",
            port.readWalletState(),
        )
    }

    @Test
    fun `a port over no lifecycle throws on every write`() {
        val port = lightningNodePort(null)

        // iOS force-unwraps these and crashes. The Android contract is an
        // exception the caller can act on, and the thing that must not happen
        // is the third option: returning quietly, so the user believes a
        // channel closed or a payment went out.
        assertThrows(NodeUnavailableException::class.java) {
            port.connect("02aa", "10.0.2.2:9735", persist = true)
        }
        assertThrows(NodeUnavailableException::class.java) {
            port.openChannel("02aa", "10.0.2.2:9735", 100_000u, null)
        }
        assertThrows(NodeUnavailableException::class.java) {
            port.closeChannel("channel-1", "02aa")
        }
    }

    @Test
    fun `a port over a lifecycle with no node running answers as if there were none`() =
        runTest(UnconfinedTestDispatcher()) {
            val lifecycle = lifecycle(NotAnLdkNode())
            val port = lightningNodePort(lifecycle)

            // Never started, so `current` is null. This is the configured build
            // between process start and the first successful unlock, which is
            // the state a K7 run spends its first seconds in.
            assertNull(lifecycle.current)
            assertEquals(emptyList<Any>(), port.listChannels())
            assertNull(port.readWalletState())
            assertThrows(NodeUnavailableException::class.java) {
                port.closeChannel("channel-1", "02aa")
            }
        }

    @Test
    fun `the port re-reads the lifecycle rather than capturing it`() =
        runTest(UnconfinedTestDispatcher()) {
            val node = NotAnLdkNode()
            val lifecycle = lifecycle(node)
            val port = lightningNodePort(lifecycle)

            // Built before the node existed, which is the composition order
            // WalletModule uses: the port is constructed once at injection and
            // the node comes up later, on unlock.
            assertEquals(emptyList<Any>(), port.listPeers())

            lifecycle.startOnce()
            assertEquals(
                "The lifecycle did not publish the started node, so the rest of " +
                    "this test would pass for the wrong reason.",
                node,
                lifecycle.current,
            )

            // Still empty — but now for the cast's reason rather than for the
            // null lifecycle's, and that distinction is the whole point of the
            // fake not being an LdkManagedNode. A port that had captured
            // `current` at construction could not tell the two apart either,
            // which is why this assertion is paired with the one below.
            assertEquals(emptyList<Any>(), port.listPeers())
            assertNull(lifecycle.current.ldkNode())
            assertTrue(
                "The lifecycle reports a node and ldkNode() found none, which is " +
                    "the documented outcome for a ManagedNode that is not an " +
                    "LdkManagedNode. If this ever fails, the cast in ldkNode() " +
                    "started matching something it should not.",
                lifecycle.current != null,
            )
        }

    private fun kotlinx.coroutines.test.TestScope.lifecycle(node: ManagedNode) = NodeLifecycle(
        scope = backgroundScope,
        factory = { node },
        // Nothing in this class drives a failure, so the classifier is never
        // consulted; retrying nothing is the honest default here.
        classifier = NodeStartErrorClassifier { false },
        elapsedRealtimeMillis = { 0L },
        wait = { },
    )
}
