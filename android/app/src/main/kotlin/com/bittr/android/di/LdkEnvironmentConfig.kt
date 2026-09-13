package com.bittr.android.di

import com.bittr.android.BuildConfig
import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.core.wallet.ldk.node.WalletNetwork

/**
 * iOS's `EnvironmentConfig`, as the half `:core:wallet-ldk` needs.
 *
 * BIT-126 scope item 4. `NodeConfigPlan` defaults no endpoint, node id or
 * network — `NoEmbeddedNodeCredentialsTest` fails the build on one that appears
 * — so the values have to arrive from somewhere, and this is that somewhere.
 *
 * ## Nothing here is in the repository
 *
 * Every field comes from a `BuildConfig` constant whose **committed default is
 * the empty string**. The real values are supplied at build time from Gradle
 * properties or the environment (`app/build.gradle.kts` says how), which keeps
 * this issue's note — *never mainnet keys, never production node access, never
 * real funds* — true of a clone rather than true of a convention.
 *
 * That is also why [fromBuildConfig] returns null rather than throwing on an
 * unconfigured build. An unconfigured build is the *normal* state of this
 * repository: CI builds one, every Maestro run installs one, and a clone
 * produces one. A throw would turn "this build has no node" into "this build
 * does not start", and the branch that answer feeds — [WalletModule] composing
 * the seed-only wallet instead of the node-backed one — is the same branch the
 * app was on before BIT-126.
 *
 * ## Partially configured is not configured
 *
 * A build with a chain source and no LSP node id would start a node that can
 * sync and can never open a channel — and it would look like it worked. So the
 * check is all-or-nothing: any required field blank and the whole environment is
 * absent. [missingFields] exists so the difference between "nobody configured
 * this" and "someone configured four of the five" is visible to whoever is
 * looking at a build that will not open a channel.
 *
 * Proved by `LdkEnvironmentConfigTest`.
 */
object LdkEnvironmentConfig {

    /**
     * The environment this build was compiled with, or null if it was compiled
     * without one.
     *
     * The network is **not** a field of its own. It comes from
     * `BuildConfig.BITCOIN_NETWORK`, which is what the whole app already
     * branches on to decide whether a pasted address is acceptable. A second
     * knob for the node's network is a second thing to get out of step, and the
     * failure it produces — a regtest build whose node talks to mainnet — is one
     * of the few in this repo that spends real money.
     */
    fun fromBuildConfig(): LdkEnvironment? {
        if (missingFields().isNotEmpty()) return null
        return LdkEnvironment(
            network = walletNetwork(BitcoinNetwork.fromBuildConfig(BuildConfig.BITCOIN_NETWORK)),
            chainSourceUrl = BuildConfig.LDK_CHAIN_SOURCE_URL,
            // Optional, and genuinely so: `NodeConfigPlan.forEnvironment` drops it
            // on regtest and signet because iOS has no RGS server there, so a
            // blank one is a configuration that matches iOS rather than one that
            // is missing something. Blank becomes null; the plan decides the rest.
            rapidGossipSyncUrl = BuildConfig.LDK_RAPID_GOSSIP_SYNC_URL.ifBlank { null },
            lightningNodeId = BuildConfig.LDK_LIGHTNING_NODE_ID,
            lightningNodeAddress = BuildConfig.LDK_LIGHTNING_NODE_ADDRESS,
            // Empty on iOS (`BitcoinManager.swift:172`) and therefore not
            // required here. It is a field so that the day the LSP starts
            // requiring one it is a build input and not a code change.
            lsps2Token = BuildConfig.LDK_LSPS2_TOKEN,
        )
    }

    /**
     * Which required fields this build was compiled without.
     *
     * Empty means configured. The RGS URL and the LSPS2 token are not in the
     * list — see [fromBuildConfig] for why each is legitimately blank.
     */
    fun missingFields(): List<String> = buildList {
        if (BuildConfig.LDK_CHAIN_SOURCE_URL.isBlank()) add("LDK_CHAIN_SOURCE_URL")
        if (BuildConfig.LDK_LIGHTNING_NODE_ID.isBlank()) add("LDK_LIGHTNING_NODE_ID")
        if (BuildConfig.LDK_LIGHTNING_NODE_ADDRESS.isBlank()) add("LDK_LIGHTNING_NODE_ADDRESS")
    }

    /**
     * `:core:common`'s network as `:core:wallet-ldk`'s.
     *
     * Two enums for one concept, and they stay two on purpose: `BitcoinNetwork`
     * carries address-parsing data (bech32 HRPs, base58 version bytes) that the
     * wallet module has no business depending on, and `WalletNetwork` exists so
     * `NodeConfigPlan` — the thing the parity test asserts about — is free of a
     * type that drags a native library behind it. The mapping is total, so a new
     * chain on either side fails to compile here rather than defaulting.
     */
    fun walletNetwork(network: BitcoinNetwork): WalletNetwork = when (network) {
        BitcoinNetwork.MAINNET -> WalletNetwork.Bitcoin
        BitcoinNetwork.TESTNET -> WalletNetwork.Testnet
        BitcoinNetwork.SIGNET -> WalletNetwork.Signet
        BitcoinNetwork.REGTEST -> WalletNetwork.Regtest
    }
}
