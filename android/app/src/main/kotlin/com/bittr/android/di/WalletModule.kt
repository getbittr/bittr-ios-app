package com.bittr.android.di

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.bittr.android.BuildConfig
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.keystore.KeystoreSecureStore
import com.bittr.android.core.wallet.ldk.adapter.BdkOnchainWalletHolder
import com.bittr.android.core.wallet.ldk.adapter.LdkEventPumpRunner
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeFactory
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeStartErrors
import com.bittr.android.core.wallet.ldk.adapter.lightningNodePort
import com.bittr.android.core.wallet.ldk.adapter.nodeOnchainPort
import com.bittr.android.core.wallet.ldk.cache.CachedChannelClosureStore
import com.bittr.android.core.wallet.ldk.cache.FileWalletCache
import com.bittr.android.core.wallet.ldk.host.NodeBackedWalletService
import com.bittr.android.core.wallet.ldk.host.ServiceForegroundPresence
import com.bittr.android.core.wallet.ldk.host.WalletNodeHost
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort
import com.bittr.android.core.wallet.ldk.lightning.WalletBalanceReader
import com.bittr.android.core.wallet.ldk.lightning.openChannelFundingTxIds
import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureRecorder
import com.bittr.android.core.wallet.ldk.onchain.OnchainSyncLoop
import com.bittr.android.core.wallet.ldk.onchain.ScanCoordinator
import com.bittr.android.core.wallet.ldk.seed.SecureStoreSeedVault
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import com.bittr.android.core.wallet.seed.SeedWalletService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The one place the app names a wallet implementation.
 *
 * Two of them, now, and which one is composed is a property of the *build*
 * rather than of the source — see [provideWalletService].
 *
 * [SeedWalletService] over a Keystore-backed [SecureStore] is the seed half in
 * both: a real BIP-39 phrase, a real PIN gate, the failed-attempt counter and
 * the wipe ordering. BIT-126 adds the node half around it, as a decorator rather
 * than as a second implementation — see [NodeBackedWalletService] for why.
 *
 * `:core:wallet-stub` is still in the build for the flows that must not touch
 * key material.
 */
@Module
@InstallIn(SingletonComponent::class)
object WalletModule {

    private const val TAG = "WalletModule"

    @Provides
    @Singleton
    fun provideSecureStore(@ApplicationContext context: Context): SecureStore =
        KeystoreSecureStore(context)

    /**
     * The wallet the app runs on.
     *
     * With no [LdkEnvironment], this is exactly what the app was before BIT-126:
     * [SeedWalletService], whose `start`/`stop` are no-ops. That is the build CI
     * assembles and Maestro installs, and it has to keep working — an
     * unconfigured clone that would not run is a repository nobody can
     * contribute to.
     *
     * With one, the same [SeedWalletService] is wrapped in
     * [NodeBackedWalletService] and `start`/`stop` reach `NodeLifecycle`. The
     * seam does not change shape: `UnlockViewModel` already calls
     * `wallet.start()` after a correct PIN, and that call is what now brings a
     * node up.
     *
     * **The branch is logged at both ends.** A build that was meant to be
     * configured and is not produces a wallet that opens, unlocks, shows a zero
     * balance and never explains itself; [LdkEnvironmentConfig.missingFields]
     * turns that into one line in logcat naming the properties that were blank.
     */
    @Provides
    @Singleton
    fun provideWalletService(composition: WalletComposition): WalletService = composition.wallet

    /**
     * The node's payment surface, bound to the wallet above.
     *
     * Split out of [provideWalletComposition] rather than built here, because
     * the two must be the *same* composition: a second `lightningNodePort` over
     * a second `NodeLifecycle` would be a port watching a node the wallet never
     * starts, which reads as "no node is running" forever and is indisting-
     * uishable from a broken network.
     *
     * **Its only caller today is [WalletGraph]**, which is where that is
     * written down. Binding it is what makes `LightningNodePort` reachable at
     * all — until now `LdkNodeSurface` had no construction site outside its own
     * test.
     */
    @Provides
    @Singleton
    fun provideLightningNodePort(composition: WalletComposition): LightningNodePort =
        composition.lightning

    /**
     * The node's on-chain receive surface — BIT-132, K7's funding phase.
     *
     * Bound out of [WalletComposition] for [provideLightningNodePort]'s reason,
     * and one of its own. An address is only useful to the wallet that can
     * spend it: this port must be over the `NodeLifecycle` [provideWalletService]
     * starts, or the host funds an address belonging to a node nothing opens a
     * channel from, and the failure arrives as an insufficient-funds error one
     * phase later.
     *
     * **`NodeOnchainPort`, not BDK.** `BdkOnchainWalletHolder` below is a second
     * on-chain wallet over the same seed, and it derives its own addresses;
     * `openChannel` cannot spend them. `NodeOnchainPort`'s comment has the full
     * argument for why those are two wallets rather than one.
     *
     * Like [provideLightningNodePort], its only caller today is [WalletGraph].
     * The receive screen that will use it does not exist on Android yet.
     */
    @Provides
    @Singleton
    fun provideNodeOnchainPort(composition: WalletComposition): NodeOnchainPort =
        composition.onchain

    @Provides
    @Singleton
    fun provideWalletComposition(
        @ApplicationContext context: Context,
        store: SecureStore,
    ): WalletComposition {
        val seed = SeedWalletService(store)
        val environment: LdkEnvironment? = LdkEnvironmentConfig.fromBuildConfig()
        if (environment == null) {
            Log.i(
                TAG,
                "No LdkEnvironment in this build; the wallet holds a seed and no funds. " +
                    "Unset: ${LdkEnvironmentConfig.missingFields().joinToString(", ")}. " +
                    "See app/build.gradle.kts for how to supply them.",
            )
            // A port over no lifecycle, which is what this build has: reads
            // answer empty, writes throw. `lightningNodePort`'s comment is the
            // argument for why that is the contract rather than a null binding.
            return WalletComposition(
                wallet = seed,
                lightning = lightningNodePort(null),
                // Same null lifecycle, same contract: this build has no node,
                // so it has no on-chain wallet to reveal an address from and
                // the port says so rather than inventing one.
                onchain = nodeOnchainPort(null),
            )
        }

        // Everything ldk-node writes goes under no_backup — BIT-8 rule 4 /
        // BIT-20 rule 5. The directories are created before a node is built
        // rather than on first write, because ldk-node creates its storage path
        // itself and a path it created is a path WalletPaths did not.
        val paths = WalletPaths.forContext(context)
        paths.createDirectories()

        /*
         * The wallet layer's durable records — iOS's `CacheManager`, which on
         * Android is a file store under `no_backup/wallet/cache` rather than
         * SharedPreferences, because SharedPreferences is inside the backup set
         * and there is no no-backup variant of it. `WalletCache` has the full
         * argument, and `WalletPaths.cacheDir` has the siting one: it is a
         * sibling of the LDK state directory and BDK's store, not a child of
         * either, because a quarantine moves the first and every start deletes
         * the second.
         *
         * One instance, because it holds the in-memory mirror of what is on
         * disk. Two would be two answers to "has this event been shown".
         */
        val cache = FileWalletCache(paths.cacheDir)

        /*
         * The wallet's scope: process-lifetime, and nothing above it.
         *
         * `NodeStartGate` and `ScanCoordinator` both say in their class comments
         * why this cannot be a `lifecycleScope` or a `viewModelScope` — a
         * rotation during a start would cancel the start and leave every caller
         * attached to it holding a cancelled `Deferred`. A `SupervisorJob` is
         * what stops one runner's failure cancelling the node start beside it.
         *
         * `Dispatchers.IO` because every leaf of the work under it is a blocking
         * FFI call into Rust — `Node.start()`, `nextEventAsync()`, BDK's full
         * scan — and none of them is a coroutine that suspends. On
         * `Dispatchers.Default` they would occupy the CPU-bound pool for the
         * length of a network round trip.
         *
         * Nothing cancels it, which is the other half of `WalletNodeHost`'s
         * "survives backgrounding, dies with the process": a stop cancels the
         * runners, explicitly, and the scope outlives them so the next start has
         * somewhere to run. It is built here rather than as its own `@Provides`
         * so there is no unqualified `CoroutineScope` in the graph for an
         * unrelated feature to inject by accident.
         */
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        /*
         * The seed, read fresh on every use rather than held.
         *
         * One instance shared by the node factory and the on-chain wallet, and
         * they must agree: BDK derives the receive addresses and ldk-node the
         * node's keys, both from these twelve words, and two readers that could
         * disagree is a wallet whose two halves belong to different seeds. See
         * `BdkWalletFactory` on the passphrase, which is the other half of the
         * same requirement.
         */
        val vault = SecureStoreSeedVault(store, SeedWalletService.KEY_SEED)

        val lifecycle = NodeLifecycle(
            scope = scope,
            factory = LdkNodeFactory(
                // Re-read per build, not captured: the plan holds the network
                // and the endpoints, and a build that ran an hour after the
                // environment changed should use the new one. Cheap — it is
                // field copying.
                plan = {
                    NodeConfigPlan.forEnvironment(
                        storageDir = paths.ldkStateDir,
                        environment = environment,
                        // iOS's `EnvironmentConfig.isDevelopment`, which on
                        // Android is the build type. Debug == regtest here, the
                        // same split iOS makes.
                        development = BuildConfig.DEBUG,
                    )
                },
                // The seed the app actually writes, not the BIT-8 blob nothing
                // writes yet. SecureStoreSeedVault's class comment is the one to
                // read before changing this line.
                vault = vault,
            ),
            classifier = LdkNodeStartErrors,
            // Monotonic and deep-sleep-inclusive. `System.currentTimeMillis` here
            // would let an NTP correction mid-start expire the retry budget; the
            // reasoning is in NodeStartRetryPolicy.
            elapsedRealtimeMillis = SystemClock::elapsedRealtime,
        )

        /*
         * The Lightning surface, built here rather than in the `return` below
         * because the on-chain sync needs it: `ChannelClosureRecorder` asks
         * `listChannels()` which funding transactions are still backing a live
         * channel. One port, over one lifecycle, read by the graph and by the
         * sync — which is `provideLightningNodePort`'s rule applied inside the
         * composition as well as outside it.
         */
        val lightning = lightningNodePort(lifecycle)

        /*
         * The on-chain half: BDK's wallet, and the loop that scans it.
         *
         * Composed here rather than lazily at a screen — which is what iOS does,
         * `didStartBDK()` being called from Send, Swap and Home as well as from
         * the start path — because Android has none of those screens yet and the
         * node start is the only trigger there is. `OnchainSyncLoop` says what
         * that costs and what revives a failed scan.
         *
         * One `ScanCoordinator` for the process, deliberately outliving any one
         * node: `hasBeenScanned` is what stops a second node start inside the
         * same process paying for a second full scan, and two coordinators would
         * be two answers to "has this wallet been scanned" — the flag four iOS
         * call sites read to decide whether the user may open the send screen.
         */
        val scans = ScanCoordinator(scope)
        val onchainWallet = BdkOnchainWalletHolder(
            // Re-read per open, never captured: the seed can be erased while the
            // app runs, and iOS's `guard let cachedMnemonic` treats that as a
            // teardown rather than as an error.
            mnemonic = vault::read,
            network = environment.network,
            databaseFile = paths.bdkDatabaseFile,
            // Not `environment.chainSourceUrl` — LdkEnvironment.electrumUrl says
            // why those are two fields.
            electrumUrl = environment.electrumUrl,
            onOpenFailure = { failure ->
                // iOS's `handleError(error:row:)`. The wallet still opens, shows
                // a zero on-chain balance and refuses to build a drain; what it
                // must not do is do that silently.
                Log.w(TAG, "BDK wallet failed to open; on-chain balance will read zero", failure)
            },
        )

        /*
         * The three `CacheManager` entries the channel closure turns on, as one
         * store with two callers.
         *
         * The balance read writes the funding outpoint and clears it; the
         * closure scan reads it and clears it; both write the closure txids.
         * One instance because it is one set of keys over the one `cache`
         * above — two would be two objects, but the bug they invite is the
         * reader ending up over a *different* `WalletCache`, which is how the
         * in-memory mirror stops being one answer to "what is on disk".
         */
        val closureCache = CachedChannelClosureStore(cache)

        /*
         * `storeChannelClosureTxIDIfFound()`, which iOS runs at the end of both
         * sync paths and nowhere else (`BDKManager.swift:301`, `:369`).
         *
         * Composed here because nowhere else can be: its three collaborators
         * come from three layers — the cache store, the BDK wallet's
         * transactions, and the node's channel list — and each of the three
         * owns one and cannot reach the other two. That is also why the
         * parameter went un-passed from BIT-124 until now, with the result that
         * a running app recorded no closures at all.
         *
         * **The channel list is a lambda, read inside the scan rather than
         * before the sync.** A full scan is a round trip with a 180-second
         * watchdog and a channel can close during one. An empty answer — what a
         * torn-down node gives, per `LightningNodePort`'s read contract — makes
         * `shouldScan` say yes about a channel that may still be open, and that
         * is the safe direction rather than a bug: the scan then looks for a
         * transaction spending the funding *outpoint*, an open channel's
         * funding output is unspent, and so it costs a walk of the transaction
         * list and records nothing. Defaulting the other way would skip the
         * real closure. `ClosureScanWiringTest` carries that case.
         *
         * ## What this still does not do, said plainly
         *
         * BIT-144 supplied the writer this paragraph used to say was missing:
         * `balances` below is `WalletBalanceReader`, it runs on the sync loop's
         * tick, and it writes `channel_funding_outpoint` through the same
         * `closureCache`. So the scan is now effective as well as reachable —
         * **on a wallet that has a channel**.
         *
         * On one that has never opened a channel there is still nothing to
         * write, because `listChannels()` is empty and
         * `WalletBalanceSnapshot.channelFundingOutpointToStore` is therefore
         * null. Android has no channel-open path yet; that is BIT-122's
         * remaining half. Until it lands, the honest statement about a fresh
         * Android wallet is that the closure scan runs, finds no outpoint to
         * watch, and records nothing — which is the correct behaviour for a
         * wallet with no channels rather than the broken wiring it used to be.
         */
        val closures = ChannelClosureRecorder(
            // The same instance the balance read writes through, not a second
            // store over the same cache. They share three keys and one of them —
            // the closure txids — has both of them as writers, which only works
            // because `storeChannelClosureTxIds` is a union; see its KDoc.
            store = closureCache,
            transactions = onchainWallet.transactions,
            openChannelFundingTxIds = { lightning.listChannels().openChannelFundingTxIds() },
            onFailure = { failure ->
                // Swallowed by the recorder by design — the cost is a missing
                // label on one row of the transaction list, and a sync failed
                // over it would leave `hasBeenScanned` false. Logged so the
                // missing label leaves a trace somewhere.
                Log.w(TAG, "Channel closure scan failed", failure)
            },
        )

        /*
         * `loadWalletData()` — the read that decides which channel is watched.
         *
         * This is BIT-144, and it is the half BIT-130 said was missing: without
         * it `channel_funding_outpoint` had no writer in `main`, so the recorder
         * above short-circuited on every sync and a running app recorded no
         * closure at all.
         *
         * Over the same `lightning` port the recorder's channel-list lambda
         * uses, which is `provideLightningNodePort`'s rule again — a second port
         * would read a node this composition never starts. It calls
         * `readWalletState()`, which is the single-handle read: three separate
         * port calls here could return two thirds of a wallet and a null, and
         * `WalletBalanceSnapshot`'s class comment says what that costs.
         *
         * Its trigger is `OnchainSyncLoop`'s tick rather than a timer of its
         * own; that decision, and the ordering of the read against the closure
         * scan, are argued in that class.
         */
        val balances = WalletBalanceReader(
            node = lightning,
            closures = closureCache,
            onFailure = { failure ->
                // Swallowed by the reader by design — an exception here would
                // end the sync runner and take the light-sync timer with it.
                // Logged so a cache entry that was not written leaves a trace.
                Log.w(TAG, "Wallet balance read failed", failure)
            },
        )

        val wallet = NodeBackedWalletService(
            seed = seed,
            host = WalletNodeHost(
                scope = scope,
                lifecycle = lifecycle,
                presence = ServiceForegroundPresence(context) { refused ->
                    // A node running without foreground protection, which is
                    // the state it was already in. Logged rather than surfaced:
                    // deciding what the user should be told about a wallet the
                    // OS will freeze is BIT-123's, and it needs K8's measurement
                    // of what freezing actually costs before there is anything
                    // true to say.
                    Log.w(TAG, "Foreground service refused; node runs unprotected", refused)
                },
                /*
                 * The event pump, which is what a `NodeRunner` was defined for:
                 * cancelled on every stop, relaunched on every start, because
                 * it is deliberately terminal on a read failure and the host is
                 * what gives it another life.
                 *
                 * Its handler is a log line and nothing else — see
                 * `LdkEventPumpRunner`, which says what that costs and what
                 * replaces it. The variant name rather than the event: a
                 * rendered `PaymentSuccessful` contains the payment preimage,
                 * and logcat is not where that belongs.
                 */
                runners = listOf(
                    LdkEventPumpRunner(
                        lifecycle = lifecycle,
                        cache = cache,
                        onEvent = { event -> Log.i(TAG, "Node event handled: $event") },
                        onLedgerFailure = { failure ->
                            // The event was shown and the ledger did not record
                            // it, so a replay will show it again. Not fatal to
                            // the pump, by design.
                            Log.w(TAG, "Event ledger write failed", failure)
                        },
                        onAcknowledgeFailure = { failure ->
                            // Routine while the node is going down; the event
                            // stays queued and is replayed. iOS's `try?`.
                            Log.d(TAG, "eventHandled() failed; event stays queued", failure)
                        },
                        onStopped = { outcome ->
                            Log.i(TAG, "Event pump stopped: ${outcome.stop}", outcome.cause)
                        },
                    ),
                    /*
                     * The on-chain scan loop — `startBDK()` plus
                     * `BackgroundSync`. Second in the list and not first, which
                     * is the order iOS starts them in: `startLightning()` and
                     * the event listener come up with the node, and `startBDK()`
                     * runs afterwards off `continueStartWallet`
                     * (`StartLightning.swift:144`). The host launches all
                     * runners concurrently, so the order is documentation rather
                     * than sequencing — but a reader comparing the two files
                     * should not have to wonder.
                     */
                    OnchainSyncLoop(
                        wallet = onchainWallet,
                        sync = onchainWallet.sync(scans = scans, closures = closures),
                        scans = scans,
                        // The tick the balance read borrows. Named rather than
                        // defaulted, because a loop wired without one is exactly
                        // the silent failure BIT-144 was about.
                        balances = { balances.read() != null },
                        report = { event -> Log.i(TAG, "On-chain sync: $event") },
                    ),
                ),
            ),
            // Deliberately left as the no-op default. Removing a wallet erases
            // the seed and nothing else, which is `WalletService.removeWallet`'s
            // stated contract; the LDK state directory is left where it is, and
            // that is the safe direction rather than an omission. A later
            // install's `SeedImportGuard` finds state whose discriminator does
            // not match the new seed and *quarantines* it — BIT-20's design —
            // instead of deleting force-close sweep material this issue has no
            // business deciding about.
        )

        return WalletComposition(
            wallet = wallet,
            // The same instance the closure scan reads through, not a second
            // port over the same lifecycle.
            lightning = lightning,
            // The same `lifecycle` the wallet and the Lightning port are over,
            // which is the whole reason this class exists — see
            // WalletModule.provideNodeOnchainPort.
            onchain = nodeOnchainPort(lifecycle),
        )
    }
}

/**
 * The two halves of one wallet, so two `@Provides` can name one composition.
 *
 * [WalletModule.provideWalletComposition] builds the node, its host, its
 * runners and its scope in a single pass — they share a `NodeLifecycle` and a
 * `CoroutineScope`, and every one of those relationships is load-bearing. This
 * class is how the result is handed out in two pieces without the pieces coming
 * from two passes.
 *
 * It exists because of Dagger rather than because of the design: a `@Provides`
 * returns one type, and the alternative — a second provider that rebuilds the
 * lifecycle to wrap it in a port — is the exact bug [WalletModule.provideLightningNodePort]
 * describes. Nothing outside this file should inject it; inject [WalletService]
 * or [LightningNodePort], which is what the graph is for.
 */
class WalletComposition(
    val wallet: WalletService,
    val lightning: LightningNodePort,
    /**
     * BIT-132 — the node's on-chain receive surface, over the same lifecycle.
     *
     * Here for the same reason [lightning] is: it must be a port over the node
     * *this* composition starts. A second one would hand out addresses from a
     * wallet the app never funds — and unlike a wrong balance, that failure is
     * a transaction that confirms.
     */
    val onchain: NodeOnchainPort,
)
