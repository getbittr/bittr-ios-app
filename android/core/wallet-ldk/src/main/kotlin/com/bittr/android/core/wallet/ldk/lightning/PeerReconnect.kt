package com.bittr.android.core.wallet.ldk.lightning

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The two peer calls, as suspending functions.
 *
 * ldk-node's `connect` blocks — it opens a TCP connection and completes a
 * handshake — so calling it from a coroutine without moving threads blocks
 * whatever dispatcher the caller is on. iOS gets this for free: `connect` is
 * `async` there and Swift's runtime owns the thread. On Android it has to be
 * said, and [dispatching] is where it is said, once.
 */
interface PeerConnectPort {

    suspend fun connect(nodeId: String, address: String, persist: Boolean)

    suspend fun disconnect(nodeId: String)
}

/**
 * [PeerConnectPort] over a [LightningNodePort], with the blocking calls moved
 * off the caller's thread.
 *
 * @param dispatcher `Dispatchers.IO` in production. Injected so
 *   `PeerReconnectTest` can run the whole reconnect on the test scheduler and
 *   assert the timeout in virtual time rather than by waiting five seconds.
 */
fun LightningNodePort.dispatching(
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
): PeerConnectPort = object : PeerConnectPort {

    override suspend fun connect(nodeId: String, address: String, persist: Boolean) =
        withContext(dispatcher) { this@dispatching.connect(nodeId, address, persist) }

    override suspend fun disconnect(nodeId: String) =
        withContext(dispatcher) { this@dispatching.disconnect(nodeId) }
}

/**
 * Getting — and keeping — a connection to the LSP.
 *
 * Port of `connectToLightningPeer()` and `didEstablishPeerConnection()`
 * (`BitcoinManager.swift:317–387`). iOS writes it as a `withTaskGroup` racing the
 * connect against a five-second sleep and taking `group.next()`, which is
 * *whichever finishes first*, not *whichever succeeds*.
 *
 * ## Three behaviours the obvious rewrite loses
 *
 * 1. **A fast failure answers immediately.** If `connect` throws in 200 ms the
 *    result is `false` at 200 ms, not at five seconds. Writing this as "try to
 *    connect, wait up to 5s, then check" would make every offline retry cost five
 *    seconds of spinner. [withTimeoutOrNull] preserves it: the body returns as
 *    soon as the connect resolves, either way.
 *
 * 2. **A hang answers `false` and the connect keeps going.** iOS calls
 *    `group.cancelAll()`, but the connect task is inside a synchronous FFI call
 *    that does not observe cancellation, so it runs to completion regardless —
 *    and that is fine, even useful: the connection may well establish a moment
 *    later and the next call finds it up. The same is true here, and for the same
 *    reason: cancelling the coroutine cannot interrupt a blocking JNI call, it
 *    only stops us waiting on it. What it must not do is leak the wait — hence
 *    the dispatcher in [dispatching] rather than running it on the caller's.
 *
 * 3. **A failed connect is followed by a disconnect, whose own failure is
 *    ignored.** This reads like belt-and-braces and is not. ldk-node records a
 *    peer the moment a connect is attempted with `persist: true`; a connect that
 *    then fails leaves that entry behind, and the next attempt can be answered
 *    from it rather than retried. Disconnecting clears it. The disconnect itself
 *    routinely throws — there is usually nothing connected to disconnect — and
 *    iOS logs and swallows it (`BitcoinManager.swift:325–335`), because the
 *    caller asked "am I connected", and the answer is already known to be no.
 *
 * ## What it deliberately does not do
 *
 * No retry, no backoff, no reconnect loop. iOS calls this from
 * `fetchAndPrintPeers()` on every wallet-data load and the *caller's* cadence is
 * the reconnect policy. Adding a schedule here would give Android a second,
 * invisible one on top of it.
 *
 * Proved by `PeerReconnectTest`.
 */
class PeerReconnect(
    private val peers: PeerConnectPort,
    /** The LSP's node id and address — `EnvironmentConfig.lightningNodeId` / `…Address`. */
    private val lspNodeId: String,
    private val lspAddress: String,
    /** `BitcoinManager.swift:374`. */
    private val timeoutMillis: Long = CONNECT_TIMEOUT_MILLIS,
    /**
     * What to do with a swallowed disconnect failure. iOS hands it to
     * `SentryManager.capture`; defaulted to a no-op so this class has no logging
     * dependency and its test can assert the swallow happened.
     */
    private val onDisconnectFailure: (Throwable) -> Unit = {},
) {

    /**
     * `connectToLightningPeer() -> Bool`.
     *
     * @return whether the peer connection was established. False covers all three
     *   of: the connect threw, the connect timed out, and the connect succeeded
     *   after the timeout had already answered.
     */
    suspend fun connectToLightningPeer(): Boolean {
        val established = didEstablishPeerConnection()
        if (!established) {
            // See the class comment, point 3. Not `runCatching`: an Error on the
            // way through JNI is not a disconnect that politely failed, and the
            // rest of this module draws the line in the same place.
            try {
                peers.disconnect(lspNodeId)
            } catch (failure: Exception) {
                onDisconnectFailure(failure)
            }
        }
        return established
    }

    /** `didEstablishPeerConnection() async -> Bool`. */
    suspend fun didEstablishPeerConnection(): Boolean = withTimeoutOrNull(timeoutMillis) {
        try {
            peers.connect(nodeId = lspNodeId, address = lspAddress, persist = PERSIST)
            true
        } catch (failure: Exception) {
            // iOS's `catch` inside the connect task: log, and return false *now*
            // rather than letting the five-second timer decide.
            false
        }
    } ?: false

    companion object {

        /** `Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)` (`BitcoinManager.swift:374`). */
        const val CONNECT_TIMEOUT_MILLIS: Long = 5_000

        /**
         * `persist: true` (`BitcoinManager.swift:352`).
         *
         * The LSP is the one peer this wallet always wants back after a restart,
         * so ldk-node is asked to remember it. It is also what makes the
         * disconnect in [connectToLightningPeer] necessary rather than decorative.
         */
        const val PERSIST: Boolean = true
    }
}
