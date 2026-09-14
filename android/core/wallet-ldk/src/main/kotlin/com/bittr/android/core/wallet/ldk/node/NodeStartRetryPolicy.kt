package com.bittr.android.core.wallet.ldk.node

/**
 * How many times, and for how long, a failing node start is retried.
 *
 * Port of `BitcoinManager.didStartNode` (`BitcoinManager.swift:220–265`): three
 * attempts at most, waiting 1s then 3s, abandoned entirely once ten seconds
 * have passed, and only for errors that are connectivity-related. The numbers
 * are iOS's; this class exists so they are stated once and asserted against
 * rather than re-derived inside a retry loop.
 *
 * ## The clock this is measured against is an Android decision
 *
 * iOS measures the deadline with `-startedAt.timeIntervalSinceNow` — wall
 * clock. Wall clock is the wrong source here on Android for two reasons that do
 * not arise on iOS with the same force:
 *
 * - **It can move under you.** An NTP correction or a user changing the date
 *   mid-start can make the deadline expire on attempt one, or never.
 * - **`uptimeMillis` is the other trap.** It *stops* during deep sleep, so a
 *   start begun just before the device dozed would come back hours later
 *   believing no time had passed, and retry into a node that has lost its peer
 *   connections.
 *
 * So the runner takes an elapsed-realtime source: monotonic, unaffected by the
 * user or NTP, and *including* deep sleep — the closest thing on Android to
 * what iOS's wall-clock subtraction means, minus the ways it can lie.
 * `SystemClock.elapsedRealtime()` in production, injected in tests, which is
 * also what lets the deadline be tested without a ten-second test.
 */
class NodeStartRetryPolicy(
    /**
     * Delay before attempt *n+1*, indexed from attempt 1. Its size is also the
     * retry budget: `[1s, 3s]` means attempts 1 and 2 may be retried, and
     * attempt 3 is the last.
     */
    val delaysMillis: List<Long> = listOf(1_000L, 3_000L),
    /**
     * Total budget from the first attempt. iOS's ten seconds — a bound on how
     * long a user stares at a spinner, not on how long a start "should" take.
     */
    val totalDeadlineMillis: Long = 10_000L,
) {

    /**
     * How long to wait before the next attempt, or `null` to stop trying.
     *
     * @param attempt 1-based number of the attempt that just failed.
     * @param elapsedMillis since the first attempt began.
     * @param retryable whether the failure was connectivity-related.
     */
    fun retryDelayMillis(attempt: Int, elapsedMillis: Long, retryable: Boolean): Long? {
        if (!retryable) return null
        // `attempt <= delays.count` on iOS: attempt 1 waits delays[0], attempt 2
        // waits delays[1], attempt 3 has nothing left to wait for.
        if (attempt > delaysMillis.size) return null
        if (elapsedMillis >= totalDeadlineMillis) return null
        return delaysMillis[attempt - 1]
    }
}

/**
 * Which start failures are worth retrying.
 *
 * Declared here as an interface with no ldk-node type in it so the retry loop
 * stays provable on the JVM; the implementation that names `NodeException`
 * cases lives in the adapter package. See `WalletLayeringGuardTest`.
 */
fun interface NodeStartErrorClassifier {
    fun isRetryable(error: Throwable): Boolean
}

/**
 * The retry loop itself: iOS's `didStartNode`, with its two implicit clocks made
 * explicit and its post-hoc success check kept.
 *
 * That last part is easy to drop and matters. `StartLightning.swift:156–158`
 * does this after `didStartLDK()` returns false:
 *
 * ```swift
 * if !didStartNode, BitcoinManager.shared.status()?.isRunning == true {
 *     didStartNode = true
 * }
 * ```
 *
 * On Android that branch is not a curiosity — it is the routine outcome of
 * starting a node that is already up, because ldk-node signals it by throwing
 * `NodeException.AlreadyRunning` rather than returning quietly. A process whose
 * foreground service is restarted while the old node object is still alive hits
 * exactly this. Without the check, the app would treat a perfectly healthy node
 * as a failed start and show the user the retry alert.
 */
class NodeStartRunner(
    private val policy: NodeStartRetryPolicy = NodeStartRetryPolicy(),
    private val classifier: NodeStartErrorClassifier,
    /** Monotonic, deep-sleep-inclusive. See the policy's class comment. */
    private val elapsedRealtimeMillis: () -> Long,
    /** Cancellable wait. `kotlinx.coroutines.delay` in production. */
    private val wait: suspend (Long) -> Unit,
) {

    /**
     * Run `startNode` until it succeeds, the budget runs out, or the failure is
     * not one worth retrying.
     *
     * @param startNode throws on failure, as `Node.start()` does.
     * @param isRunning consulted only after a failure — the post-hoc check above.
     */
    suspend fun run(startNode: () -> Unit, isRunning: () -> Boolean): NodeStartAttempts {
        val startedAt = elapsedRealtimeMillis()
        var attempt = 1

        while (true) {
            try {
                startNode()
                return NodeStartAttempts(started = true, attempts = attempt)
            } catch (error: Throwable) {
                if (error is kotlinx.coroutines.CancellationException) throw error

                val delay = policy.retryDelayMillis(
                    attempt = attempt,
                    elapsedMillis = elapsedRealtimeMillis() - startedAt,
                    retryable = classifier.isRetryable(error),
                )

                if (delay == null) {
                    // Out of retries. Before calling it a failure, ask the node
                    // whether it is up anyway — see the class comment.
                    val alreadyUp = runCatching { isRunning() }.getOrDefault(false)
                    return NodeStartAttempts(
                        started = alreadyUp,
                        attempts = attempt,
                        lastError = error,
                        recoveredByStatusCheck = alreadyUp,
                    )
                }

                wait(delay)
                attempt++
            }
        }
    }
}

/** Outcome of [NodeStartRunner.run], with enough detail to log what happened. */
data class NodeStartAttempts(
    val started: Boolean,
    val attempts: Int,
    val lastError: Throwable? = null,
    /**
     * True when the start threw but the node turned out to be running. Worth
     * separating from a clean start: it means something else started the node,
     * and on Android that is usually a second entry point into the wallet that
     * should have gone through [NodeStartGate].
     */
    val recoveredByStatusCheck: Boolean = false,
)
