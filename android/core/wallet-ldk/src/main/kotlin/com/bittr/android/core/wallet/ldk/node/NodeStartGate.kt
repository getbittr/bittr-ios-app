package com.bittr.android.core.wallet.ldk.node

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/**
 * Starting the node at most once, and telling every caller how it went.
 *
 * Port of `BitcoinManager.claimNodeStart` / `runClaimedNodeStart` /
 * `endNodeStart` (`BitcoinManager.swift:78–117`). The iOS shape is a lock, a
 * `isStartingNode` flag, and an array of completions that the winner fires when
 * it finishes — with a three-way decision (`proceed` / `startInFlight` /
 * `alreadyRunning`) returned to the caller.
 *
 * Two things about that shape are worth restating, because both were bought
 * with a bug:
 *
 * - **A caller that loses the race must still be told the outcome.** iOS's own
 *   doc comment says it: a `.startInFlight` branch with no completion attached
 *   "is a silent dead end for as long as that start runs". `CoreViewController`
 *   raises a spinner before calling, so a dead end is a spinner forever.
 * - **Node start is not idempotent in a useful way.** ldk-node throws
 *   `NodeException.AlreadyRunning` rather than returning, and a second `build()`
 *   against the same storage directory is a second writer.
 *
 * Here, "every caller gets an outcome" is structural rather than a convention:
 * there is one entry point, [startOnce], and it returns the outcome whether the
 * caller owned the start or attached to one already running. A caller cannot
 * take the losing branch and forget to pass a completion, because there is no
 * losing branch to take.
 *
 * ## What is different on Android, and why the [scope] parameter exists
 *
 * On iOS the winner runs on `DispatchQueue.global(qos: .userInitiated)`, which
 * nothing cancels. The Android equivalent — starting the node from whatever
 * coroutine scope the caller happens to be in — is wrong in a way that is easy
 * to miss, because the common caller is UI:
 *
 * - `lifecycleScope` is cancelled on rotation and on backgrounding.
 * - `viewModelScope` is cancelled when the user leaves the screen.
 *
 * Cancelling the *caller* would then cancel the *node start*, and every other
 * caller attached to it is left holding a cancelled `Deferred` — the silent
 * dead end again, arriving by a route iOS does not have. So the start runs in
 * the scope this gate was built with (the wallet service's own, tied to the
 * process and not to a screen), and callers merely await it. A caller that goes
 * away takes nothing with it.
 *
 * `NodeStartGateTest` proves both halves: concurrent callers produce exactly one
 * start, and cancelling an attached caller — or the owner — does not cancel it.
 *
 * ## What this gate deliberately does not do
 *
 * It has no memory across process death, and should not. A fresh process has no
 * node running and no start in flight, so the correct answer after a kill is
 * "proceed", which is what an empty gate says. Persisting anything here would
 * mean persisting a claim that the node is running when it demonstrably is not.
 */
class NodeStartGate(
    /**
     * The scope the node start itself runs in. Must outlive any individual
     * caller — see the class comment. In production this is the wallet
     * service's scope; in tests, the test scope.
     */
    private val scope: CoroutineScope,
    /**
     * Whether the node is up right now.
     *
     * Port of `ldkNode != nil, status()?.isRunning == true`
     * (`BitcoinManager.swift:88`). Non-suspending on purpose: it is read while
     * the gate's lock is held, and a suspending call under a lock is how a
     * single-flight guard becomes a deadlock.
     */
    private val isRunning: () -> Boolean,
    /** Build and start the node. `true` if it came up. */
    private val start: suspend () -> Boolean,
) {

    private val lock = Any()

    /** Non-null exactly while a start this gate owns is in flight. */
    private var inFlight: Deferred<NodeStartResult>? = null

    /**
     * Bring the node up if it is not up already, and return what happened.
     *
     * Never starts a second node. Never returns without an outcome.
     */
    suspend fun startOnce(): NodeStartResult {
        val attached: Deferred<NodeStartResult>
        val owned: Boolean

        synchronized(lock) {
            val existing = inFlight
            if (existing != null) {
                // Port of `.startInFlight`, with the completion no longer
                // optional: awaiting the same Deferred *is* the completion.
                attached = existing
                owned = false
            } else {
                if (isRunning()) return NodeStartResult.alreadyRunning()
                // LAZY so the body cannot begin — and cannot complete, and
                // cannot run the completion handler below — before this block
                // has published it to `inFlight`. Without that, a start that
                // finishes fast clears a field that has not been set yet, and
                // the next caller attaches to a corpse.
                val fresh = scope.async(start = CoroutineStart.LAZY) { runStart() }
                fresh.invokeOnCompletion {
                    synchronized(lock) { if (inFlight === fresh) inFlight = null }
                }
                inFlight = fresh
                attached = fresh
                owned = true
            }
        }

        // No-op for everyone but the owner.
        attached.start()
        return attached.await().copy(ownedStart = owned)
    }

    private suspend fun runStart(): NodeStartResult = try {
        if (start()) {
            NodeStartResult.started()
        } else {
            android.util.Log.w("BittrNode", "Node start returned false")
            NodeStartResult.failed(null)
        }
    } catch (cancellation: kotlinx.coroutines.CancellationException) {
        // The gate's own scope is going down — the wallet is being torn down or
        // the process is ending. Not an outcome to report; let it propagate so
        // awaiting callers see a cancellation rather than a spurious failure
        // that would send them to the retry alert on the way out.
        throw cancellation
    } catch (error: Throwable) {
        // iOS lets `didStartLDK()` return false for every failure mode and
        // reports the error to Sentry at the throw site. Carrying the cause out
        // instead keeps the retry decision (NodeStartRetryPolicy) able to see
        // what actually failed.
        android.util.Log.w("BittrNode", "Node start failed", error)
        NodeStartResult.failed(error)
    }
}

/**
 * What a call to [NodeStartGate.startOnce] did.
 *
 * [ownedStart] is the port of iOS's `.proceed` vs `.startInFlight`: the outcome
 * is the same either way, but which caller *did* the work is worth logging, and
 * the follow-up work after a start (sync, load, connect peer) is global rather
 * than per-caller — see `continueStartWallet`'s own guard
 * (`StartLightning.swift:92–96`), which is a separate concern from this one and
 * stays that way.
 */
data class NodeStartResult(
    val outcome: NodeStartOutcome,
    /** True for the caller that ran the start, false for callers that attached. */
    val ownedStart: Boolean,
    /** The failure, when there was one and it surfaced as an exception. */
    val cause: Throwable? = null,
) {
    val isUsable: Boolean
        get() = outcome != NodeStartOutcome.Failed

    companion object {
        fun alreadyRunning() = NodeStartResult(NodeStartOutcome.AlreadyRunning, ownedStart = false)
        fun started() = NodeStartResult(NodeStartOutcome.Started, ownedStart = true)
        fun failed(cause: Throwable?) =
            NodeStartResult(NodeStartOutcome.Failed, ownedStart = true, cause = cause)
    }
}

enum class NodeStartOutcome {
    /** The node was already up; nothing was started. */
    AlreadyRunning,

    /** The node is up because of this call, or the call it attached to. */
    Started,

    /** The node is not up. */
    Failed,
}
