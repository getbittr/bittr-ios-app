package com.bittr.android.core.wallet.ldk.node

import java.io.File

/**
 * Every value iOS passes into `Builder`, as plain data.
 *
 * `BitcoinManager.didStartLDK()` (`BitcoinManager.swift:119–217`) builds the
 * node's configuration inline, mixing four kinds of thing: constants that are a
 * product decision (the 1000-sat anchor reserve), constants that are a
 * protocol/performance decision (the 30-second sync intervals), per-network
 * routing (Electrum on mainnet, Esplora elsewhere), and deployment endpoints.
 * A literal port would mix them the same way inside an adapter that only an
 * emulator can run — and the port-parity question ("are we passing what iOS
 * passes?") would then have no test.
 *
 * So the plan is computed here, out of ldk-node's types, and the adapter's only
 * job is to copy fields across. `NodeConfigPlanTest` asserts the values against
 * the iOS source line by line, on the JVM, with no native library in sight.
 *
 * ## No endpoint is defaulted in this file, on purpose
 *
 * This issue's notes are explicit: *never mainnet keys, never production node
 * access, never real funds; never commit node credentials.* Every URL, node id
 * and address is therefore a required input from the app's environment
 * configuration, not a constant with a "safe" default that a test run could
 * quietly reach past. `NoEmbeddedNodeCredentialsTest` keeps it that way.
 */
data class NodeConfigPlan(
    /** ldk-node's persistence directory — `WalletPaths.ldkStateDir`. */
    val storageDir: File,
    val network: WalletNetwork,
    /**
     * `["0.0.0.0:19735"]` in development, `["0.0.0.0:9735"]` otherwise
     * (`BitcoinManager.swift:128`).
     */
    val listeningAddresses: List<String>,
    /** The LSP, trusted for 0-conf channels (`BitcoinManager.swift:136`). */
    val trustedPeers0Conf: List<String>,
    /** `BitcoinManager.swift:137`. */
    val probingLiquidityLimitMultiplier: ULong,
    val anchorChannels: AnchorChannelsPlan,
    val backgroundSync: BackgroundSyncPlan,
    val chainSource: ChainSourcePlan,
    /**
     * Rapid Gossip Sync, where iOS configures one. Null on regtest and signet,
     * which have no RGS server (`BitcoinManager.swift:176–187`).
     */
    val rapidGossipSyncUrl: String?,
    /** LSPS2 liquidity source (`BitcoinManager.swift:169–173`). */
    val lsps2: Lsps2Plan,
) {

    /**
     * Anchor channels need an on-chain reserve per channel so the commitment
     * transaction can be fee-bumped. iOS exempts the LSP from the reserve and
     * keeps 1000 sats for everyone else (`BitcoinManager.swift:138–140`).
     */
    data class AnchorChannelsPlan(
        val trustedPeersNoReserve: List<String>,
        val perChannelReserveSats: ULong,
    )

    /**
     * ldk-node's own background sync intervals (`BitcoinManager.swift:152–156`).
     *
     * **These intervals are not honoured on Android the way they are on iOS,
     * and nothing in this module can make them be.** ldk-node runs them on its
     * own Rust threads. Under Doze and App Standby those threads are frozen
     * along with the rest of the process, so a 30-second interval becomes "30
     * seconds of the times the process is allowed to run". iOS has the same
     * class of restriction but reaches it far later: the app is suspended, not
     * frozen mid-doze on a schedule the OS picks.
     *
     * The consequence is a scheduling problem outside this data class — a
     * foreground service while the wallet is in use, and the app's push wake for
     * anything time-critical. What this comment is for is to stop the intervals
     * below being read as a guarantee of freshness. **K8** (`wallet-core-spec`
     * §6) is the test that measures what actually happens, and it needs a
     * device; until it has run, channel-monitor freshness after a doze is
     * unmeasured, not assured.
     */
    data class BackgroundSyncPlan(
        val onchainWalletSyncIntervalSecs: ULong,
        val lightningWalletSyncIntervalSecs: ULong,
        val feeRateCacheUpdateIntervalSecs: ULong,
    )

    /** Electrum on mainnet, Esplora on every test network — iOS's split. */
    sealed interface ChainSourcePlan {
        val url: String

        data class Electrum(override val url: String) : ChainSourcePlan
        data class Esplora(override val url: String) : ChainSourcePlan
    }

    data class Lsps2Plan(
        val nodeId: String,
        val address: String,
        /**
         * Empty on iOS (`BitcoinManager.swift:172`). Kept as a field rather than
         * hardcoded so that when the LSP starts requiring one it is an
         * environment value and not a code change.
         */
        val token: String,
    )

    companion object {

        /** `BitcoinManager.swift:152–156`. */
        val IOS_BACKGROUND_SYNC = BackgroundSyncPlan(
            onchainWalletSyncIntervalSecs = 30uL,
            lightningWalletSyncIntervalSecs = 30uL,
            feeRateCacheUpdateIntervalSecs = 300uL,
        )

        /** `BitcoinManager.swift:140`. Not `const`: Kotlin has no unsigned constants. */
        val ANCHOR_RESERVE_SATS: ULong = 1_000uL

        /** `BitcoinManager.swift:137`. */
        val PROBING_LIQUIDITY_LIMIT_MULTIPLIER: ULong = 3uL

        const val LISTENING_PORT_PRODUCTION = 9735
        const val LISTENING_PORT_DEVELOPMENT = 19735

        /**
         * Assemble the plan the way `didStartLDK()` does.
         *
         * @param development iOS's `EnvironmentConfig.isDevelopment`, which on
         *   Android is the app's build configuration and is passed in rather
         *   than read here — this module has no `BuildConfig` of its own and
         *   should not acquire one.
         */
        fun forEnvironment(
            storageDir: File,
            environment: LdkEnvironment,
            development: Boolean,
        ): NodeConfigPlan {
            val port = if (development) LISTENING_PORT_DEVELOPMENT else LISTENING_PORT_PRODUCTION
            return NodeConfigPlan(
                storageDir = storageDir,
                network = environment.network,
                listeningAddresses = listOf("0.0.0.0:$port"),
                trustedPeers0Conf = listOf(environment.lightningNodeId),
                probingLiquidityLimitMultiplier = PROBING_LIQUIDITY_LIMIT_MULTIPLIER,
                anchorChannels = AnchorChannelsPlan(
                    trustedPeersNoReserve = listOf(environment.lightningNodeId),
                    perChannelReserveSats = ANCHOR_RESERVE_SATS,
                ),
                backgroundSync = IOS_BACKGROUND_SYNC,
                chainSource = when (environment.network) {
                    // Mainnet is the only network iOS points at Electrum
                    // (BitcoinManager.swift:179); everything else is Esplora.
                    WalletNetwork.Bitcoin -> ChainSourcePlan.Electrum(environment.chainSourceUrl)
                    else -> ChainSourcePlan.Esplora(environment.chainSourceUrl)
                },
                rapidGossipSyncUrl = when (environment.network) {
                    // Regtest and signet have no RGS server on iOS, so they get
                    // no gossip source at all and learn the graph from peers.
                    WalletNetwork.Regtest, WalletNetwork.Signet -> null
                    else -> environment.rapidGossipSyncUrl
                },
                lsps2 = Lsps2Plan(
                    nodeId = environment.lightningNodeId,
                    address = environment.lightningNodeAddress,
                    token = environment.lsps2Token,
                ),
            )
        }
    }
}

/**
 * The deployment-specific half, supplied by the app.
 *
 * Mirrors the fields of `EnvironmentConfig` this module needs and no others.
 * Nothing here has a default — see [NodeConfigPlan]'s class comment.
 */
data class LdkEnvironment(
    val network: WalletNetwork,
    /** The **node's** chain source: Electrum URL on mainnet, Esplora URL otherwise. */
    val chainSourceUrl: String,
    /**
     * The **on-chain wallet's** Electrum server (`EnvironmentConfig.electrumURL`).
     *
     * A second field rather than a reuse of [chainSourceUrl], because iOS only
     * makes them the same value on mainnet (`BitcoinManager.swift:179` passes
     * `electrumURL` to `setChainSourceElectrum`). Everywhere else ldk-node gets
     * Esplora over HTTP and BDK still gets Electrum over TCP — two protocols on
     * two ports — so collapsing them would hand `ElectrumClient` an Esplora URL
     * on every development build. Nothing in [NodeConfigPlan] reads it; it is
     * here because this is the type the app fills in, and `BdkOnchainWalletHolder`
     * is the only consumer.
     */
    val electrumUrl: String,
    val rapidGossipSyncUrl: String?,
    val lightningNodeId: String,
    val lightningNodeAddress: String,
    val lsps2Token: String,
)

/**
 * ldk-node's `Network`, restated without the dependency.
 *
 * Small enough to be worth it: it keeps [NodeConfigPlan] — the thing the parity
 * test asserts about — free of a type that drags a native library behind it.
 */
enum class WalletNetwork {
    Bitcoin,
    Testnet,
    Signet,
    Regtest,
}
