package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.withTimeout

/**
 * One BDK full scan at a time, and every caller told how it went.
 *
 * Port of `BdkScanState` + `didSyncBdkWallet` + `lightSyncBdkWallet`
 * (`BDKManager.swift:17–95`, `:196–330`). The iOS shape is a lock, three flags
 * (`isScanning` / `hasBeenScanned` / `timedOut`), an array of waiter closures,
 * and a 180-second watchdog.
 *
 * Four call sites branch on those flags to decide whether the user may even open
 * the send screen (`SendViewController.swift:144`, `:317`,
 * `SendableAmount.swift:102`, `SwapViewController.swift:122`), and a fifth
 * raises an alert off `timedOut` (`AlertManager.swift:77`). They are UI state,
 * not diagnostics, which is why the defect below matters.
 *
 * ## The watchdog is rewritten, not ported, and this is the reason
 *
 * iOS schedules the watchdog with `asyncAfter(deadline: .now() + 180)` and never
 * cancels it (`BDKManager.swift:215–219`). `DispatchQueue.asyncAfter` has no
 * cancellation, so **the timer always fires at +180s, including long after its
 * own scan finished.** `markBdkScanTimedOut()` then does this:
 *
 * ```swift
 * guard _isScanning else { return }
 * _timedOut = true
 * ```
 *
 * The guard checks *whether a scan is running*, not *whether it is the scan this
 * timer belongs to*. So a scan that completes in two seconds leaves a live timer
 * that, three minutes later, flags whatever healthy scan happens to be running
 * at that moment as timed out — and `AlertManager` shows the user a scan-failed
 * alert for a scan that is fine. On iOS a full scan per launch makes the overlap
 * uncommon. On Android it is the normal case: process death is routine, every
 * start wipes BDK's store (see [BdkStore]) and so every start full-scans, and
 * Doze stretches a scan across the window where the previous timer is still
 * armed.
 *
 * A literal port would therefore import a latent iOS bug into the one place it
 * reliably fires. So the timeout here is scoped to the scan it belongs to, via
 * [generation]: a watchdog can only ever mark out the scan it was started for.
 * This is a defect fix, not a design deviation — the iOS *intent*, "tell the
 * caller after 180s", is preserved exactly, including the part where the scan
 * itself keeps running after the timeout is reported.
 *
 * ## The scan outlives the timeout on purpose
 *
 * iOS's watchdog calls `completion(false)` but never `endBdkScan`, so the claim
 * stays held and the scan runs on; a later caller attaches to it rather than
 * starting a second one. That is the right behaviour and it is kept: a full scan
 * is expensive and abandoning it would mean the next caller pays for it again.
 * [withTimeout] around the *await* rather than around the scan body is what
 * expresses it — the caller gives up waiting, the work does not give up running.
 *
 * Proved by `ScanCoordinatorTest`, including the cross-talk case as a negative
 * control: a timer from a finished scan must not mark a live one.
 */
class ScanCoordinator(
    /**
     * The scope the scan runs in. Must outlive any individual caller, for the
     * same reason `NodeStartGate` takes one: a `lifecycleScope` cancelled by a
     * rotation would otherwise cancel the scan out from under every caller
     * attached to it.
     */
    private val scope: CoroutineScope,
    /** iOS's 180 seconds (`BDKManager.swift:216`). Injected so tests need no wait. */
    private val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
) {

    private val lock = Any()

    private var inFlight: Deferred<Boolean>? = null

    /**
     * Which scan is current. Incremented per claimed scan so a watchdog can tell
     * "my scan" from "a scan" — the distinction iOS's guard is missing.
     */
    private var generation: Long = 0

    private var scanned = false
    private var timedOutGeneration: Long = -1

    /** `bdkWalletIsScanning`. A full scan is running right now. */
    val isScanning: Boolean get() = synchronized(lock) { inFlight != null }

    /** `bdkWalletHasBeenScanned`. A full scan has finished at least once since launch. */
    val hasBeenScanned: Boolean get() = synchronized(lock) { scanned }

    /**
     * `bdkFullScanTimedOut`. The scan running *now* passed its watchdog.
     *
     * False once that scan ends, and — unlike iOS — false for a scan whose
     * predecessor's watchdog fired.
     */
    val timedOut: Boolean
        get() = synchronized(lock) { inFlight != null && timedOutGeneration == generation }

    /**
     * Run a full scan, or attach to the one already running, and report whether
     * the wallet got scanned.
     *
     * @param scan the adapter's `startFullScan` → `fullScan` → `applyUpdate` →
     *   `persist` sequence. `true` if the update was applied.
     */
    suspend fun fullScan(scan: suspend () -> Boolean): Boolean {
        val attached: Deferred<Boolean>
        val myGeneration: Long

        synchronized(lock) {
            val existing = inFlight
            if (existing != null) {
                // iOS's waiter array, as an await. A caller that loses the race
                // is told the outcome rather than left on a spinner forever.
                attached = existing
                myGeneration = generation
            } else {
                generation += 1
                myGeneration = generation
                // LAZY for the same reason as NodeStartGate: a scan that
                // finishes before this block publishes it would clear a field
                // that has not been set, and the next caller attaches to a
                // corpse.
                val fresh = scope.async(start = CoroutineStart.LAZY) { runScan(scan) }
                fresh.invokeOnCompletion {
                    synchronized(lock) { if (inFlight === fresh) inFlight = null }
                }
                inFlight = fresh
                attached = fresh
            }
        }

        attached.start()
        return try {
            withTimeout(timeoutMillis) { attached.await() }
        } catch (timeout: TimeoutCancellationException) {
            // The watchdog. Marks *this* generation and nothing else, then
            // reports failure to the caller while leaving the scan running —
            // iOS's behaviour, minus the cross-talk.
            synchronized(lock) {
                if (generation == myGeneration && inFlight != null) {
                    timedOutGeneration = myGeneration
                }
            }
            false
        }
    }

    private suspend fun runScan(scan: suspend () -> Boolean): Boolean {
        val ok = scan()
        synchronized(lock) { if (ok) scanned = true }
        return ok
    }

    /**
     * Whether a light sync may run.
     *
     * Port of `lightSyncBdkWallet`'s first guard (`BDKManager.swift:285–288`):
     * *"Stand down while a full scan is running."* Both paths call
     * `applyUpdate` and `persist` against the same wallet and connection, and
     * BDK's `Wallet` is not safe to update from two places at once.
     */
    fun mayLightSync(): Boolean = !isScanning

    /** `clearBdkScanState()`. Forgets all of it — called on wallet teardown. */
    fun clear() {
        synchronized(lock) {
            inFlight = null
            scanned = false
            timedOutGeneration = -1
            // Bump so any watchdog still armed for the cleared scan cannot mark
            // the next one.
            generation += 1
        }
    }

    companion object {
        /** `BDKManager.swift:216`. */
        const val DEFAULT_TIMEOUT_MILLIS: Long = 180_000L
    }
}
