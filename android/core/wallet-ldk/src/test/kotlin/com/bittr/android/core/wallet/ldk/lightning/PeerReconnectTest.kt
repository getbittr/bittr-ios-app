package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The LSP reconnect, on virtual time.
 *
 * iOS writes this as a `withTaskGroup` racing a connect against a five-second
 * sleep and taking whichever *finishes first* — not whichever succeeds. The three
 * tests below are the three behaviours that phrasing produces and that a
 * "connect, then wait, then check" rewrite would lose.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PeerReconnectTest {

    private companion object {
        val LSP_NODE_ID = "03".padEnd(66, 'b')
        const val LSP_ADDRESS = "lsp.example:9735"
    }

    private class FakePeers(
        /** How long the connect takes before it answers. */
        private val connectDelayMillis: Long = 0,
        private val connectFailure: Exception? = null,
        private val disconnectFailure: Exception? = null,
    ) : PeerConnectPort {

        var connects = 0
        var disconnects = 0
        var persisted: Boolean? = null

        override suspend fun connect(nodeId: String, address: String, persist: Boolean) {
            connects++
            persisted = persist
            delay(connectDelayMillis)
            connectFailure?.let { throw it }
        }

        override suspend fun disconnect(nodeId: String) {
            disconnects++
            disconnectFailure?.let { throw it }
        }
    }

    @Test
    fun `a connect that succeeds inside the window establishes the peer`() = runTest {
        val peers = FakePeers(connectDelayMillis = 400)

        val established = PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertTrue(established)
        assertEquals("No disconnect on success.", 0, peers.disconnects)
        assertEquals(400L, currentTime)
    }

    /**
     * Behaviour one. iOS's `group.next()` returns the *first* task to finish, so a
     * connect that throws in 200 ms answers at 200 ms — it does not sit out the
     * five-second timer. Getting this wrong puts a five-second spinner in front of
     * every offline retry.
     */
    @Test
    fun `a connect that fails fast answers immediately, not at the timeout`() = runTest {
        val peers = FakePeers(connectDelayMillis = 200, connectFailure = java.io.IOException("no route"))

        val established = PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertFalse(established)
        assertEquals(
            "200 ms, not 5 000. The failure is the answer.",
            200L,
            currentTime,
        )
    }

    /** Behaviour two: a hang answers false at five seconds. */
    @Test
    fun `a connect that hangs times out at five seconds`() = runTest {
        val peers = FakePeers(connectDelayMillis = 60_000)

        val established = PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertFalse(established)
        assertEquals(PeerReconnect.CONNECT_TIMEOUT_MILLIS, currentTime)
        assertEquals("The failure path disconnects.", 1, peers.disconnects)
    }

    /**
     * Behaviour three, and the one that reads as belt-and-braces. ldk-node records
     * a peer as soon as a connect is attempted with `persist: true`; a connect that
     * then fails leaves that entry behind and the next attempt can be answered from
     * it. The disconnect clears it.
     */
    @Test
    fun `a failed connect is followed by a disconnect`() = runTest {
        val peers = FakePeers(connectFailure = java.io.IOException("refused"))

        PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertEquals(1, peers.connects)
        assertEquals(1, peers.disconnects)
    }

    /**
     * And the disconnect's own failure is swallowed: there is usually nothing
     * connected to disconnect, so it throws routinely. The caller asked whether
     * the peer is up and that answer is already known.
     */
    @Test
    fun `a disconnect that throws does not change the answer`() = runTest {
        val failure = IllegalStateException("not connected")
        val peers = FakePeers(
            connectFailure = java.io.IOException("refused"),
            disconnectFailure = failure,
        )
        val swallowed = mutableListOf<Throwable>()

        val established = PeerReconnect(
            peers = peers,
            lspNodeId = LSP_NODE_ID,
            lspAddress = LSP_ADDRESS,
            onDisconnectFailure = { swallowed += it },
        ).connectToLightningPeer()

        assertFalse(established)
        assertEquals(1, swallowed.size)
        assertSame(failure, swallowed.single())
    }

    /**
     * `persist: true` (`BitcoinManager.swift:352`). The LSP is the one peer the
     * wallet always wants back after a restart — and it is also what makes the
     * disconnect above necessary rather than decorative.
     */
    @Test
    fun `the LSP connection is persisted`() = runTest {
        val peers = FakePeers()

        PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertEquals(true, peers.persisted)
    }

    @Test
    fun `no retry schedule lives here`() = runTest {
        val peers = FakePeers(connectFailure = java.io.IOException("refused"))

        PeerReconnect(peers, LSP_NODE_ID, LSP_ADDRESS).connectToLightningPeer()

        assertEquals(
            "One attempt. The caller's cadence is the reconnect policy — adding a " +
                "schedule here would give Android a second, invisible one on top of it.",
            1,
            peers.connects,
        )
    }
}
