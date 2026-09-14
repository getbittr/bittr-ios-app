package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.NodeUnavailableException
import com.bittr.android.core.wallet.ldk.lightning.OnchainAddressView
import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.node.NodeStartErrorClassifier
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.lightningdevkit.ldknode.FeeRate
import org.lightningdevkit.ldknode.OnchainPaymentInterface

/**
 * [LdkOnchainSurface], **both halves** — which is the thing worth saying about
 * this class rather than about [LightningNodePortTest].
 *
 * BIT-132, `android/docs/wallet-node-device-tests.md` §3 item 1. K7's host
 * phase asks the device for the address to fund, because the host cannot derive
 * ldk-node's. This is where that answer's plumbing is checked.
 *
 * ## Why the forwarding half is provable here and is not for `LightningNodePort`
 *
 * `LightningNodePortTest` can only assert the no-node branch, and says so: its
 * port is built over `() -> Node?`, `Node` is a concrete UniFFI class, and
 * nothing a JVM test can construct is one.
 *
 * [LdkOnchainSurface] takes `() -> OnchainPaymentInterface?`. That interface is
 * plain Kotlin — `OnchainPayment` implements it, and so does [FakeOnchain]
 * below — so the assertion that matters most about this port is available
 * without a device: **the address the node returned is the address the caller
 * gets, unchanged.** An address that is almost right is a transaction that
 * confirms into nobody's wallet.
 *
 * What still needs the device is the layer under the seam:
 * `lifecycle.current.ldkNode()?.onchainPayment()` reaching a real node, and the
 * address being one ldk-node will actually spend from at `openChannel`. That is
 * the regtest suite's, and it is the half K7 exercises end to end.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NodeOnchainPortTest {

    /**
     * An `OnchainPaymentInterface` that is not ldk-node's.
     *
     * The two send methods throw rather than returning a dummy transaction id.
     * [com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort] deliberately
     * exposes no send — the host holds bitcoind and does all the sending — so a
     * call to either of these from the port would be a new fund-moving path
     * arriving without a test, and this is where it is noticed.
     */
    private class FakeOnchain(private val addresses: List<String>) : OnchainPaymentInterface {
        var revealed = 0
            private set

        override fun newAddress(): String = addresses[revealed++.coerceAtMost(addresses.lastIndex)]

        override fun sendAllToAddress(
            address: String,
            retainReserve: Boolean,
            feeRate: FeeRate?,
        ): String = error("NodeOnchainPort has no send; nothing should reach this.")

        override fun sendToAddress(
            address: String,
            amountSats: ULong,
            feeRate: FeeRate?,
        ): String = error("NodeOnchainPort has no send; nothing should reach this.")
    }

    /** A `ManagedNode` that is not an `LdkManagedNode` — `ldkNode()` finds none. */
    private class NotAnLdkNode : ManagedNode {
        private var running = false
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
    fun `a port over no node refuses to invent an address`() {
        val port = LdkOnchainSurface { null }

        // Not null, not an empty string, not a placeholder. A caller that asked
        // where to send money and got a value it could use would send it there.
        val thrown = assertThrows(NodeUnavailableException::class.java) {
            port.newReceiveAddress()
        }
        assertEquals(
            "The message is what a CI log shows at 03:20 UTC when a regtest run " +
                "reaches the funding phase against a node that did not start, so it " +
                "names both reasons a node can be absent.",
            true,
            thrown.message.orEmpty().contains("no Lightning node is running"),
        )
    }

    @Test
    fun `the unconfigured build composes a port and that port throws`() {
        // `nodeOnchainPort(null)` is the binding an APK with no LdkEnvironment
        // gets — the one CI assembles, Maestro installs and a clone builds. It
        // has to construct, because a graph that cannot be created is an app
        // that cannot launch; what it must not do is answer.
        val port = nodeOnchainPort(null)

        assertThrows(NodeUnavailableException::class.java) { port.newReceiveAddress() }
    }

    @Test
    fun `a running node's address is forwarded unchanged`() {
        val node = FakeOnchain(listOf("bcrt1qexampleaddressoneexampleaddressone0"))
        val port = LdkOnchainSurface { node }

        assertEquals(
            "The address was not forwarded verbatim. This is the one thing this " +
                "class does, and the failure it prevents is funds confirming into " +
                "an address nobody is watching.",
            OnchainAddressView("bcrt1qexampleaddressoneexampleaddressone0"),
            port.newReceiveAddress(),
        )
        assertEquals(
            "The port called newAddress() a number of times that is not one. Each " +
                "call reveals and persists the next index, so a port that called it " +
                "twice per request would burn an address per funding round.",
            1,
            node.revealed,
        )
    }

    @Test
    fun `each call reveals the next address rather than repeating one`() {
        val node = FakeOnchain(listOf("bcrt1qfirst", "bcrt1qsecond"))
        val port = LdkOnchainSurface { node }

        // Not a property of this class — it is ldk-node's — but it is the
        // property the host phase depends on, and pinning it here says that a
        // cached address inside the port would be a bug rather than an
        // optimisation. Two fundings, two addresses.
        assertEquals(OnchainAddressView("bcrt1qfirst"), port.newReceiveAddress())
        assertEquals(OnchainAddressView("bcrt1qsecond"), port.newReceiveAddress())
    }

    @Test
    fun `the port re-reads the node rather than capturing it`() {
        var current: OnchainPaymentInterface? = null
        val port = LdkOnchainSurface { current }

        // The composition order WalletModule uses: the port is built once at
        // injection, and the node comes up later, on unlock. A port that had
        // resolved its node at construction would throw here forever.
        assertThrows(NodeUnavailableException::class.java) { port.newReceiveAddress() }

        current = FakeOnchain(listOf("bcrt1qafterstart"))
        assertEquals(OnchainAddressView("bcrt1qafterstart"), port.newReceiveAddress())

        // And back. A stop between two calls is a teardown, not a programming
        // error — NodeLifecycle.current goes null and every caller must
        // tolerate it.
        current = null
        assertThrows(NodeUnavailableException::class.java) { port.newReceiveAddress() }
    }

    @Test
    fun `a lifecycle over a node that is not ldk-node's answers as if there were none`() =
        runTest(UnconfinedTestDispatcher()) {
            val lifecycle = NodeLifecycle(
                scope = backgroundScope,
                factory = { NotAnLdkNode() },
                classifier = NodeStartErrorClassifier { false },
                elapsedRealtimeMillis = { 0L },
                wait = { },
            )
            val port = nodeOnchainPort(lifecycle)

            lifecycle.startOnce()

            // The lifecycle holds a running node and the cast finds no ldk-node
            // node behind it, which is the branch `ldkNode()` exists for. The
            // port's answer has to be the same as for no node at all — the
            // alternative is a caller that distinguishes two flavours of
            // absence.
            assertThrows(NodeUnavailableException::class.java) { port.newReceiveAddress() }
        }
}
