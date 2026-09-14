package com.bittr.android.core.wallet.ldk.onchain

import com.bittr.android.core.wallet.ldk.host.NodeRunner
import kotlinx.coroutines.delay

/**
 * The BDK wallet's own lifetime, as the two calls a loop needs from it.
 *
 * Port of `didStartBDK()` and `clearBdkWalletReferences()`
 * (`BDKManager.swift:98–183`) reduced to what [OnchainSyncLoop] decides against.
 * The implementation is `BdkOnchainWalletHolder`, in `adapter/`, and it is a
 * field assignment either side of six BDK constructors.
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

    /** A scan had already succeeded for this process, so the loop went straight to the timer. */
    AlreadyScanned,

    /** A periodic light sync reached the wallet. */
    LightSyncApplied,

    /** One did not — no wallet, a full scan in the way, or the network. */
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
 * 2. **Full scan, unless one has already succeeded.** iOS's
 *    `guard !bdkWalletHasBeenScanned else { restart the timer }`
 *    (`StartLightning.swift:186`). [BdkStore] wipes the store on every start, so
 *    on a fresh process the scan is mandatory rather than an optimisation —
 *    with an empty store BDK knows no UTXOs and the wallet reads as empty. The
 *    branch still matters because [ScanCoordinator] outlives a *node* restart
 *    within one process, and a second node start should not pay for a second
 *    full scan.
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
 * ## What a failed full scan costs, and what revives it
 *
 * On iOS the user is the retry: `ReloadWallet` and the send screen both call
 * `didSyncBdkWallet` again. Android has neither screen yet, so the honest
 * statement is that **a failed full scan leaves the on-chain wallet unscanned
 * until something restarts this runner** — and the one thing that does is
 * `WalletNodeHost.start()` on an already-running node, which relaunches runners
 * that are no longer live. That is the unlock path, so in practice it is "the
 * user opens the app again". It is not a timer, and it should not become one
 * here: an automatic full-scan retry loop is 25 addresses of Electrum traffic
 * every interval on a wallet whose Electrum server is the thing that is down.
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
 * Proved by `OnchainSyncLoopTest`.
 */
class OnchainSyncLoop(
    private val wallet: OnchainWalletPort,
    /**
     * The sync sequence, over whatever the port's types are.
     *
     * Star-projected because nothing here touches them: [OnchainSync.fullScan]
     * and [OnchainSync.lightSync] both return `Boolean`. That is also what lets
     * `di/WalletModule` hold one — `:app` cannot name `org.bitcoindevkit.Wallet`,
     * because `:core:wallet-ldk` depends on bdk-android with `implementation`.
     */
    private val sync: OnchainSync<*, *, *, *>,
    /** The same instance [sync] was built with. Read for `hasBeenScanned`, cleared on the way out. */
    private val scans: ScanCoordinator,
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
    /** `BackgroundSync.swift:18`. Injected so the test needs no wall clock. */
    private val lightSyncIntervalMillis: Long = LIGHT_SYNC_INTERVAL_MILLIS,
    /** Every step, in order. A log line in production; the assertion in the test. */
    private val report: (OnchainLoopEvent) -> Unit = {},
) : NodeRunner {

    override val name: String = NAME

    override suspend fun run() {
        try {
            if (!wallet.open()) {
                report(OnchainLoopEvent.WalletUnavailable)
                return
            }

            if (scans.hasBeenScanned) {
                report(OnchainLoopEvent.AlreadyScanned)
            } else if (sync.fullScan()) {
                report(OnchainLoopEvent.FullScanApplied)
            } else {
                report(OnchainLoopEvent.FullScanFailed)
                return
            }

            // The node-start read. `AlreadyScanned` reaches it too: a second node
            // inside one process is a new node object, and the outpoint it should
            // be watching is a question about the channels *that* node reports.
            readBalances()

            while (true) {
                // Before the first sync, not after: iOS schedules the timer at
                // `.now() + 30`, and the full scan immediately above has just
                // read the chain. An immediate light sync would be a round trip
                // for an answer nothing has had time to change.
                delay(lightSyncIntervalMillis)
                report(
                    if (sync.lightSync()) {
                        OnchainLoopEvent.LightSyncApplied
                    } else {
                        OnchainLoopEvent.LightSyncSkipped
                    },
                )
                // After the sync, and after the closure scan inside it — see the
                // class comment. Unconditional on whether the sync applied,
                // because this reads the *node* and the node's channels can move
                // without BDK seeing anything: a light sync skipped for want of
                // an Electrum server is not a reason to stop watching a channel.
                readBalances()
            }
        } finally {
            // Non-suspending, both of them, which is what makes this correct on
            // the cancellation path — a `suspend` call in a `finally` after a
            // cancellation needs `NonCancellable` to run at all, and neither of
            // these does.
            scans.clear()
            wallet.close()
        }
    }

    /**
     * One reading, reported.
     *
     * Silent when there is no [balances] — a loop wired without one has nothing
     * to say about a read it does not make, and an event claiming otherwise would
     * be the kind of log line that makes BIT-144 hard to find again.
     */
    private fun readBalances() {
        val read = balances ?: return
        report(
            if (read.read()) OnchainLoopEvent.BalancesRead else OnchainLoopEvent.BalancesUnavailable,
        )
    }

    companion object {

        /** `BackgroundSync.swift:18` — `deadline: .now() + 30, repeating: 30.0`. */
        const val LIGHT_SYNC_INTERVAL_MILLIS: Long = 30_000L

        /** Appears in `WalletNodeHost.onRunnerStopped` reports and nowhere a user can see. */
        const val NAME: String = "onchain-sync"
    }
}
