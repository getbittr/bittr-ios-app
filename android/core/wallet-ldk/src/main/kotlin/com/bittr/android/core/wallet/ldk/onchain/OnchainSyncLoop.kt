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

    companion object {

        /** `BackgroundSync.swift:18` — `deadline: .now() + 30, repeating: 30.0`. */
        const val LIGHT_SYNC_INTERVAL_MILLIS: Long = 30_000L

        /** Appears in `WalletNodeHost.onRunnerStopped` reports and nowhere a user can see. */
        const val NAME: String = "onchain-sync"
    }
}
