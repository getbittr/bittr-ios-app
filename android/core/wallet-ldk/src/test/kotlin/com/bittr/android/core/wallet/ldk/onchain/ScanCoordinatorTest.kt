package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

/**
 * Single-flight scanning, and the watchdog that must not flag the wrong scan.
 *
 * The last test is the negative control for the iOS defect this class fixes; if
 * the generation check is removed, it is the one that fails.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ScanCoordinatorTest {

    @Test
    fun `concurrent callers produce exactly one scan and all get the outcome`() = runTest {
        val coordinator = ScanCoordinator(this)
        val scans = AtomicInteger(0)
        val release = CompletableDeferred<Unit>()

        val callers = (1..5).map {
            async {
                coordinator.fullScan {
                    scans.incrementAndGet()
                    release.await()
                    true
                }
            }
        }

        // Let all five reach the gate before any scan can finish. `runCurrent`,
        // not `advanceUntilIdle`: the latter advances virtual time through every
        // pending task, which includes this coordinator's 180-second watchdog —
        // so it would fire the timeout in a test that is not about the timeout.
        testScheduler.runCurrent()
        release.complete(Unit)

        val outcomes = callers.map { it.await() }
        assertEquals("Exactly one scan must have run", 1, scans.get())
        assertTrue("Every caller must be told the outcome", outcomes.all { it })
        assertTrue(coordinator.hasBeenScanned)
        assertFalse(coordinator.isScanning)
    }

    @Test
    fun `a failed scan does not set hasBeenScanned`() = runTest {
        val coordinator = ScanCoordinator(this)
        assertFalse(coordinator.fullScan { false })
        assertFalse(
            "hasBeenScanned gates the send screen — a failed scan must not open it",
            coordinator.hasBeenScanned,
        )
    }

    @Test
    fun `the watchdog reports failure to the caller but leaves the scan running`() = runTest {
        val coordinator = ScanCoordinator(this, timeoutMillis = 1_000L)
        val release = CompletableDeferred<Unit>()
        val finished = CompletableDeferred<Unit>()

        val caller = async {
            coordinator.fullScan {
                release.await()
                finished.complete(Unit)
                true
            }
        }

        advanceTimeBy(1_500L)

        assertFalse("The caller must be told it timed out", caller.await())
        assertTrue("And the flag the alert reads must be set", coordinator.timedOut)
        assertTrue("But the scan must still be running, not abandoned", coordinator.isScanning)

        // iOS keeps the claim held so the expensive scan is not paid for twice.
        release.complete(Unit)
        testScheduler.advanceUntilIdle()
        assertTrue("The scan completes on its own terms", finished.isCompleted)
        assertTrue("And its success still registers", coordinator.hasBeenScanned)
    }

    @Test
    fun `timedOut clears once the timed-out scan ends`() = runTest {
        val coordinator = ScanCoordinator(this, timeoutMillis = 1_000L)
        val release = CompletableDeferred<Unit>()

        val caller = async { coordinator.fullScan { release.await(); true } }
        advanceTimeBy(1_500L)
        assertTrue(coordinator.timedOut)

        caller.await()
        release.complete(Unit)
        testScheduler.advanceUntilIdle()

        assertFalse("A finished scan is not a timed-out scan", coordinator.timedOut)
    }

    @Test
    fun `a light sync stands down while a full scan is running`() = runTest {
        val coordinator = ScanCoordinator(this)
        val release = CompletableDeferred<Unit>()

        val caller = async { coordinator.fullScan { release.await(); true } }
        testScheduler.runCurrent()

        assertFalse(
            "Both paths applyUpdate and persist against the same Wallet",
            coordinator.mayLightSync(),
        )

        release.complete(Unit)
        caller.await()
        assertTrue(coordinator.mayLightSync())
    }

    @Test
    fun `clear forgets the scan state`() = runTest {
        val coordinator = ScanCoordinator(this)
        coordinator.fullScan { true }
        assertTrue(coordinator.hasBeenScanned)

        coordinator.clear()

        assertFalse(coordinator.hasBeenScanned)
        assertFalse(coordinator.isScanning)
        assertFalse(coordinator.timedOut)
    }

    @Test
    fun `a timed-out scan does not leave the next scan flagged`() = runTest {
        // The iOS defect, as a negative control. On iOS `markBdkScanTimedOut`
        // guards on `_isScanning` — "is *a* scan running" — not on *which* scan
        // the timer belongs to, and `DispatchQueue.asyncAfter` cannot be
        // cancelled, so a stale watchdog flags whatever is running when it fires.
        // The user gets a scan-failed alert (AlertManager.swift:77) for a healthy
        // scan. On Android that overlap is the normal case, not a rarity.
        //
        // The sequence below is the one that distinguishes the two designs:
        // scan A times out, A then finishes anyway, and scan B starts. B must be
        // clean. Remove the `timedOutGeneration == generation` comparison and B
        // inherits A's timed-out flag, which is exactly the iOS behaviour.
        val coordinator = ScanCoordinator(this, timeoutMillis = 1_000L)
        val releaseA = CompletableDeferred<Unit>()

        val a = async { coordinator.fullScan { releaseA.await(); true } }
        advanceTimeBy(1_500L)
        assertFalse("A's caller gave up", a.await())
        assertTrue("A is flagged while it is still the current scan", coordinator.timedOut)

        // A finishes on its own terms, after its caller walked away.
        releaseA.complete(Unit)
        testScheduler.runCurrent()

        // B is healthy and still running. `runCurrent` again: advancing the clock
        // here would run B past its own 1s watchdog and the assertion below would
        // be testing B's timeout rather than A's flag leaking onto it.
        val releaseB = CompletableDeferred<Unit>()
        val b = async { coordinator.fullScan { releaseB.await(); true } }
        testScheduler.runCurrent()

        assertTrue("B is running", coordinator.isScanning)
        assertFalse(
            "B is a healthy scan and must not inherit A's timed-out flag. If this " +
                "fails, the generation comparison has been dropped and the iOS " +
                "cross-talk defect is back — the user sees a scan-failed alert for " +
                "a scan that is fine.",
            coordinator.timedOut,
        )

        releaseB.complete(Unit)
        assertTrue(b.await())
    }
}
