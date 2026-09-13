package com.bittr.android.core.wallet.ldk.node

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay

/**
 * A built Lightning node, as the four operations its lifecycle needs.
 *
 * The interface exists so [NodeLifecycle] — which decides when a node is built,
 * when it is published, and when it is destroyed — can be written and tested
 * without ldk-node's `Node` in its signature. `LdkManagedNode` is the binding.
 * See `WalletLayeringGuardTest` for why that split is not optional here.
 *
 * Deliberately four methods and not forty. Sync, channels and payments are the
 * rest of BIT-122 and they will arrive as their own seams; what belongs *here*
 * is only what the start/stop decision has to be able to do, because every
 * method added to this interface is a method the fakes in `NodeLifecycleTest`
 * have to model.
 */
interface ManagedNode {

    /**
     * Bring the node up. Throws on failure, as ldk-node's `Node.start()` does —
     * including `AlreadyRunning`, which is a routine outcome on Android and is
     * handled by [NodeStartRunner], not here.
     */
    fun start()

    /** Whether the node reports itself up. `status().isRunning` on ldk-node. */
    fun isRunning(): Boolean

    /**
     * Take the node down.
     *
     * **Stopping a node that is not running is not an error at this seam.** iOS
     * reaches `stop()` from `AppDelegate` and from the reset path without ever
     * asking whether the node is up (`BitcoinManager.swift:389–394`), and
     * `WalletService.stop` says in as many words that it must be safe to call
     * when already stopped. ldk-node disagrees — it throws `NotRunning` — so the
     * adapter absorbs that one case and this interface promises the iOS
     * behaviour. Every other failure still propagates.
     */
    fun stop()

    /**
     * Release the node's native resources now, rather than whenever a cleaner
     * gets to it.
     *
     * **This has no iOS counterpart and it is not optional.** On iOS a `Node`
     * that fails to start goes out of scope and ARC frees it at a known moment,
     * which releases ldk-node's handle on the storage directory and its SQLite
     * store. UniFFI's Kotlin bindings free the Rust object from a
     * `java.lang.ref.Cleaner`, at an unspecified time — so a dropped reference
     * is a node that may still hold the store minutes later.
     *
     * That matters because the next thing that happens after a failed start is
     * usually another start, and a second `Node` built over a store the first
     * one has not let go of is the two-writers case that `LdkNodeStartErrors`
     * refuses to retry. Closing explicitly is what makes "the failed node is
     * gone" true at the point [NodeLifecycle] says it.
     */
    fun close()
}

/** Builds a node from the current configuration. Throws if it cannot. */
fun interface ManagedNodeFactory {
    fun build(): ManagedNode
}

/**
 * There is no mnemonic to build a node from.
 *
 * iOS's `guard let mnemonicString = CacheManager.getMnemonic() else { return
 * false }` (`BitcoinManager.swift:145–149`), as a type rather than as a boolean,
 * so the failure arrives at [NodeStartResult.cause] saying what went wrong
 * instead of arriving as a bare `false`.
 *
 * It lives here rather than in the adapter because the retry classifier has to
 * be able to *not* match it, and a classifier deciding about a type it cannot
 * see would decide by accident. It is not a `NodeException`, so
 * `LdkNodeStartErrors` classifies it non-retryable — which is right: waiting one
 * second does not produce a seed. On Android the usual cause is a teardown
 * racing a start, exactly as iOS's `didStartBDK` comment describes it
 * (`BDKManager.swift:111`).
 */
class MnemonicUnavailableException(message: String) : Exception(message)

/**
 * Owning the node object: one at a time, published only when it is up, and
 * destroyed when it is not.
 *
 * This is the piece `BitcoinManager` keeps as a bare `var ldkNode: Node?`
 * assigned at `BitcoinManager.swift:215`, and the piece that on Android has to
 * be more than a var. Three of iOS's implicit guarantees are guarantees only
 * because of ARC and because an iOS app is not routinely killed and relaunched:
 *
 * - **A node that failed to start is freed.** iOS's `newLdkNode` goes out of
 *   scope; here it is [ManagedNode.close]'s job, and skipping it leaves a native
 *   object holding the state directory. See that method's comment.
 * - **`self.ldkNode` only ever holds a node that started.** iOS assigns after
 *   `didStartNode` returns true, and that ordering is preserved exactly: a node
 *   is published from [buildAndStart] only on success, so no caller can reach a
 *   half-built one.
 * - **There is never a second node over the same store.** On iOS the only way to
 *   get one is to call `didStartLDK` twice concurrently, which `claimNodeStart`
 *   prevents. On Android the same call also has to survive a *stale* node — an
 *   object left over from a start that succeeded and a node that has since died,
 *   which a foreground-service restart produces routinely. [NodeStartGate] stops
 *   the concurrent case; the stale case is handled below, by discarding the old
 *   object before building its replacement rather than by overwriting the field
 *   and hoping.
 *
 * ## What this class does not decide
 *
 * Whether to start at all, and what to do about a failure, stay where they were:
 * [NodeStartGate] arbitrates callers, [NodeStartRunner] owns the retry schedule,
 * and `LdkNodeStartErrors` classifies. This is only the object's custody. That
 * separation is what lets `NodeLifecycleTest` prove the custody rules against
 * fakes, on the JVM, with no native library loaded.
 *
 * Proved by `NodeLifecycleTest`.
 */
class NodeLifecycle(
    /**
     * The scope a start runs in. Must outlive any individual caller — see
     * [NodeStartGate]'s class comment for what a `viewModelScope` here would do
     * to every caller attached to the start.
     */
    scope: CoroutineScope,
    private val factory: ManagedNodeFactory,
    private val classifier: NodeStartErrorClassifier,
    private val policy: NodeStartRetryPolicy = NodeStartRetryPolicy(),
    /**
     * Monotonic and deep-sleep-inclusive: `SystemClock.elapsedRealtime` in
     * production. Required rather than defaulted so this file needs no
     * `android.os` import and its tests need no Robolectric — the reasoning
     * about *which* clock is in [NodeStartRetryPolicy].
     */
    private val elapsedRealtimeMillis: () -> Long,
    /** Cancellable wait between attempts. */
    private val wait: suspend (Long) -> Unit = { delay(it) },
) {

    private val lock = Any()

    /** The node, if one is up. Written only by [buildAndStart] and [stop]. */
    private var node: ManagedNode? = null

    private val gate = NodeStartGate(
        scope = scope,
        isRunning = ::isNodeRunning,
        start = ::buildAndStart,
    )

    /**
     * The running node, or null.
     *
     * Callers that need the node for work — sync, channels, payments — read it
     * here and must tolerate null, because a teardown or a process-level stop
     * can null it between two statements. iOS has the same hazard and says so at
     * `BitcoinManager.swift:705–709`.
     */
    val current: ManagedNode? get() = synchronized(lock) { node }

    /**
     * Bring the node up if it is not up already.
     *
     * The single entry point. Concurrent callers produce one start and all of
     * them get the outcome — see [NodeStartGate].
     */
    suspend fun startOnce(): NodeStartResult = gate.startOnce()

    /**
     * Take the node down and release it.
     *
     * Safe when nothing is running, which is `WalletService.stop`'s stated
     * contract and [ManagedNode.stop]'s. The field is cleared *before* the stop rather than after: a stop that
     * throws must still leave the wallet believing it has no node, because the
     * alternative is a published reference to something in an unknown state.
     * The object is closed either way, so the native resources go back even when
     * the orderly stop failed.
     */
    suspend fun stop() {
        val running = synchronized(lock) { node.also { node = null } } ?: return
        try {
            running.stop()
        } finally {
            runCatching { running.close() }
        }
    }

    private fun isNodeRunning(): Boolean {
        val existing = synchronized(lock) { node } ?: return false
        // Read while the gate's lock is held, so it cannot be allowed to throw:
        // an exception here would propagate out of `startOnce` as neither a
        // start nor an outcome. Unanswerable reads count as "not running",
        // which sends us into a start attempt — and if the node *is* in fact up,
        // ldk-node throws `AlreadyRunning` and NodeStartRunner's post-hoc check
        // turns that back into a successful start. The fail-safe direction.
        return runCatching { existing.isRunning() }.getOrDefault(false)
    }

    /**
     * iOS's `didStartLDK` + `didStartNode`, with the object custody made
     * explicit. Runs inside the gate, so nothing else is starting concurrently.
     */
    private suspend fun buildAndStart(): Boolean {
        // A node object we hold that is not running is not an object to keep.
        // Building its replacement while it is still alive would put two
        // `Node`s over one storage directory — the case LdkNodeStartErrors
        // refuses to retry, arriving from inside rather than from a second
        // caller. The gate guarantees no start is concurrent with this, so
        // taking the field here cannot race one.
        synchronized(lock) { node.also { node = null } }?.let(::discardUnstarted)

        val built = factory.build()

        val attempts = try {
            NodeStartRunner(
                policy = policy,
                classifier = classifier,
                elapsedRealtimeMillis = elapsedRealtimeMillis,
                wait = wait,
            ).run(
                startNode = built::start,
                isRunning = { runCatching { built.isRunning() }.getOrDefault(false) },
            )
        } catch (error: Throwable) {
            // Including cancellation: the scope is going down mid-start and the
            // node we built is about to be unreachable. Free it on the way out.
            discardUnstarted(built)
            throw error
        }

        if (!attempts.started) {
            discardUnstarted(built)
            return false
        }

        // Publish only now — iOS's ordering at BitcoinManager.swift:210–216.
        synchronized(lock) { node = built }
        return true
    }

    /**
     * Release a node that is not running.
     *
     * [ManagedNode.stop] is deliberately not called: there is nothing to stop,
     * and the adapter would have to swallow a `NotRunning` that means exactly
     * what we already know. [ManagedNode.close] is what gives the store back.
     * Failures are swallowed because this runs on paths that are already
     * failing, and the error that matters is the one that got us here.
     */
    private fun discardUnstarted(node: ManagedNode) {
        runCatching { node.close() }
    }
}
