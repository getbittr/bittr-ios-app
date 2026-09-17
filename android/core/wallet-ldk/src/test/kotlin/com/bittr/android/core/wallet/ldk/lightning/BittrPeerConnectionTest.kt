package com.bittr.android.core.wallet.ldk.lightning

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BittrPeerConnectionTest {

    private companion object {
        val BITTR_NODE_ID = "02".padEnd(66, 'a')
        const val BITTR_ADDRESS = "bittr.example:9735"
    }

    /** Fails the first [failures] connects, then connects. */
    private class PeerPort(
        private val failures: Int,
        private val onConnect: () -> Unit = {},
    ) : LightningNodePort by ReadingOnlyPort(null) {

        @Volatile var connects = 0
        @Volatile var disconnects = 0
        @Volatile var connected = false

        override fun listPeers(): List<PeerView> =
            if (connected) listOf(PeerView(BITTR_NODE_ID, BITTR_ADDRESS, isPersisted = true, isConnected = true)) else emptyList()

        override fun connect(nodeId: String, address: String, persist: Boolean) {
            connects++
            onConnect()
            if (connects <= failures) throw IllegalStateException("connect $connects refused")
            connected = true
        }

        override fun disconnect(nodeId: String) {
            disconnects++
        }
    }

    private fun TestScope.connection(port: LightningNodePort, nodeId: String? = BITTR_NODE_ID) =
        BittrPeerConnection(
            lightning = port,
            nodeId = nodeId,
            address = BITTR_ADDRESS,
            scope = backgroundScope,
            io = StandardTestDispatcher(testScheduler),
        )

    @Test
    fun `an already connected peer answers at once without connecting`() = runTest {
        val port = PeerPort(failures = 0).apply { connected = true }

        assertTrue(connection(port).ensureConnected())
        assertEquals(0, port.connects)
    }

    @Test
    fun `retries after a second and connects on the second attempt`() = runTest {
        val port = PeerPort(failures = 1)

        assertTrue(connection(port).ensureConnected())
        assertEquals(2, port.connects)
        assertEquals("The failed attempt disconnects.", 1, port.disconnects)
        assertEquals(1_000L, currentTime)
    }

    @Test
    fun `gives up after three attempts, one and two seconds apart`() = runTest {
        val port = PeerPort(failures = Int.MAX_VALUE)

        assertFalse(connection(port).ensureConnected())
        assertEquals(3, port.connects)
        assertEquals(3, port.disconnects)
        assertEquals(3_000L, currentTime)
    }

    @Test
    fun `concurrent callers share one run`() = runTest {
        val port = PeerPort(failures = 1)
        val peer = connection(port)

        val first = async { peer.ensureConnected() }
        val second = async { peer.ensureConnected() }

        assertTrue(first.await())
        assertTrue(second.await())
        assertEquals(2, port.connects)
    }

    @Test
    fun `a build with no bittr node answers false without touching the node`() = runTest {
        val port = PeerPort(failures = 0)
        val peer = connection(port, nodeId = null)

        assertFalse(peer.ensureConnected())
        assertFalse(peer.isConnected())
        assertEquals(0, port.connects)
    }

    /** A connect stuck in the FFI call: the caller gets `false` at the timeout, not when it returns. */
    @Test
    fun `a hung connect times out instead of holding the caller`() = runBlocking {
        val release = CountDownLatch(1)
        val port = PeerPort(failures = 0, onConnect = { release.await(10, TimeUnit.SECONDS) })
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val peer = BittrPeerConnection(
            lightning = port,
            nodeId = BITTR_NODE_ID,
            address = BITTR_ADDRESS,
            scope = scope,
            timeoutMillis = 100,
        )
        try {
            val started = System.nanoTime()
            assertFalse(peer.connect())
            val tookMillis = (System.nanoTime() - started) / 1_000_000
            assertTrue("Took $tookMillis ms", tookMillis < 5_000)
            assertEquals(1, port.disconnects)
        } finally {
            release.countDown()
            scope.cancel()
        }
    }
}
