package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import org.lightningdevkit.ldknode.AnchorChannelsConfig
import org.lightningdevkit.ldknode.BackgroundSyncConfig
import org.lightningdevkit.ldknode.BuilderInterface
import org.lightningdevkit.ldknode.Config
import org.lightningdevkit.ldknode.ElectrumSyncConfig
import org.lightningdevkit.ldknode.EsploraSyncConfig
import org.lightningdevkit.ldknode.Network

/**
 * [NodeConfigPlan] as the values ldk-node actually wants — the field-copying
 * half of `didStartLDK()` (`BitcoinManager.swift:119–202`).
 *
 * ## This adapter has tests, and the reason is a property of UniFFI
 *
 * The rest of `adapter/` exists because `bdk-android` and `ldk-node-android`
 * wrap native `.so` files, so anything expressed in their types needs an
 * emulator. That is true of *calls into Rust*. It is not true of the types
 * themselves: UniFFI generates records like [Config] and [BackgroundSyncConfig]
 * as ordinary Kotlin data classes, and object interfaces like [BuilderInterface]
 * as ordinary Kotlin interfaces. Nothing crosses the FFI boundary until a real
 * [org.lightningdevkit.ldknode.Builder] is touched.
 *
 * So this file is deliberately arranged to keep the FFI boundary one function
 * away. [config] returns a record and [configure] talks to an *interface*,
 * which means `LdkNodeConfigTest` can build the whole configuration on the JVM
 * and compare it to the iOS source field by field — the port-parity question
 * answered by a test rather than by review. `LdkNodeFactory` is the only piece
 * that needs a device, and all it does is call these two and then `build()`.
 *
 * That is the same trick `LdkNodeStartErrorsTest` already relies on for
 * `NodeException`, generalised: keep the part that is data separable from the
 * part that is a call, and the data half is provable.
 *
 * ## No endpoint, node id or network is defaulted here
 *
 * Every one of them comes out of the plan, which gets them from
 * `LdkEnvironment`, which the app supplies. `NoEmbeddedNodeCredentialsTest`
 * enforces it. See [NodeConfigPlan]'s class comment for why that is a rule and
 * not a preference.
 */
object LdkNodeConfig {

    /**
     * The passphrase iOS passes with the mnemonic (`BitcoinManager.swift:164`).
     *
     * Empty, and it must stay empty: the BIP-39 passphrase is part of the seed
     * derivation, so a non-empty one here would derive a different wallet from
     * the same twelve words and every address the user has ever been shown would
     * change. Named rather than inlined so that is a stated decision with a test
     * on it, not a literal someone reads as a placeholder.
     */
    const val MNEMONIC_PASSPHRASE = ""

    /** [WalletNetwork] restated as ldk-node's own enum. Total, so a new case fails to compile. */
    fun network(network: WalletNetwork): Network = when (network) {
        WalletNetwork.Bitcoin -> Network.BITCOIN
        WalletNetwork.Testnet -> Network.TESTNET
        WalletNetwork.Signet -> Network.SIGNET
        WalletNetwork.Regtest -> Network.REGTEST
    }

    /**
     * The `Config` record, matching `BitcoinManager.swift:130–142` value for value.
     *
     * The three nulls are iOS's three nils, and each is a decision worth being
     * able to point at:
     *
     * - `announcementAddresses` — the node is not announced. A mobile node with
     *   no stable address has nothing useful to announce, and announcing one
     *   would publish the user's IP in the network graph.
     * - `nodeAlias` — same reason; an alias is only meaningful for an announced
     *   node.
     * - `routeParameters` — ldk-node's defaults. iOS has never set these, so
     *   setting them here would be a routing change disguised as a port.
     */
    fun config(plan: NodeConfigPlan): Config = Config(
        // ldk-node takes a path string and creates it if needed. `absolutePath`
        // rather than `path`: the plan's File comes from WalletPaths and is
        // already absolute, but a relative one would be resolved by ldk-node
        // against the process working directory, which on Android is `/` and is
        // not writable. Making it absolute here means a mis-built plan fails as
        // a permission error at a path we can read in the log, rather than
        // silently persisting somewhere nobody looks.
        storageDirPath = plan.storageDir.absolutePath,
        network = network(plan.network),
        listeningAddresses = plan.listeningAddresses,
        announcementAddresses = null,
        nodeAlias = null,
        trustedPeers0conf = plan.trustedPeers0Conf,
        probingLiquidityLimitMultiplier = plan.probingLiquidityLimitMultiplier,
        anchorChannelsConfig = AnchorChannelsConfig(
            trustedPeersNoReserve = plan.anchorChannels.trustedPeersNoReserve,
            perChannelReserveSats = plan.anchorChannels.perChannelReserveSats,
        ),
        routeParameters = null,
    )

    /**
     * The builder calls iOS makes after `Builder.fromConfig`, in iOS's order
     * (`BitcoinManager.swift:163–187`).
     *
     * Takes [BuilderInterface] rather than `Builder` so the sequence can be
     * recorded and asserted on the JVM — see the class comment. Ordering is
     * preserved because these are setters on one Rust object and a later call
     * wins; a port that reorders them is a port whose behaviour differs the day
     * two of them touch the same field.
     *
     * ## The gossip source when there is no RGS server
     *
     * iOS calls `setGossipSourceRgs` on mainnet and testnet and **calls nothing
     * at all** on regtest and signet (`BitcoinManager.swift:176–187`), leaving
     * ldk-node's default, which is peer-to-peer gossip. That absence is ported
     * literally: a `setGossipSourceP2p()` added here for legibility would be a
     * behaviour change if the default is ever anything else, and this module has
     * no test that could tell — reading it takes a running node. The plan's null
     * `rapidGossipSyncUrl` is where the decision lives, and `NodeConfigPlanTest`
     * asserts which networks get one.
     */
    fun configure(builder: BuilderInterface, plan: NodeConfigPlan, mnemonic: String) {
        builder.setEntropyBip39Mnemonic(mnemonic, MNEMONIC_PASSPHRASE)

        // LSPS2, so channels are usable to full capacity rather than LDK's
        // default 10% — iOS's comment at BitcoinManager.swift:166–168.
        builder.setLiquiditySourceLsps2(plan.lsps2.nodeId, plan.lsps2.address, plan.lsps2.token)

        plan.rapidGossipSyncUrl?.let(builder::setGossipSourceRgs)

        val sync = backgroundSync(plan)
        when (val source = plan.chainSource) {
            is NodeConfigPlan.ChainSourcePlan.Electrum ->
                builder.setChainSourceElectrum(source.url, ElectrumSyncConfig(sync))

            is NodeConfigPlan.ChainSourcePlan.Esplora ->
                builder.setChainSourceEsplora(source.url, EsploraSyncConfig(sync))
        }
    }

    /**
     * `BitcoinManager.swift:152–156`.
     *
     * Note where this ends up: on the *chain source* config, not on [Config].
     * iOS builds one `BackgroundSyncConfig` and wraps it in both an
     * `EsploraSyncConfig` and an `ElectrumSyncConfig` because only one of the
     * two is ever installed. The same shape is kept here so the intervals are
     * stated once.
     *
     * [NodeConfigPlan.BackgroundSyncPlan]'s comment is the one to read before
     * treating these numbers as a freshness guarantee on Android; they are not,
     * and K8 is what would measure it.
     */
    private fun backgroundSync(plan: NodeConfigPlan) = BackgroundSyncConfig(
        onchainWalletSyncIntervalSecs = plan.backgroundSync.onchainWalletSyncIntervalSecs,
        lightningWalletSyncIntervalSecs = plan.backgroundSync.lightningWalletSyncIntervalSecs,
        feeRateCacheUpdateIntervalSecs = plan.backgroundSync.feeRateCacheUpdateIntervalSecs,
    )
}
