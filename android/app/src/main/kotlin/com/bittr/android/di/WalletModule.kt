package com.bittr.android.di

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.bittr.android.BuildConfig
import com.bittr.android.buy.BittrRegistrationKeys
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.keystore.KeystoreSecureStore
import com.bittr.android.core.wallet.ldk.adapter.BdkOnchainWalletHolder
import com.bittr.android.core.wallet.ldk.adapter.LdkEventPumpRunner
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeFactory
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeStartErrors
import com.bittr.android.core.wallet.ldk.adapter.lightningNodePort
import com.bittr.android.core.wallet.ldk.bip.Bip84Account
import com.bittr.android.core.wallet.ldk.bip.RegistrationSigner
import com.bittr.android.core.wallet.ldk.adapter.nodeOnchainPort
import com.bittr.android.core.wallet.ldk.cache.CachedChannelClosureStore
import com.bittr.android.core.wallet.ldk.cache.CachedOnchainAddressStore
import com.bittr.android.core.wallet.ldk.cache.FileWalletCache
import com.bittr.android.core.wallet.ldk.host.BackgroundWake
import com.bittr.android.core.wallet.ldk.host.ForegroundPresence
import com.bittr.android.core.wallet.ldk.host.NodeBackedWalletService
import com.bittr.android.core.wallet.ldk.host.NodeRunner
import com.bittr.android.core.wallet.ldk.host.ServiceForegroundPresence
import com.bittr.android.core.wallet.ldk.host.WalletNodeHost
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.NodeEvents
import com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort
import com.bittr.android.core.wallet.ldk.lightning.WalletBalanceReader
import com.bittr.android.core.wallet.ldk.lightning.WalletOverviewPublisher
import com.bittr.android.core.wallet.ldk.lightning.openChannelFundingTxIds
import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.onchain.AddressDerivation
import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureRecorder
import com.bittr.android.core.wallet.ldk.onchain.OnchainAddressPool
import com.bittr.android.core.wallet.ldk.onchain.OnchainSendSupport
import com.bittr.android.core.wallet.ldk.onchain.OnchainSyncLoop
import com.bittr.android.core.wallet.ldk.onchain.ScanCoordinator
import com.bittr.android.core.wallet.ldk.seed.SecureStoreSeedVault
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import com.bittr.android.core.wallet.seed.SeedWalletService
import com.bittr.android.receive.EsploraAddressUsage
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first

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

    /**
     * The background wake — BIT-133's client half, and the third piece of the
     * one composition.
     *
     * Bound out of [WalletComposition] for exactly the reason
     * [provideLightningNodePort] is: it must share the wallet's scope, its
     * foreground presence and its `WalletService`. A wake built over a second
     * composition would promote a *different* foreground service and start a
     * *different* wallet from the one `UnlockViewModel` starts, and both halves
     * would look like they worked.
     *
     * Reached through two `@EntryPoint`s and no `@Inject` site: `WalletWake`, which
     * FCM's one service calls, uses `WalletWakeEntryPoint`, which exposes this and nothing else, and
     * `FcmWakeTest` uses [WalletGraph]. Both of those say why there are two.
     */
    @Provides
    @Singleton
    fun provideBackgroundWake(composition: WalletComposition): BackgroundWake = composition.wake

    @Provides
    @Singleton
    fun provideWalletComposition(
        @ApplicationContext context: Context,
        store: SecureStore,
        http: HttpClient,
    ): WalletComposition {
        val seed = SeedWalletService(store)

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
         *
         * **Above the environment branch, not inside it (BIT-133).** The
         * background wake needs a scope on both sides: in an unconfigured build
         * the wake still runs, still reaches `WalletService.start()`, and still
         * finds a no-op behind it — which is what lets the wiring be proved on
         * the device CI actually installs. One scope per process either way; the
         * unconfigured build simply never launches anything in it.
         */
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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
                // `ForegroundPresence.None`, and that is the honest binding
                // rather than a degraded one: a build with no node has nothing
                // to hold the process up for. The wake still runs — it reaches
                // `SeedWalletService.start()`, which is a no-op — and that is
                // deliberate, because it is the only wake path an unconfigured
                // APK has and therefore the only one `FcmWakeTest` can measure
                // in the `wallet-instrumented` job.
                wake = BackgroundWake(
                    scope = scope,
                    presence = ForegroundPresence.None,
                    walletState = { seed.state.value },
                    start = seed::start,
                    report = { outcome -> Log.i(TAG, "Background wake (no node in this build): $outcome") },
                ),
                // No on-chain wallet, so no address pool: Receive shows "Unavailable"
                // rather than an address nothing is watching.
                addressPool = null,
                // Never publishes, so Home never reports a sync for a wallet with no
                // node — and, with `hasNode` false, shows no sync spinner either.
                overview = WalletOverviewPublisher(hasNode = false),
                // Nothing to send from.
                onchainSend = null,
                refresh = {},
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
        /*
         * Home's overview — the UI half of `loadWalletData()`. Published from every
         * reading below; the first one is `finalizeSync()`, which opens Send and
         * Receive on Home.
         */
        val overview = WalletOverviewPublisher(hasNode = true, closureTxIds = closureCache::closureTxIds)

        // What the event pump tells the UI — the channel-closed card, for now.
        val nodeEvents = NodeEvents()

        val balances = WalletBalanceReader(
            node = lightning,
            closures = closureCache,
            onFailure = { failure ->
                // Swallowed by the reader by design — an exception here would
                // end the sync runner and take the light-sync timer with it.
                // Logged so a cache entry that was not written leaves a trace.
                Log.w(TAG, "Wallet balance read failed", failure)
            },
            onReading = overview::publish,
        )

        /*
         * The on-chain receive pool — `manageOnchainAddresses()`. BDK derives and
         * reveals the addresses so light syncs watch them; ldk-node's revealed index
         * is dragged along behind so the two wallets agree on what has been handed
         * out. `OnchainAddressPool` has the argument for why Receive does not just
         * ask the node for a fresh address.
         */
        val onchainPort = nodeOnchainPort(lifecycle)
        val addressPool = OnchainAddressPool(
            store = CachedOnchainAddressStore(cache),
            derivation = object : AddressDerivation {
                override fun peek(index: Int): String? = onchainWallet.peekAddress(index)
                override fun revealTo(index: Int) = onchainWallet.revealAddressesTo(index)
            },
            node = { runCatching { onchainPort.newReceiveAddress().address }.getOrNull() },
            // Esplora is the node's chain source on every network but mainnet —
            // see EsploraAddressUsage on what that means for a mainnet build.
            usage = EsploraAddressUsage(esploraBaseUrl = environment.chainSourceUrl, http = http),
            log = { message -> Log.i(TAG, "Address pool: $message") },
        )

        /*
         * What holds the process up, as one object with two callers.
         *
         * Hoisted out of the `WalletNodeHost(...)` argument list it used to be
         * written inside (BIT-133), because the background wake promotes it too
         * — synchronously, before the node start it then launches, which is the
         * only thing that can happen inside `onMessageReceived`'s budget. Two
         * `ServiceForegroundPresence` instances would be two `stopService` calls
         * racing one service, and the demote that lands second would tear down a
         * promotion the other one still believes in.
         */
        val presence = ServiceForegroundPresence(context) { refused ->
            // A node running without foreground protection, which is the state
            // it was already in. Logged rather than surfaced: deciding what the
            // user should be told about a wallet the OS will freeze is BIT-123's,
            // and it needs K8's measurement of what freezing actually costs
            // before there is anything true to say.
            //
            // On the wake path this is the *expected* outcome for a
            // normal-priority message: only a high-priority FCM data message
            // buys the temporary exemption that lets a backgrounded app start a
            // foreground service on Android 12+.
            Log.w(TAG, "Foreground service refused; node runs unprotected", refused)
        }

        val wallet = NodeBackedWalletService(
            seed = seed,
            host = WalletNodeHost(
                scope = scope,
                lifecycle = lifecycle,
                presence = presence,
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
                        onNodeEvent = nodeEvents::emit,
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
                    /*
                     * The address pool, once BDK has opened — iOS runs
                     * `manageOnchainAddresses()` straight after `didStartBDK()`, off
                     * the main thread and beside the scan rather than after it.
                     */
                    object : NodeRunner {
                        override val name: String = "address-pool"
                        override suspend fun run() {
                            onchainWallet.opened.first { it }
                            addressPool.manage()
                        }
                    },
                ),
                // A runner that ends — returning or throwing, `Error`s included — ends
                // silently otherwise, and a scan loop that died at start looks exactly
                // like one that is still scanning.
                onRunnerStopped = { name, failure ->
                    if (failure == null) {
                        Log.i(TAG, "Runner $name finished")
                    } else {
                        Log.e(TAG, "Runner $name failed", failure)
                    }
                },
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
            onchain = onchainPort,
            /*
             * BIT-133. `wallet::start` and not `host::start` — the seam
             * `UnlockViewModel` uses, which here *is* `WalletNodeHost.start()`
             * through `NodeBackedWalletService`, so the start collapsing and the
             * runner restart come for free. `BackgroundWake`'s class comment has
             * the argument for binding to the interface rather than to the host.
             *
             * The same `presence` the host holds, promoted first and
             * synchronously: `onMessageReceived` returns long before a node
             * start finishes, and a process that has not been promoted by then
             * can be frozen with the start half-done.
             */
            wake = BackgroundWake(
                scope = scope,
                presence = presence,
                walletState = { wallet.state.value },
                start = wallet::start,
                report = { outcome -> Log.i(TAG, "Background wake: $outcome") },
            ),
            addressPool = addressPool,
            overview = overview,
            // Send's view of BDK: ready once the full scan has applied, which is iOS's
            // `bdkWalletHasBeenScanned` gate on the regular send.
            onchainSend = object : OnchainSendSupport {
                override val isReady: Boolean get() = onchainWallet.opened.value && scans.hasBeenScanned
                override fun drainPreview(address: String?, satPerVb: ULong) = onchainWallet.drainPreview(address, satPerVb)
                override fun transactionVsize(address: String, amountSats: Long, satPerVb: ULong) =
                    onchainWallet.transactionVsize(address, amountSats, satPerVb)
            },
            // A reading now, so what Send just did reaches the overview without waiting
            // for the sync loop's next tick.
            refresh = { balances.read() },
            // Buy's `POST /customer`: the first receive address, the account xpub and the
            // BIP137 signature by that address's key, all over this composition's seed and
            // BDK wallet. Debug builds are regtest, coin type 1 — iOS's isDevelopment.
            registration = object : BittrRegistrationKeys {
                private val signer = RegistrationSigner(mnemonic = vault::read, mainnet = !BuildConfig.DEBUG)

                override suspend fun bittrAddress(): String? {
                    // `while bdkWallet == nil`, four 3-second waits (Transfer2ViewController:322).
                    repeat(5) { attempt ->
                        onchainWallet.peekAddress(0)?.let { return it }
                        if (attempt < 4) kotlinx.coroutines.delay(3_000)
                    }
                    return null
                }

                override fun xpub(): String? = onchainWallet.accountXpub
                    ?: vault.read()?.let { Bip84Account.accountXpub(it, mainnet = !BuildConfig.DEBUG) }

                override fun signBitcoinMessage(message: String): String? = signer.sign(message)
            },
            nodeEvents = nodeEvents,
            channelFundingTxId = { closureCache.channelFundingOutpoint()?.txId },
        )
    }

    // What Home reads — `WalletOverviewSource` — is bound in `history/HistoryModule`, which applies
    // descriptions and swap matching to `WalletComposition.overview`.
}

/**
 * The three parts of one wallet, so three `@Provides` can name one composition.
 *
 * [WalletModule.provideWalletComposition] builds the node, its host, its
 * runners and its scope in a single pass — they share a `NodeLifecycle`, a
 * `CoroutineScope` and a `ForegroundPresence`, and every one of those
 * relationships is load-bearing. This class is how the result is handed out in
 * pieces without the pieces coming from separate passes.
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
    /** BIT-133 — what an FCM data message is handed. Present in every build. */
    val wake: BackgroundWake,
    /** The on-chain receive pool. Null in a build with no node. */
    val addressPool: OnchainAddressPool?,
    /** Home's balance, history and sync state. */
    val overview: WalletOverviewSource,
    /** Send's drain and size previews over the BDK wallet. Null in a build with no node. */
    val onchainSend: OnchainSendSupport?,
    /** Take a wallet reading now and publish it to [overview]. */
    val refresh: () -> Unit,
    /** What bittr registration signs with. Null in a build with no node. */
    val registration: BittrRegistrationKeys? = null,
    /** Node events the UI reacts to. Never emits in a build with no node. */
    val nodeEvents: NodeEvents = NodeEvents(),
    /** `CacheManager.getTxoID()` — the active channel's funding transaction id, once one is cached. */
    val channelFundingTxId: () -> String? = { null },
)
