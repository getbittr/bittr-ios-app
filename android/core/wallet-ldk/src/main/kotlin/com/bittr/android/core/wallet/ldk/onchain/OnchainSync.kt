package com.bittr.android.core.wallet.ldk.onchain

/**
 * What iOS hands Electrum for a full scan (`BDKManager.swift:258–263`).
 *
 * ```swift
 * update = try electrumClient.fullScan(
 *     request: syncRequest, stopGap: UInt64(25), batchSize: UInt64(25), fetchPrevTxouts: true
 * )
 * ```
 *
 * [stopGap] is the one that costs money to get wrong, and it is worth saying why
 * it is a named constant with a test rather than a literal in an adapter. It is
 * how many *unused* consecutive addresses BDK will look past before deciding the
 * wallet ends there. A user who received into address 30 while the app was
 * uninstalled, with 1–29 unused, is a user whose coins are invisible at a stop
 * gap of 25 — the wallet shows a balance of zero and the drain preview offers
 * nothing, on a wallet that has funds.
 *
 * That failure is silent in both directions, which is the argument for pinning
 * the value to iOS rather than picking one: a *smaller* gap loses coins iOS can
 * see, and a *larger* one shows coins iOS cannot, and neither shows up as an
 * error anywhere. It is 25 because iOS is 25.
 */
data class FullScanParameters(
    val stopGap: ULong,
    val batchSize: ULong,
    val fetchPrevTxouts: Boolean,
)

/**
 * What iOS hands Electrum for a light sync (`BDKManager.swift:332–336`).
 *
 * No stop gap: a light sync only revisits scripts the wallet has already
 * revealed (`startSyncWithRevealedSpks`), so there is no gap to walk. That is a
 * different type rather than a nullable field on [FullScanParameters] because a
 * nullable field is a field somebody force-unwraps in an adapter.
 */
data class LightSyncParameters(
    val batchSize: ULong,
    val fetchPrevTxouts: Boolean,
)

/**
 * Where a sync stopped.
 *
 * iOS distinguishes these only by the `row:` it passes to `handleError`
 * (`BDKManager.swift:212`, `:236`, `:243`, `:250`) and then collapses them all
 * into `completion(false)`. Naming them is what lets [OnchainSyncTest] assert
 * that the *right* step failed, rather than that something did.
 */
enum class SyncStep {
    /** No wallet to sync. iOS's `guard let bdkWallet ... else` — a teardown, or a sync before the start finished. */
    NoWallet,

    /** A light sync was asked for while a full scan was running. `BDKManager.swift:285–288`. */
    FullScanInProgress,

    /** `startFullScan().build()` / `startSyncWithRevealedSpks().build()` threw. */
    BuildRequest,

    /** The Electrum round trip threw — the connectivity case, and the common one. */
    FetchUpdate,

    /** The wallet was replaced while the network call was in flight. See [OnchainSync]. */
    WalletReplaced,

    /** `applyUpdate` threw. BDK's `CannotConnectException`: the update does not attach to this wallet's chain. */
    ApplyUpdate,
}

/**
 * How a sync went, in more detail than the `Bool` iOS hands its callers.
 */
sealed interface SyncOutcome {

    /** Whether the wallet's view of the chain was actually updated. iOS's `Bool`. */
    val applied: Boolean

    /**
     * The update reached the wallet.
     *
     * @param persisted whether it also reached the SQLite store. **False is not a
     *   failure of this sync** — see [OnchainSync.runFullScan].
     */
    data class Applied(
        val persisted: Boolean,
        val persistFailure: Throwable? = null,
    ) : SyncOutcome {
        override val applied: Boolean get() = true
    }

    /** The sync stopped at [step]. [cause] is null for the two guard steps, which throw nothing. */
    data class NotApplied(
        val step: SyncStep,
        val cause: Throwable? = null,
    ) : SyncOutcome {
        override val applied: Boolean get() = false
    }
}

/**
 * The BDK calls a sync makes, as a seam with no BDK types in it.
 *
 * Four type parameters rather than one, because BDK's two sync paths do not
 * share a request type: `startFullScan()` yields a `FullScanRequest` and
 * `startSyncWithRevealedSpks()` a `SyncRequest`, and collapsing them behind a
 * common supertype would mean an unchecked cast in the one place a mix-up is
 * invisible — a light sync run with full-scan machinery still returns an
 * `Update`, it just returns the wrong one.
 *
 * The names match bdk-android's own, so `BdkSyncPort` is a file of one-line
 * forwards with nothing to get wrong that review cannot see.
 *
 * @param W the wallet. `org.bitcoindevkit.Wallet` in production.
 * @param F a full-scan request.
 * @param S a light-sync request.
 * @param U the update a scan produces.
 */
interface OnchainSyncPort<W : Any, F : Any, S : Any, U : Any> {

    /**
     * The wallet as of right now, or null if there is none.
     *
     * Called twice per sync, and the second call is the point — see
     * [OnchainSync.runFullScan]. Implementations must read the live field rather
     * than return a captured value, or the identity check checks nothing.
     */
    fun currentWallet(): W?

    fun startFullScan(wallet: W): F

    fun fullScan(request: F, parameters: FullScanParameters): U

    fun startSyncWithRevealedSpks(wallet: W): S

    fun sync(request: S, parameters: LightSyncParameters): U

    fun applyUpdate(wallet: W, update: U)

    /** `wallet.persist(connection)`. The connection is the port's business, not this layer's. */
    fun persist(wallet: W)
}

/**
 * The order a BDK sync happens in, and what each failure means.
 *
 * Port of `didSyncBdkWallet` and `lightSyncBdkWallet` (`BDKManager.swift:196–330`
 * and `:301–371`), minus the two things that already have homes: claiming the
 * scan and the watchdog are [ScanCoordinator]'s, and [BdkStore] owns the store's
 * lifecycle.
 *
 * ## Why the sequence is here and not in the adapter
 *
 * Every step below is a `try`/`catch` whose *catch* is a decision, and three of
 * them are decisions a careless port gets wrong in a way no review catches:
 *
 * 1. **A persist failure does not fail the sync.** iOS writes
 *    `do { let _ = try bdkWallet.persist(...) } catch { self.handleError(...) }`
 *    and then falls through to `endBdkScan(scanned: true)` and
 *    `completion(true)` — the update is already in the wallet's memory, and the
 *    user's balance is correct on screen whether or not SQLite took it. Porting
 *    that `catch` as `return false` would turn a working sync into a failed one
 *    and, through [ScanCoordinator], leave `hasBeenScanned` false — which is
 *    what four iOS call sites read to decide whether the user may open the send
 *    screen at all. The cost of the real failure is a rescan; the cost of the
 *    mistranslation is a wallet that will not let its owner spend.
 *
 *    Worth recording alongside that: on Android the persist is nearly moot
 *    anyway. [BdkStore] deletes the whole store on every start, ported from
 *    iOS, so nothing persisted here survives to be read back. It is kept
 *    because it is what iOS does and because the day that delete is
 *    reconsidered — BIT-131 is the decision, still open — the persist has to
 *    already be in the right place.
 *
 *    **Necessary, but not sufficient — do not read this as "delete the delete
 *    and persistence works".** `BdkWalletFactory.open` builds the wallet with
 *    bdk-android's *create* constructor, `Wallet(external, internal, network,
 *    connection)`, and the binding declares `CreateWithPersistException`
 *    `.DataAlreadyExists` for exactly the case of a store that already holds a
 *    changeset. Removing the wipe on its own therefore yields a wallet that
 *    opens once and throws on every start after it — and that failure is
 *    *quieter* than the one it was meant to cure, because
 *    `OnchainWalletPort.open` returns false and [OnchainSyncLoop] reports
 *    `WalletUnavailable` and returns without attempting a scan at all. Keeping
 *    the store means also routing construction through
 *    `Wallet.load(external, internal, connection)` — which takes no `Network`,
 *    so the network assertion moves out of our code and into an opaque
 *    `LoadWithPersistException.InvalidChangeSet(errorMessage: String)` — and
 *    falling back to create on `CouldNotLoad`, the empty-store case. Recorded
 *    on BIT-131.
 *
 * 2. **An `applyUpdate` failure does fail it.** BDK throws `CannotConnectException`
 *    when the update does not attach to the chain the wallet already knows. The
 *    wallet's view is then unchanged, so reporting success would report a
 *    balance from before the scan as though it were after it.
 *
 * 3. **The wallet is re-read after the network call.** iOS:
 *    `guard self.bdkWallet === bdkWallet else { ... return false }`, and it is
 *    there twice. A full scan is a round trip with a 180-second watchdog, and a
 *    teardown or a restart during it replaces the wallet object. Applying an
 *    update built against the old wallet's descriptors to the new one is the
 *    case worth refusing: `===`, on the object, not a value comparison.
 *    **On Android this is not the rare case it is on iOS** — process death and
 *    foreground-service restarts make wallet replacement routine, which is the
 *    same reason [ScanCoordinator] had to fix iOS's watchdog cross-talk.
 *
 * ## The type parameters are what make it provable
 *
 * `OnchainSyncTest` instantiates this over `String` and drives every branch on
 * the JVM with a recording fake. Nothing here names a BDK type, so
 * `WalletLayeringGuardTest` is satisfied for the same reason the rest of
 * `onchain/` satisfies it, and `BdkSyncPort` — the part that does need a device
 * — has no branches left in it to be wrong about.
 *
 * Proved by `OnchainSyncTest`.
 */
class OnchainSync<W : Any, F : Any, S : Any, U : Any>(
    private val port: OnchainSyncPort<W, F, S, U>,
    private val scans: ScanCoordinator,
    /**
     * The closure scan, run at the end of a sync that applied.
     *
     * iOS calls `storeChannelClosureTxIDIfFound()` from both paths and from
     * nowhere else (`BDKManager.swift:301`, `:369`), immediately before
     * reporting success — so the ordering is encoded here rather than left to a
     * caller.
     *
     * **Nullable but not defaulted, and the missing default is the point.** It
     * was defaulted while [ChannelClosureRecorder] had no channel list to be
     * built from, and a defaulted parameter is a wiring step that can be
     * forgotten in silence: a production `OnchainSync(port, scans)` compiles,
     * runs, syncs correctly and never records a closure, and nothing about it
     * reads as wrong. BIT-130 supplied the channel list and wired it, so every
     * construction site now has to say which it is. Null is still a legitimate
     * answer — it is what most of `OnchainSyncTest` wants — it just has to be
     * written down.
     */
    private val closures: ChannelClosureRecorder?,
) {

    /**
     * `didSyncBdkWallet`, with the claim and the watchdog delegated to
     * [ScanCoordinator].
     *
     * Returns what iOS's completion carries: whether the wallet got scanned.
     * A caller that loses the race attaches to the running scan and gets its
     * answer rather than starting a second one; a caller still waiting at 180
     * seconds is told `false` while the scan runs on. Both are
     * [ScanCoordinator]'s behaviour and its tests.
     */
    suspend fun fullScan(): Boolean = scans.fullScan { runFullScan().applied }

    /** `lightSyncBdkWallet() -> Bool`. */
    fun lightSync(): Boolean = runLightSync().applied

    /**
     * The full-scan sequence itself, with the step that stopped it.
     *
     * Public because it is the thing worth asserting: [fullScan] reduces this to
     * the one bit iOS's callers get, and a test that could only see that bit
     * could not tell a persist failure from a connectivity failure.
     */
    fun runFullScan(): SyncOutcome {
        val wallet = port.currentWallet()
            ?: return SyncOutcome.NotApplied(SyncStep.NoWallet)

        val request = try {
            port.startFullScan(wallet)
        } catch (failure: Exception) {
            return SyncOutcome.NotApplied(SyncStep.BuildRequest, failure)
        }

        val update = try {
            port.fullScan(request, FULL_SCAN)
        } catch (failure: Exception) {
            return SyncOutcome.NotApplied(SyncStep.FetchUpdate, failure)
        }

        return applyAndPersist(wallet, update)
    }

    /**
     * The light-sync sequence.
     *
     * The stand-down guard is first, exactly as iOS orders it: both paths call
     * `applyUpdate` and `persist` against the same wallet and connection, and
     * BDK's `Wallet` is not safe to update from two places at once. Asking
     * [ScanCoordinator] rather than tracking it here keeps one answer to "is a
     * scan running" in the codebase.
     */
    fun runLightSync(): SyncOutcome {
        if (!scans.mayLightSync()) {
            return SyncOutcome.NotApplied(SyncStep.FullScanInProgress)
        }

        val wallet = port.currentWallet()
            ?: return SyncOutcome.NotApplied(SyncStep.NoWallet)

        val request = try {
            port.startSyncWithRevealedSpks(wallet)
        } catch (failure: Exception) {
            return SyncOutcome.NotApplied(SyncStep.BuildRequest, failure)
        }

        val update = try {
            port.sync(request, LIGHT_SYNC)
        } catch (failure: Exception) {
            return SyncOutcome.NotApplied(SyncStep.FetchUpdate, failure)
        }

        return applyAndPersist(wallet, update)
    }

    /**
     * The tail both paths share: re-check the wallet, apply, then persist
     * without letting the persist decide the outcome.
     *
     * @param wallet the wallet the update was built for. Compared by identity
     *   against the live one — see the class comment, point 3.
     */
    private fun applyAndPersist(wallet: W, update: U): SyncOutcome {
        // iOS's `guard self.bdkWallet === bdkWallet`. Referential, deliberately:
        // two Wallet objects over the same descriptors are still two wallets
        // with two chain views, and `equals` on a UniFFI object would not tell
        // us that even if it were overridden.
        if (port.currentWallet() !== wallet) {
            return SyncOutcome.NotApplied(SyncStep.WalletReplaced)
        }

        try {
            port.applyUpdate(wallet, update)
        } catch (failure: Exception) {
            return SyncOutcome.NotApplied(SyncStep.ApplyUpdate, failure)
        }

        // Not `try`/`return false`. See the class comment, point 1 — this is the
        // single most tempting line in the file to get wrong.
        //
        // `Exception` and not `runCatching`, which would also absorb `Error`:
        // an OutOfMemoryError on the way through SQLite is not a sync that
        // succeeded without persisting, and every other catch in this file draws
        // the line in the same place.
        val persistFailure = try {
            port.persist(wallet)
            null
        } catch (failure: Exception) {
            failure
        }
        // iOS's position exactly: after the persist, before success is reported,
        // on both paths. It cannot fail the sync — see ChannelClosureRecorder.
        closures?.record()

        return SyncOutcome.Applied(
            persisted = persistFailure == null,
            persistFailure = persistFailure,
        )
    }

    companion object {

        /** `BDKManager.swift:258–263`. */
        val FULL_SCAN = FullScanParameters(
            stopGap = 25uL,
            batchSize = 25uL,
            fetchPrevTxouts = true,
        )

        /** `BDKManager.swift:332–336`. */
        val LIGHT_SYNC = LightSyncParameters(
            batchSize = 25uL,
            fetchPrevTxouts = true,
        )
    }
}
