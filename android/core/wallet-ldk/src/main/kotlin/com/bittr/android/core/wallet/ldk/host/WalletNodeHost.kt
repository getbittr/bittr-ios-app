package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.node.NodeStartOutcome
import com.bittr.android.core.wallet.ldk.node.NodeStartResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Whatever is holding this process up while the node runs.
 *
 * On Android that is a foreground service; in a test it is a recorder; in a
 * build with no node configured it is [None]. The interface exists so the
 * ordering decisions in [WalletNodeHost] — promote *before* the start, demote
 * only on a definite failure — are provable on the JVM, which a `Service`
 * subclass in the same file would not be.
 *
 * Both methods are non-suspending and must be safe to call repeatedly. The host
 * calls [promote] on every start, including starts that turn out to be
 * no-ops, because "the node is up" and "the process is protected" have to be the
 * same fact and the cheapest way to keep them so is to re-assert it.
 */
interface ForegroundPresence {

    /** Take the process into the foreground. Called before the node start begins. */
    fun promote()

    /** Release it. Called when, and only when, the node is known to be down. */
    fun demote()

    /**
     * No foreground protection at all.
     *
     * The honest binding for a build that has no node to protect — see
     * `LdkEnvironment` and the app's wallet module — and the one the JVM tests
     * use when the presence is not what they are asserting about.
     */
    object None : ForegroundPresence {
        override fun promote() = Unit
        override fun demote() = Unit
    }
}

/**
 * A loop that must run for exactly as long as one node does.
 *
 * `EventPump.run()` is the first of these and states the contract this interface
 * exists to honour: it is *deliberately terminal* on a read failure, because
 * spinning on a failing FFI read burns the battery, and **the host restarts it
 * when the host restarts the node**. Anything with the same shape — the sync
 * loop BIT-123 will add — implements this rather than being launched by hand at
 * a call site that will forget the restart.
 */
interface NodeRunner {

    /** For logs and for [WalletNodeHost.onRunnerStopped]. Not an identity. */
    val name: String

    /** Runs until cancelled or until it decides to stop. */
    suspend fun run()
}

/**
 * The wallet's host: whose scope the node runs in, what holds the process up
 * while it does, and what has to be true before key material is erased.
 *
 * This is the piece BIT-122's scope item 4 said was missing. `NodeLifecycle`
 * starts and stops a node and owns the object; `NodeStartGate` arbitrates
 * callers; `EventPump` reads the queue. None of them decides *when*, and none of
 * them can, because the answer is an Android question: a start takes tens of
 * seconds, the user backgrounds the app halfway through it, and whether the work
 * survives that is a property of the scope it was launched in and of whether
 * anything is stopping the process being frozen.
 *
 * ## The scope is the process's, and the service is what protects it
 *
 * BIT-126's scope item 1 asks for "a foreground service that owns the wallet's
 * `CoroutineScope`". This host owns the scope instead, and the service is a
 * [ForegroundPresence] it promotes and demotes. The requirement the wording was
 * protecting — *the scope must outlive any individual caller* — is met either
 * way; the difference is what happens when the foreground service cannot start,
 * which on Android 12+ is a routine outcome rather than an error (a background
 * process that has not been granted an exemption gets
 * `ForegroundServiceStartNotAllowedException`).
 *
 * - With the scope inside the service, that exception has nowhere to go but the
 *   start: no service, no scope, no node. A restriction on *notification
 *   priority* would become a restriction on whether the wallet runs at all.
 * - With the scope here, the same exception degrades to "the node is running
 *   without foreground protection", which is strictly what an unprotected
 *   process already was, and the node start continues.
 *
 * The scope is therefore process-lifetime — which is the other half of the
 * issue's own phrasing, *"survives backgrounding, dies with the process"* — and
 * nothing in this class cancels it. What gets cancelled on [stop] is the
 * runners, explicitly, which is the thing that actually needs stopping.
 *
 * ## One start or stop at a time, including across a removal
 *
 * Every entry point takes [mutex]. That is heavier than it needs to be for
 * concurrent starts — [NodeLifecycle.startOnce] already collapses those, and a
 * caller that waits on the mutex and then finds the node up gets
 * [NodeStartOutcome.AlreadyRunning], which is the same answer — and it is exactly
 * what is needed for the case that matters: a [withWalletDown] racing a start.
 * Erasing the seed while a start is in flight is how a node gets built against a
 * wallet that no longer exists, and the mutex is what makes "stopped" mean
 * stopped rather than "asked to stop".
 *
 * The cost is that a removal triggered during a 30-second start waits for it.
 * That is the right side to err on: the alternative is a wipe that races the
 * thing holding the state directory open.
 *
 * Proved by `WalletNodeHostTest`.
 */
class WalletNodeHost(
    /**
     * The scope every start, and every runner, is launched in. Process-lifetime
     * — see the class comment. Never a `lifecycleScope` or a `viewModelScope`.
     */
    private val scope: CoroutineScope,
    private val lifecycle: NodeLifecycle,
    private val presence: ForegroundPresence,
    /** Restarted on every node start, cancelled on every stop. */
    private val runners: List<NodeRunner> = emptyList(),
    /**
     * A runner returned or threw while the node was still meant to be up.
     *
     * Not a restart hook, deliberately. `EventPumpStop.ReadFailed` is terminal
     * on purpose, and a host that relaunched it would reintroduce the spin the
     * pump refuses to do. What this is for is the report: BIT-123 is the issue
     * that decides what a dead pump should cost the user, and it needs to be
     * able to see one first. [Throwable] is null when the runner returned
     * normally.
     */
    private val onRunnerStopped: (String, Throwable?) -> Unit = { _, _ -> },
) {

    private val mutex = Mutex()

    /** Live only while a node is up and the runners for it are running. */
    private var runnerJobs: List<Job> = emptyList()

    /**
     * Bring the node up, holding the process up while it happens.
     *
     * Cancelling the caller does not cancel any of it — the start runs in
     * [scope] via `NodeStartGate`, and the runners are launched there too. That
     * is the whole reason the gate takes a scope, and it is what makes a
     * rotation during unlock survivable.
     */
    suspend fun start(): NodeStartResult = mutex.withLock {
        // Before the start, not after. A start that takes half a minute with the
        // app already backgrounded is the case this exists for, and a promotion
        // that happens once the node is up would have missed it.
        presence.promote()

        val result = try {
            lifecycle.startOnce()
        } catch (cancellation: CancellationException) {
            // Two different events arrive here and neither is a failed start.
            // Either this caller went away — a rotation, a screen closing —
            // while the start continues in `scope`, or `scope` itself is going
            // down with the process. Demoting on the first would drop the
            // foreground protection out from under a start that is still
            // running; on the second there is nothing left to demote.
            throw cancellation
        }

        if (!result.isUsable) {
            // Nothing is up, so nothing should be held up. The runners are
            // stopped as well as not started: a failed start after a successful
            // one leaves the previous node's runners reading a node that
            // `NodeLifecycle.buildAndStart` has already discarded.
            stopRunnersLocked()
            presence.demote()
            return@withLock result
        }

        when (result.outcome) {
            // A new node object. Whatever the runners were reading is gone, so
            // they are cancelled and relaunched rather than left attached — this
            // is EventPump's "restart it when you restart the node", made
            // structural instead of written down at a call site.
            NodeStartOutcome.Started -> restartRunnersLocked()

            // The node we already had. Its runners should still be running; if
            // one has stopped — a pump that took `ReadFailed` — this is the
            // moment it gets another life, because a caller has just asked for a
            // working wallet and would otherwise be handed one with a dead
            // event loop and no sign of it.
            NodeStartOutcome.AlreadyRunning -> if (!runnersAreLive()) restartRunnersLocked()

            NodeStartOutcome.Failed -> Unit // unreachable: !isUsable above.
        }

        result
    }

    /**
     * Take the wallet down.
     *
     * Safe when nothing is up — `WalletService.stop`'s stated contract, and
     * [NodeLifecycle.stop]'s. The order is runners, then node, then presence:
     *
     * - **Runners first, and joined.** A pump cancelled *after* the node stops
     *   is a pump that may be inside `eventHandled()` when the handle under it
     *   is freed. Cancelling and waiting means every runner has left the FFI
     *   before the node does.
     * - **Presence last, and unconditionally.** A node stop that throws still
     *   leaves `NodeLifecycle` believing it has no node — that is its documented
     *   behaviour — so a host that skipped the demote on that path would hold
     *   the process in the foreground forever, with a notification the user
     *   cannot dismiss and nothing running behind it.
     */
    suspend fun stop() = mutex.withLock { stopLocked() }

    /**
     * Stop the wallet, then run [block] with it guaranteed down.
     *
     * The ordering half of `WalletService.removeWallet`. iOS's
     * `CacheManager.deleteClientInfo()` runs only after the node has stopped and
     * the files are gone; the reason it can be written as a sequence there and
     * has to be a lock here is that on Android something else may be starting
     * the node at the same moment — a service restart, a second screen — and a
     * wipe that lands between `build()` and `start()` produces a node running
     * against a seed that has been erased.
     *
     * **This is not the cooperative channel close.** `WalletService.removeWallet`
     * says that is BIT-6's and it is still unimplemented;
     * `WipeSafety.channelsFullyClosedAndSwept` is the decision it will be built
     * from, and it needs the node *up* to answer — so it belongs above this
     * call, not inside it. What this guarantees is only that by the time [block]
     * runs, nothing holds the state directory and nothing will start a node
     * against key material that is about to go.
     *
     * The wallet is left down afterwards, including when [block] throws. There
     * is no restart on the failure path on purpose: a removal that got part-way
     * through is not a wallet to bring back up.
     */
    suspend fun <T> withWalletDown(block: suspend () -> T): T = mutex.withLock {
        stopLocked()
        block()
    }

    /** Whether a node is up right now. `NodeLifecycle.current`, as a question. */
    val isRunning: Boolean get() = lifecycle.current != null

    private suspend fun stopLocked() {
        stopRunnersLocked()
        try {
            lifecycle.stop()
        } finally {
            presence.demote()
        }
    }

    private suspend fun restartRunnersLocked() {
        stopRunnersLocked()
        runnerJobs = runners.map { runner ->
            scope.launch {
                try {
                    runner.run()
                    onRunnerStopped(runner.name, null)
                } catch (cancellation: CancellationException) {
                    // The ordinary stop. Not a report — the host asked for this.
                    throw cancellation
                } catch (failure: Throwable) {
                    onRunnerStopped(runner.name, failure)
                }
            }
        }
    }

    private suspend fun stopRunnersLocked() {
        val jobs = runnerJobs
        runnerJobs = emptyList()
        jobs.forEach { it.cancel() }
        // Joined, not just cancelled — see [stop]. `join` on an already-cancelled
        // job returns as soon as it has actually finished unwinding.
        jobs.forEach { it.join() }
    }

    private fun runnersAreLive(): Boolean =
        runnerJobs.size == runners.size && runnerJobs.all { it.isActive }
}
