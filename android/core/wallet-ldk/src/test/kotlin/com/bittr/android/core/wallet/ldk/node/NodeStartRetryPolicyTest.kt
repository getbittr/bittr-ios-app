package com.bittr.android.core.wallet.ldk.node

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS's retry schedule, asserted rather than re-derived.
 *
 * `didStartNode` (`BitcoinManager.swift:220–265`) is four conditions in one
 * `guard`, and each of them is load-bearing: attempts left, inside the ten-
 * second budget, and the error is one where waiting helps. Getting any of them
 * wrong is invisible in normal use and shows up as either a start that gives up
 * on a slow network or one that hammers a broken node for a minute.
 *
 * The clock is injected, which is the only reason this file runs in
 * milliseconds instead of taking half a minute.
 */
class NodeStartRetryPolicyTest {

    private val policy = NodeStartRetryPolicy()

    @Test
    fun `the schedule is iOS's — 1s then 3s, three attempts, ten second budget`() {
        assertEquals(listOf(1_000L, 3_000L), policy.delaysMillis)
        assertEquals(10_000L, policy.totalDeadlineMillis)

        assertEquals(1_000L, policy.retryDelayMillis(attempt = 1, elapsedMillis = 0, retryable = true))
        assertEquals(3_000L, policy.retryDelayMillis(attempt = 2, elapsedMillis = 1_100, retryable = true))
        assertNull(
            "Attempt 3 is the last — `attempt <= nodeStartRetryDelays.count` on iOS.",
            policy.retryDelayMillis(attempt = 3, elapsedMillis = 4_200, retryable = true),
        )
    }

    @Test
    fun `a non-retryable failure is not retried, however early it happens`() {
        assertNull(
            "Retrying a corrupt store or an invalid network three times only delays the " +
                "error the user needs to see.",
            policy.retryDelayMillis(attempt = 1, elapsedMillis = 0, retryable = false),
        )
    }

    @Test
    fun `the budget stops a retry that would start after it has expired`() {
        assertNull(
            policy.retryDelayMillis(attempt = 1, elapsedMillis = 10_000, retryable = true),
        )
        assertEquals(
            "One millisecond inside the budget is still inside it.",
            1_000L,
            policy.retryDelayMillis(attempt = 1, elapsedMillis = 9_999, retryable = true),
        )
    }

    @Test
    fun `a start that succeeds first time does not wait`() = runTest {
        val waits = mutableListOf<Long>()
        val attempts = runner(waits, retryable = true).run(startNode = {}, isRunning = { false })

        assertTrue(attempts.started)
        assertEquals(1, attempts.attempts)
        assertEquals(emptyList<Long>(), waits)
    }

    @Test
    fun `a retryable failure is retried on iOS's schedule and then gives up`() = runTest {
        val waits = mutableListOf<Long>()
        val failure = RuntimeException("connection failed")

        val attempts = runner(waits, retryable = true)
            .run(startNode = { throw failure }, isRunning = { false })

        assertFalse(attempts.started)
        assertEquals("Three attempts, as on iOS.", 3, attempts.attempts)
        assertEquals(listOf(1_000L, 3_000L), waits)
        assertSame(failure, attempts.lastError)
        assertFalse(attempts.recoveredByStatusCheck)
    }

    @Test
    fun `a clock that advances past the budget cuts the retries short`() = runTest {
        // The deadline is measured, not assumed: a first attempt that itself
        // takes eleven seconds (a chain source that accepts the connection and
        // then hangs) must not be followed by two more.
        val waits = mutableListOf<Long>()
        var now = 0L
        val runner = NodeStartRunner(
            classifier = { true },
            elapsedRealtimeMillis = { now },
            wait = { waits += it },
        )

        val attempts = runner.run(
            startNode = { now += 11_000; throw RuntimeException("hung") },
            isRunning = { false },
        )

        assertFalse(attempts.started)
        assertEquals(1, attempts.attempts)
        assertEquals(emptyList<Long>(), waits)
    }

    @Test
    fun `a start that throws but leaves the node running counts as started`() = runTest {
        // `StartLightning.swift:156–158`. On Android this is the routine
        // outcome of starting a node that is already up — ldk-node throws
        // AlreadyRunning rather than returning — so without this check a healthy
        // node is reported to the user as a failed start.
        val attempts = runner(mutableListOf(), retryable = false)
            .run(startNode = { throw RuntimeException("already running") }, isRunning = { true })

        assertTrue(attempts.started)
        assertTrue(
            "The distinction is worth keeping: it means something outside NodeStartGate " +
                "started the node.",
            attempts.recoveredByStatusCheck,
        )
    }

    @Test
    fun `a status check that itself throws does not mask the start failure`() = runTest {
        // `status()` goes through the same FFI as `start()`, so a node that is
        // too broken to start can be too broken to answer. Letting that throw
        // would replace a reportable failure with a crash inside the retry loop.
        val failure = RuntimeException("chain source unreachable")
        val attempts = runner(mutableListOf(), retryable = false).run(
            startNode = { throw failure },
            isRunning = { error("FFI call on a dead node") },
        )

        assertFalse(attempts.started)
        assertSame(failure, attempts.lastError)
    }

    private fun runner(waits: MutableList<Long>, retryable: Boolean) = NodeStartRunner(
        classifier = { retryable },
        // Advance by each wait, so `elapsed` tracks the schedule without the
        // test taking four seconds.
        elapsedRealtimeMillis = { waits.sum() },
        wait = { waits += it },
    )
}
