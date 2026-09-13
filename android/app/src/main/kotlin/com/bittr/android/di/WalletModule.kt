package com.bittr.android.di

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.bittr.android.BuildConfig
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.keystore.KeystoreSecureStore
import com.bittr.android.core.wallet.ldk.adapter.LdkEventPumpRunner
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeFactory
import com.bittr.android.core.wallet.ldk.adapter.LdkNodeStartErrors
import com.bittr.android.core.wallet.ldk.cache.FileWalletCache
import com.bittr.android.core.wallet.ldk.host.NodeBackedWalletService
import com.bittr.android.core.wallet.ldk.host.ServiceForegroundPresence
import com.bittr.android.core.wallet.ldk.host.WalletNodeHost
import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
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
    fun provideWalletService(
        @ApplicationContext context: Context,
        store: SecureStore,
    ): WalletService {
        val seed = SeedWalletService(store)
        val environment: LdkEnvironment? = LdkEnvironmentConfig.fromBuildConfig()
        if (environment == null) {
            Log.i(
                TAG,
                "No LdkEnvironment in this build; the wallet holds a seed and no funds. " +
                    "Unset: ${LdkEnvironmentConfig.missingFields().joinToString(", ")}. " +
                    "See app/build.gradle.kts for how to supply them.",
            )
            return seed
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
                vault = SecureStoreSeedVault(store, SeedWalletService.KEY_SEED),
            ),
            classifier = LdkNodeStartErrors,
            // Monotonic and deep-sleep-inclusive. `System.currentTimeMillis` here
            // would let an NTP correction mid-start expire the retry budget; the
            // reasoning is in NodeStartRetryPolicy.
            elapsedRealtimeMillis = SystemClock::elapsedRealtime,
        )

        return NodeBackedWalletService(
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
    }
}
