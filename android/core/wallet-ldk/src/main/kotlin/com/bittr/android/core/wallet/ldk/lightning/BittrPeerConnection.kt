package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The one connection to the bittr node every flow shares — the payout push, a Lightning send,
 * wallet removal, Device details and the connects after a node start and on foreground.
 *
 * iOS connects in each of those places (`BitcoinManager.connectToLightningPeer()`), and a payout
 * push that finds the peer gone says "We couldn't connect to bittr" only after the node has been
 * given a chance to reconnect. Android had a single `listPeers()` check and failed on it.
 *
 * - [connect] is one attempt: [PeerReconnect]'s five-second race and disconnect-on-failure. The
 *   blocking FFI call runs detached in [scope] on [io], so a hung connect costs the caller the
 *   timeout and never more — `withContext` would wait for the JNI call to return.
 * - [ensureConnected] is up to [ATTEMPTS] of those, [BACKOFF_MILLIS] apart, answering `true` as
 *   soon as the peer is connected. Concurrent callers share one run rather than stacking connects.
 * - With no bittr node in the build ([nodeId] or [address] null) everything answers `false`
 *   without touching the node.
 */
class BittrPeerConnection(
    private val lightning: LightningNodePort,
    private val nodeId: String?,
    private val address: String?,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val timeoutMillis: Long = PeerReconnect.CONNECT_TIMEOUT_MILLIS,
    private val sleep: suspend (Long) -> Unit = { delay(it) },
    /** Logcat, tag `BittrPeer`, in the app; nothing in tests. */
    private val log: (String) -> Unit = {},
) {

    private val lock = Mutex()
    private var inFlight: Deferred<Boolean>? = null

    /** `isConnectedToPeer()`: the bittr node is in `listPeers()` and connected. */
    suspend fun isConnected(): Boolean {
        val id = nodeId ?: return false
        return runCatching { detached { lightning.listPeers().any { it.nodeId == id && it.isConnected } } }
            .getOrDefault(false)
    }

    /** One attempt, `connectToLightningPeer()`. */
    suspend fun connect(): Boolean {
        val id = nodeId ?: return false
        val at = address ?: return false
        val peers = object : PeerConnectPort {
            override suspend fun connect(nodeId: String, address: String, persist: Boolean) {
                detached { lightning.connect(nodeId, address, persist) }
            }

            override suspend fun disconnect(nodeId: String) {
                detached { lightning.disconnect(nodeId) }
            }
        }
        return PeerReconnect(peers, id, at, timeoutMillis).connectToLightningPeer()
    }

    /** Connected already, or connected within [ATTEMPTS] tries. Single-flight. */
    suspend fun ensureConnected(): Boolean {
        if (nodeId == null || address == null) return false
        val run = lock.withLock {
            inFlight?.takeIf { it.isActive } ?: scope.async { attempts() }.also { inFlight = it }
        }
        return run.await()
    }

    private suspend fun attempts(): Boolean {
        if (isConnected()) return true
        for (attempt in 1..ATTEMPTS) {
            if (connect()) {
                log("Connected to the bittr node on attempt $attempt")
                return true
            }
            if (attempt == ATTEMPTS) break
            val backoff = BACKOFF_MILLIS[attempt - 1]
            log("Connecting to the bittr node failed (attempt $attempt of $ATTEMPTS); retrying in $backoff ms")
            sleep(backoff)
            if (isConnected()) return true
        }
        log("Couldn't connect to the bittr node after $ATTEMPTS attempts")
        return false
    }

    /**
     * Runs [block] on [io] outside the caller's job, so cancelling the wait doesn't wait for the
     * FFI call. The failure travels in the result rather than failing [scope].
     */
    private suspend fun <T> detached(block: () -> T): T =
        scope.async(io) { runCatching(block) }.await().getOrThrow()

    companion object {
        /** The logcat tag the app logs [log] under. */
        const val TAG = "BittrPeer"

        const val ATTEMPTS = 3

        /** Between attempts one and two, and two and three. */
        val BACKOFF_MILLIS = longArrayOf(1_000, 2_000)
    }
}
