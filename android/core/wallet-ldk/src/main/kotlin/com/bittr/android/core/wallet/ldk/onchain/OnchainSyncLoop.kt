package com.bittr.android.core.wallet.ldk.onchain

import com.bittr.android.core.wallet.ldk.host.NodeRunner
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The BDK wallet's own lifetime, as the two calls a loop needs from it.
 *
 * Port of `didStartBDK()` and `clearBdkWalletReferences()`
 * (`BDKManager.swift:98–183`) reduced to what [OnchainSyncLoop] decides against.
 * The implementation is `BdkOnchainWalletHolder`, in `adapter/`, and it is a
 * field assignment either side of `BdkWalletFactory.open`.
 */
interface OnchainWalletPort {

    /**
     * `didStartBDK()`. True if a wallet is open by the time this returns.
     *
     * Idempotent — iOS's `guard self.bdkWallet == nil else { return true }` — and
     * false rather than throwing on every failure iOS handles, including the one
     * that is not an error: no mnemonic, because the wallet is being torn down.
     */
    fun open(): Boolean

    /** `clearBdkWalletReferences()`. Safe when nothing is open, and safe twice. */
    fun close()
}

/**
 * The node balance read this loop lends its clock to.
 *
 * `WalletBalanceReader.read()`, as a seam with no `lightning/` type in it —
 * `onchain/` does not depend on the node views and should not start. What the
 * loop needs from it is only whether a reading happened, which is what it
 * reports.
 *
 * **Must not throw.** The implementation swallows and reports through its own
 * `onFailure`; an exception out of here would end the runner and with it the
 * light-sync timer, which is the cost [OnchainSyncLoop] spells out for a failed
 * full scan and is far more than a missed cache write is worth.
 */
fun interface WalletBalanceRead {

    /** @return true if a reading was taken, false if there was no node to read. */
    fun read(): Boolean
}

/** What the loop did, for the log and for [OnchainSyncLoopTest]'s assertions. */
enum class OnchainLoopEvent {

    /** [OnchainWalletPort.open] said no. Nothing else in this list will follow. */
    WalletUnavailable,

    /** The start's full scan applied. The light-sync timer follows. */
    FullScanApplied,

    /** It did not, so there is no timer. See [OnchainSyncLoop] on what revives it. */
    FullScanFailed,

    /** The loaded wallet had a stored full scan, and a light sync brought it up to date. */
    LoadedWalletLightSynced,

    /** A scan had already succeeded for this process, so the loop light-synced and went to the timer. */
    AlreadyScanned,

    /** A periodic light sync reached the wallet. */
    LightSyncApplied,

    /** One did not — no wallet, a full scan or another light sync in the way, or the network. */
    LightSyncSkipped,

    /** A balance reading was taken and its cache writes were made. See [WalletBalanceRead]. */
    BalancesRead,

    /** There was no node to read, so nothing was cached. Routine between a stop and a start. */
    BalancesUnavailable,
}

/**
 * `startBDK()` plus `BackgroundSync`, as the runner that holds them to one node.
 *
 * Port of `StartLightning.swift:165–214` and `BackgroundSync.swift:11–33`. This
 * is the piece that was missing after BIT-124: `BdkWalletFactory.open` and
 * [OnchainSync] both existed and **nothing in `main` called either of them**, so
 * the on-chain half of the wallet was code with no caller. This is the caller,
 * and the reason it is a [NodeRunner] rather than a line in `WalletNodeHost` is
 * that the host already solved the hard part — cancelled on every stop,
 * relaunched on every start — for the event pump.
 *
 * ## The sequence, and the two guards that are iOS's
 *
 * 1. **Open the wallet.** A failure ends the runner. iOS logs "Could not start
 *    BDK" and returns; there is nothing else to do, because every step below
 *    needs the wallet.
 * 2. **Bring the wallet up to date** — `startBDK()` since PR #99:
 *    - A scan has already succeeded in this process: light sync at once, then the
 *      timer. [ScanCoordinator] outlives a *node* restart within one process, and a
 *      second node start should not pay for a second full scan.
 *    - The loaded wallet has a stored full scan ([BdkScanRecord.hasStoredFullScan]):
 *      light sync it, and count it as scanned only once that sync succeeds
 *      (`lightSyncLoadedBDKWallet`). Skipped for another light sync, it tries again
 *      after [LOADED_WALLET_RETRY_MILLIS]. Skipped for a full scan, it waits on that
 *      scan. Failed, the loaded data may be stale, so it scans in full.
 *    - Otherwise a full scan.
 * 3. **Only then the timer.** iOS's `guard hasBeenSynced else { return }`: a
 *    failed full scan gets no light-sync timer, because a light sync only
 *    revisits scripts the wallet has already revealed and a wallet that never
 *    scanned has revealed none. Syncing on that would be round trips that cannot
 *    find anything.
 *
 * ## The balance read rides this clock, and that was a decision
 *
 * [balances] runs after the start's scan and after every light-sync tick. It is
 * the node read `WalletBalanceReader` needs — the port of `loadWalletData()`,
 * which writes the funding outpoint the closure scan watches for.
 *
 * iOS triggers it from two places, and Android has neither. One is the home
 * screen's load; there is no home screen. The other is the light-sync comparison
 * at `BitcoinManager.swift:496`, and that one **does** have a counterpart: this
 * loop's timer is `BackgroundSync`'s, 30 seconds, already running for as long as
 * a node is up. So the choice was between borrowing it and adding a second
 * timer, and the second timer is what is being refused:
 *
 * - It costs a wakeup. A `NodeRunner` with its own `delay` is a second coroutine
 *   the OS has to keep scheduled while the app is backgrounded, for a read whose
 *   only consumer today is three cache writes. K8's measurement of what Doze
 *   costs the wallet is the reason to add timers reluctantly.
 * - It buys nothing. The two would have the same period and the same lifetime —
 *   cancelled by the host on every stop, relaunched on every start — so the only
 *   difference would be that they drift apart.
 *
 * The read is **after** each sync, not before, and that ordering is load-bearing
 * rather than incidental. `OnchainSync` runs the closure scan at the end of a
 * sync that applied; the balance read's third write clears the funding outpoint
 * once a closure is pending. Reading first would clear the outpoint in the same
 * tick that the scan was about to use it, and the closing transaction would
 * never be recorded. Reading after gives the scan the outpoint on every tick
 * until it finds the closure itself.
 *
 * **What this costs is stated rather than hidden: a failed full scan takes the
 * balance read down with it**, because the `return` below ends the runner and
 * the read has no clock of its own. The two are not otherwise related — the
 * balance read is a *node* read and does not need BDK at all — so a wallet whose
 * Electrum server is down stops writing the funding outpoint as well as stopping
 * its on-chain sync. That is acceptable while the read's only consumer is the
 * closure scan, which also only runs off an applied sync. It stops being
 * acceptable the day the drain clamp or a balance screen reads the snapshot, and
 * the answer then is to give the read its own runner rather than to soften the
 * `return`.
 *
 * iOS's third guard — `guard !bdkWalletIsScanning else { return }` at the top of
 * `startBDK()` — is not ported as a branch because the host makes it structural:
 * one runner per node, cancelled and *joined* before the next is launched. The
 * check would be dead code, and dead code in a guard is worse than none.
 *
 * ## Light syncs run beside the loop, as `BackgroundSync`'s do
 *
 * iOS's timer fires every 30 seconds and runs each light sync on a background
 * queue without waiting for the last one. The claim in [ScanCoordinator] keeps
 * two from updating the wallet together, and one that has held it for two
 * minutes counts as hung: the next takes over and reconnects to Electrum. The
 * same holds here, because each tick is launched in [lightSyncScope] rather
 * than run on this coroutine. Run inline, a light sync stuck in an Electrum call
 * would stop every tick, every balance read and every rebuild after it.
 *
 * ## Pulling to refresh rebuilds the wallet
 *
 * `ReloadWallet.swift` since PR #99: the reset marks the wallet as needing a
 * rebuild ([BdkScanRecord.requestRebuild], [ScanCoordinator.markNeedsFullScan]),
 * and [rebuildNow] then runs a full scan, which first builds the wallet again
 * from an empty database. The timer is paused from the moment of the pull
 * ([pauseLightSyncs]), as iOS stops `BackgroundSync`, and starts again once the
 * scan has run. A rebuild or scan that fails keeps the loop and the wallet, and
 * each tick after it tries the full scan again until one succeeds.
 *
 * ## What a failed full scan costs, and what revives it
 *
 * **A failed full scan at the start gets no timer, and is tried again each time
 * the app returns to the foreground**, until one succeeds — iOS's
 * `appWillEnterForeground` → `startBDK()` (#95). The wallet stays open meanwhile,
 * and a pull to refresh that arrives is run then rather than left waiting. Only
 * once a scan succeeds does the timer start. Without [foregroundReturns] the
 * runner ends instead, and `WalletNodeHost.start()` on unlock relaunches it. A
 * refresh is different: the wallet was scanned and open, so a failed rebuild
 * keeps both and its ticks retry, see above.
 *
 * ## The teardown is Android's, and it is not decoration
 *
 * iOS nils the wallet, the connection and the Electrum client on node teardown
 * and clears the scan flags beside them (`BitcoinManager.swift:680–689`); ARC
 * does the rest. Here the same two calls are in a `finally`, so they also run on
 * *cancellation*, which is how a stop arrives on Android and does not exist on
 * iOS at all.
 *
 * The order is scan state, then wallet — the reverse of the iOS listing and
 * deliberately so. [ScanCoordinator.clear] bumps the generation, so a watchdog
 * still armed for the scan being abandoned cannot mark the next node's scan;
 * doing it after the close would leave a window where the flags describe a
 * wallet that is gone.
 *
 * **Closing under a running scan is safe, and it is checkable.** A full scan
 * runs in [ScanCoordinator]'s scope rather than this runner's — deliberately,
 * so a caller giving up does not abandon the scan — so cancelling the runner
 * does not stop it, and this `finally` can close a wallet a scan is still
 * inside. bdk-android's generated objects carry a `callCounter: AtomicLong`
 * beside `wasDestroyed`, and `destroy()` frees the pointer *only* when its
 * decrement reaches zero (`javap -c org/bitcoindevkit/Wallet.class`), so an
 * in-flight call holds the handle open and the free is deferred until it
 * returns. What the scan gets is an `IllegalStateException` on its *next* call,
 * which [OnchainSync] catches into a `NotApplied` — the right answer for a scan
 * whose wallet has been torn down. This is a use-after-free that the binding
 * rules out, not one this code is careful about.
 *
 * A scan that outlives its runner must not act on the next wallet either. It
 * carries its generation, which [ScanCoordinator.clear] retires: a rebuild it
 * was waiting to run refuses, and its success does not mark the next wallet as
 * scanned. `BdkOnchainWalletHolder.reopen` also refuses a holder that has been
 * closed.
 *
 * Proved by `OnchainSyncLoopTest`.
 */
class OnchainSyncLoop(
    private val wallet: OnchainWalletPort,
    /**
     * The sync sequence, over whatever the port's types are.
     *
     * Star-projected because nothing here touches them: [OnchainSync.fullScan]
     * returns `Boolean` and [OnchainSync.lightSync] a [LightSyncOutcome]. That is also what lets
     * `di/WalletModule` hold one — `:app` cannot name `org.bitcoindevkit.Wallet`,
     * because `:core:wallet-ldk` depends on bdk-android with `implementation`.
     */
    private val sync: OnchainSync<*, *, *, *>,
    /** The same instance [sync] was built with. Read for `hasBeenScanned`, cleared on the way out. */
    private val scans: ScanCoordinator,
    /**
     * The stored full scan, read at the start. Null for a wallet that keeps none, which
     * then always scans in full. Nullable but not defaulted, for the reason [balances] gives.
     */
    private val record: BdkScanRecord?,
    /**
     * The node balance read, run after the start's scan and after every tick.
     *
     * **Nullable but not defaulted**, for the reason [OnchainSync.closures]
     * gives: a defaulted collaborator is a wiring step that can be forgotten in
     * silence, and this one has already been forgotten once — that is the whole
     * of BIT-144. A production `OnchainSyncLoop(wallet, sync, scans)` would
     * compile, run, sync correctly and write no funding outpoint, and nothing
     * about it would read as wrong. Null is still a legitimate answer — it is
     * what most of `OnchainSyncLoopTest` wants — it just has to be written down.
     */
    private val balances: WalletBalanceRead?,
    /**
     * Each return of the app to the foreground, which retries a start whose scan failed.
     * Nullable but not defaulted, for the reason [balances] gives: null ends the runner
     * after a failed scan, as before.
     */
    private val foregroundReturns: Flow<Unit>?,
    /**
     * Where the timer's light syncs run, so a hung one never holds up the loop. Must
     * outlive any one run, for the reason [ScanCoordinator]'s scope does.
     */
    private val lightSyncScope: CoroutineScope,
    /** `BackgroundSync.swift:18`. Injected so the test needs no wall clock. */
    private val lightSyncIntervalMillis: Long = LIGHT_SYNC_INTERVAL_MILLIS,
    /** Every step, in order. A log line in production; the assertion in the test. */
    private val report: (OnchainLoopEvent) -> Unit = {},
) : NodeRunner {

    override val name: String = NAME

    /** Requests to rebuild the wallet, from Home's pull-to-refresh. */
    private val rebuildRequests = Channel<CompletableDeferred<Boolean>>(Channel.UNLIMITED)

    /** Whether the timer's light syncs are paused, between a pull and its rebuild. */
    @Volatile
    private var lightSyncsPaused = false

    /**
     * `resetWallet()`'s `walletSync.stop()`: pause the timer's light syncs from the moment of
     * the pull, so none is running when the rebuild wants the stored database. The rebuild
     * starts them again, as does the next run.
     */
    fun pauseLightSyncs() {
        lightSyncsPaused = true
    }

    /**
     * Rebuild the wallet from an empty database and scan it in full, on this loop's
     * coroutine — `ReloadWallet.swift`'s `didSyncBdkWallet` after the pull.
     *
     * The request is stored first ([BdkScanRecord.requestRebuild]), so the next start still
     * rebuilds if this run doesn't.
     *
     * @return whether a balance reading was taken after the scan. Suspends until the loop
     *   gets to it, which is never while the loop is not running: the caller bounds the
     *   wait. A request still waiting when a run starts is answered with no reading, since
     *   that run's own open has rebuilt the wallet.
     */
    suspend fun rebuildNow(): Boolean {
        record?.requestRebuild()
        val answer = CompletableDeferred<Boolean>()
        rebuildRequests.send(answer)
        return answer.await()
    }

    override suspend fun run() {
        // The timer's light syncs belong to this run, and are cancelled on the way out, so
        // none acts on the wallet after the run has let it go.
        val ticks = SupervisorJob(lightSyncScope.coroutineContext[Job])
        try {
            answerPendingRebuilds(false)
            lightSyncsPaused = false

            if (!wallet.open()) {
                report(OnchainLoopEvent.WalletUnavailable)
                return
            }

            if (scans.hasBeenScanned) {
                report(OnchainLoopEvent.AlreadyScanned)
                // Light sync at once. The tick reads the balances after it, so this
                // branch takes no separate node-start read.
                launchTick(ticks)
            } else {
                val retried = if (bringUpToDate(ticks)) null else retryUntilScanned(ticks) ?: return
                // The node-start read, which also answers a rebuild the retry ran.
                val read = readBalances()
                retried?.rebuild?.complete(read)
            }

            while (true) {
                // Before the first sync, not after: iOS schedules the timer at
                // `.now() + 30`, and the start immediately above has just read the
                // chain. A rebuild request interrupts the wait.
                val rebuild = withTimeoutOrNull(lightSyncIntervalMillis) { rebuildRequests.receive() }
                if (rebuild == null) {
                    launchTick(ticks)
                    continue
                }

                // The timer stays paused for the rebuild. A rebuild that fails keeps the
                // loop and the wallet: the ticks after it try the full scan again.
                val scanned = sync.fullScan()
                report(if (scanned) OnchainLoopEvent.FullScanApplied else OnchainLoopEvent.FullScanFailed)
                lightSyncsPaused = false
                rebuild.complete(if (scanned) readBalances() else false)
            }
        } finally {
            // Non-suspending, all of them, which is what makes this correct on
            // the cancellation path — a `suspend` call in a `finally` after a
            // cancellation needs `NonCancellable` to run at all, and none of
            // these does.
            ticks.cancel()
            answerPendingRebuilds(false)
            scans.clear()
            wallet.close()
        }
    }

    /**
     * The start's scan, unless a stored one can be brought up to date by a light sync.
     *
     * The light sync runs in [lightSyncScope] and is awaited, so a stop is not held up by
     * an Electrum call that hangs: the await is cancelled, and the call is left to end.
     *
     * @return whether the wallet counts as scanned. False starts no timer: the start is
     *   retried on the next return to the foreground (see [retryUntilScanned]).
     */
    private suspend fun bringUpToDate(ticks: Job): Boolean {
        if (record?.hasStoredFullScan == true) {
            // A previously scanned wallet only counts as scanned once a light sync brings it up to date.
            while (true) {
                when (lightSyncScope.async(ticks) { sync.lightSync() }.await()) {
                    LightSyncOutcome.Synced -> {
                        scans.markPreviouslyScanned()
                        report(OnchainLoopEvent.LoadedWalletLightSynced)
                        return true
                    }
                    LightSyncOutcome.SkippedForLightSync -> {
                        // Try again once the running light sync has had time to finish.
                        delay(LOADED_WALLET_RETRY_MILLIS)
                        if (scans.hasBeenScanned) return true
                    }
                    // Wait for the running full scan instead, or, when the loaded data may
                    // be stale, scan in full.
                    LightSyncOutcome.SkippedForFullScan, LightSyncOutcome.Failed -> break
                }
            }
        }

        val scanned = sync.fullScan()
        report(if (scanned) OnchainLoopEvent.FullScanApplied else OnchainLoopEvent.FullScanFailed)
        return scanned
    }

    /** A start that succeeded on a retry, with the rebuild it ran, if it was a pull to refresh. */
    private class Retried(val rebuild: CompletableDeferred<Boolean>?)

    /**
     * After a failed start, the scan again on each return to the foreground — or at once
     * for a pull to refresh — until one succeeds.
     *
     * @return once the wallet counts as scanned; null, ending the runner, when there is no
     *   foreground signal to wait for.
     */
    private suspend fun retryUntilScanned(ticks: Job): Retried? {
        val returns = foregroundReturns ?: return null
        while (true) {
            val rebuild = nextReturnOrRebuild(returns)
            val scanned = if (rebuild != null) {
                // A requested rebuild runs inside the full scan.
                sync.fullScan().also { scanned ->
                    report(if (scanned) OnchainLoopEvent.FullScanApplied else OnchainLoopEvent.FullScanFailed)
                }
            } else {
                // As iOS's `startBDK()` on each return: a stored scan is light synced again first.
                bringUpToDate(ticks)
            }
            lightSyncsPaused = false
            if (scanned) return Retried(rebuild)
            rebuild?.complete(false)
        }
    }

    /** Suspends until the app next returns to the foreground (null) or a rebuild is asked for. */
    private suspend fun nextReturnOrRebuild(returns: Flow<Unit>): CompletableDeferred<Boolean>? = coroutineScope {
        val returned = async { returns.first() }
        try {
            select {
                rebuildRequests.onReceive { it }
                returned.onAwait { null }
            }
        } finally {
            returned.cancel()
        }
    }

    /**
     * One timer tick, launched beside the loop: a sync, then the balance read.
     *
     * The sync is a light sync while the wallet counts as scanned. After a refresh whose
     * rebuild or scan failed it does not, and the tick tries the full scan again — what
     * iOS's Send and Swap screens do when they find the wallet unscanned. That attaches to
     * a scan still running rather than starting a second one, and runs a rebuild still
     * requested.
     *
     * The read is after the sync, and after the closure scan inside it — see the class
     * comment. Unconditional on whether the sync applied, because this reads the *node*
     * and the node's channels can move without BDK seeing anything: a light sync skipped
     * for want of an Electrum server is not a reason to stop watching a channel.
     */
    private fun launchTick(ticks: Job) {
        if (lightSyncsPaused) return
        lightSyncScope.launch(ticks) {
            val event = try {
                if (scans.hasBeenScanned) {
                    if (sync.lightSync() == LightSyncOutcome.Synced) {
                        OnchainLoopEvent.LightSyncApplied
                    } else {
                        OnchainLoopEvent.LightSyncSkipped
                    }
                } else if (sync.fullScan()) {
                    OnchainLoopEvent.FullScanApplied
                } else {
                    OnchainLoopEvent.FullScanFailed
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (failure: Exception) {
                // Nothing here is meant to throw. If it does, it is one skipped tick, not
                // an uncaught exception in the process scope.
                OnchainLoopEvent.LightSyncSkipped
            }
            // A run that ended while this synced has let the wallet go.
            ensureActive()
            report(event)
            readBalances()
        }
    }

    private fun answerPendingRebuilds(read: Boolean) {
        while (true) {
            val pending = rebuildRequests.tryReceive().getOrNull() ?: return
            pending.complete(read)
        }
    }

    /**
     * One reading, reported.
     *
     * Silent when there is no [balances] — a loop wired without one has nothing
     * to say about a read it does not make, and an event claiming otherwise would
     * be the kind of log line that makes BIT-144 hard to find again.
     *
     * @return whether a reading was taken.
     */
    private fun readBalances(): Boolean {
        val read = balances ?: return false
        val taken = read.read()
        report(if (taken) OnchainLoopEvent.BalancesRead else OnchainLoopEvent.BalancesUnavailable)
        return taken
    }

    companion object {

        /** `BackgroundSync.swift:18` — `deadline: .now() + 30, repeating: 30.0`. */
        const val LIGHT_SYNC_INTERVAL_MILLIS: Long = 30_000L

        /** `lightSyncLoadedBDKWallet`'s `asyncAfter(deadline: .now() + 2)` after a skip. */
        const val LOADED_WALLET_RETRY_MILLIS: Long = 2_000L

        /** Appears in `WalletNodeHost.onRunnerStopped` reports and nowhere a user can see. */
        const val NAME: String = "onchain-sync"
    }
}
