package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.lightningdevkit.ldknode.AsyncPaymentsRole
import org.lightningdevkit.ldknode.BuilderInterface
import org.lightningdevkit.ldknode.ElectrumSyncConfig
import org.lightningdevkit.ldknode.EsploraSyncConfig
import org.lightningdevkit.ldknode.LogLevel
import org.lightningdevkit.ldknode.LogWriter
import org.lightningdevkit.ldknode.Network
import org.lightningdevkit.ldknode.Node
import org.lightningdevkit.ldknode.VssHeaderProvider

/**
 * The ldk-node configuration this app builds, asserted against the iOS source,
 * on the JVM.
 *
 * `didStartLDK()` (`BitcoinManager.swift:119–202`) is the thing being ported and
 * it is pure field-copying — which makes it exactly the kind of code that is
 * ported wrong and looks right. A transposed sync interval, a chain source
 * pointed at the wrong network's client, a passphrase that is not empty: all
 * compile, none show up in review, and one of them silently derives a different
 * wallet.
 *
 * This test exists because that port is checkable without a device.
 * [BuilderInterface] and the records below are UniFFI-generated Kotlin — plain
 * interfaces and data classes — and nothing crosses into Rust until a real
 * `Builder` is constructed. [RecordingBuilder] is therefore a legitimate stand-in
 * for the real one *for the purpose of asking what was set*, which is the whole
 * question.
 *
 * What it does not and cannot prove is that ldk-node then honours those values.
 * That is a running node, and it belongs to BIT-123's device work.
 */
class LdkNodeConfigTest {

    private companion object {
        /**
         * Not a real node id — 66 hex characters shaped like a compressed
         * pubkey, so the plan is exercised with something the right length.
         * Test vectors are fine here; `NoEmbeddedNodeCredentialsTest` scans
         * `src/main` only, and for the reason it states: a parity test has to
         * pass something in.
         */
        val NODE_ID = "02" + "ab".repeat(32)
        const val NODE_ADDRESS = "lsp.example:9735"

        /**
         * Endpoints without a scheme, on purpose. The scheme is the app's to
         * supply through `LdkEnvironment` and writing `https://…` even in a test
         * invites the copy that lands in `src/main`.
         */
        const val CHAIN_SOURCE = "chain.example:50002"
        const val RGS = "rgs.example/snapshot"

        fun plan(
            network: WalletNetwork,
            development: Boolean = false,
            storageDir: File = File("/data/user/0/com.bittr.android/no_backup/wallet/ldk_state"),
        ) = NodeConfigPlan.forEnvironment(
            storageDir = storageDir,
            environment = LdkEnvironment(
                network = network,
                chainSourceUrl = CHAIN_SOURCE,
                rapidGossipSyncUrl = RGS,
                lightningNodeId = NODE_ID,
                lightningNodeAddress = NODE_ADDRESS,
                lsps2Token = "",
            ),
            development = development,
        )
    }

    @Test
    fun `the Config record carries every value iOS passes`() {
        val plan = plan(WalletNetwork.Regtest, development = true)

        val config = LdkNodeConfig.config(plan)

        assertEquals(plan.storageDir.absolutePath, config.storageDirPath)
        assertEquals(Network.REGTEST, config.network)
        assertEquals(listOf("0.0.0.0:19735"), config.listeningAddresses)
        assertEquals(listOf(NODE_ID), config.trustedPeers0conf)
        assertEquals(3uL, config.probingLiquidityLimitMultiplier)
        assertEquals(listOf(NODE_ID), config.anchorChannelsConfig?.trustedPeersNoReserve)
        assertEquals(1_000uL, config.anchorChannelsConfig?.perChannelReserveSats)
    }

    @Test
    fun `the three values iOS leaves nil are left null`() {
        // Each of these is a behaviour change if it acquires a value, and none
        // of them would fail a build. An announcement address or an alias makes
        // a mobile node advertise itself — and its IP — in the network graph;
        // route parameters silently change pathfinding.
        val config = LdkNodeConfig.config(plan(WalletNetwork.Bitcoin))

        assertNull(config.announcementAddresses)
        assertNull(config.nodeAlias)
        assertNull(config.routeParameters)
    }

    @Test
    fun `the storage path is absolute`() {
        // A relative path would be resolved by ldk-node against the process
        // working directory, which on Android is `/`. The failure would be a
        // permission error from inside Rust on a path nothing in this codebase
        // names.
        val config = LdkNodeConfig.config(plan(WalletNetwork.Signet, storageDir = File("wallet/ldk_state")))

        assertTrue(
            "Storage path handed to ldk-node must be absolute, was ${config.storageDirPath}",
            File(config.storageDirPath).isAbsolute,
        )
    }

    @Test
    fun `each network maps to the ldk-node case of the same name`() {
        assertEquals(Network.BITCOIN, LdkNodeConfig.network(WalletNetwork.Bitcoin))
        assertEquals(Network.TESTNET, LdkNodeConfig.network(WalletNetwork.Testnet))
        assertEquals(Network.SIGNET, LdkNodeConfig.network(WalletNetwork.Signet))
        assertEquals(Network.REGTEST, LdkNodeConfig.network(WalletNetwork.Regtest))
    }

    @Test
    fun `the mnemonic is passed with an empty passphrase`() {
        // The single most expensive field on this page. A BIP-39 passphrase is
        // an input to seed derivation, so a non-empty one derives a different
        // wallet from the same twelve words: the user's funds are not lost, they
        // are at addresses the app will never look at, and a restore on iOS
        // would not find them either. iOS passes "" (BitcoinManager.swift:164).
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Testnet), "twelve words here")

        assertEquals(
            listOf<Any?>("twelve words here", ""),
            builder.calls.single { it.name == "setEntropyBip39Mnemonic" }.args,
        )
        assertEquals("", LdkNodeConfig.MNEMONIC_PASSPHRASE)
    }

    @Test
    fun `mainnet gets Electrum and an RGS gossip source`() {
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Bitcoin), "seed")

        assertEquals(listOf<Any?>(RGS), builder.argsOf("setGossipSourceRgs"))
        val electrum = builder.calls.single { it.name == "setChainSourceElectrum" }
        assertEquals(CHAIN_SOURCE, electrum.args[0])
        assertEquals(iosBackgroundSync(), (electrum.args[1] as ElectrumSyncConfig).backgroundSyncConfig)
        assertTrue(
            "Mainnet must not also install an Esplora chain source.",
            builder.calls.none { it.name == "setChainSourceEsplora" },
        )
    }

    @Test
    fun `testnet gets Esplora and an RGS gossip source`() {
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Testnet), "seed")

        assertEquals(listOf<Any?>(RGS), builder.argsOf("setGossipSourceRgs"))
        val esplora = builder.calls.single { it.name == "setChainSourceEsplora" }
        assertEquals(CHAIN_SOURCE, esplora.args[0])
        assertEquals(iosBackgroundSync(), (esplora.args[1] as EsploraSyncConfig).backgroundSyncConfig)
    }

    @Test
    fun `regtest and signet get Esplora and no gossip source at all`() {
        // iOS's switch has no RGS call on these two branches
        // (BitcoinManager.swift:180–183), so ldk-node's default — peer-to-peer
        // gossip — stands. Asserting the *absence* is the point: a
        // `setGossipSourceP2p()` added here for symmetry would be a silent
        // behaviour change if that default ever moves, and nothing on the JVM
        // could tell.
        listOf(WalletNetwork.Regtest, WalletNetwork.Signet).forEach { network ->
            val builder = RecordingBuilder()

            LdkNodeConfig.configure(builder, plan(network), "seed")

            assertTrue(
                "$network must get no RGS gossip source — it has no RGS server.",
                builder.calls.none { it.name == "setGossipSourceRgs" },
            )
            assertTrue(
                "$network must not pin the gossip source to p2p either; iOS leaves it unset.",
                builder.calls.none { it.name == "setGossipSourceP2p" },
            )
            assertEquals(CHAIN_SOURCE, builder.calls.single { it.name == "setChainSourceEsplora" }.args[0])
        }
    }

    @Test
    fun `LSPS2 is configured with the plan's node id, address and token`() {
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Testnet), "seed")

        assertEquals(listOf<Any?>(NODE_ID, NODE_ADDRESS, ""), builder.argsOf("setLiquiditySourceLsps2"))
        assertTrue(
            "LSPS1 is not configured on iOS and configuring it here would change which " +
                "liquidity protocol the app negotiates.",
            builder.calls.none { it.name == "setLiquiditySourceLsps1" },
        )
    }

    @Test
    fun `no entropy source other than the mnemonic is installed`() {
        // `setEntropySeedPath` and `setEntropySeedBytes` are the other two ways
        // ldk-node can be given a seed, and either would take precedence over
        // the user's phrase in a way that compiles. A node built from a seed
        // file is a node whose funds cannot be restored from the twelve words
        // the user wrote down.
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Bitcoin), "seed")

        assertEquals(
            listOf("setEntropyBip39Mnemonic"),
            builder.calls.map { it.name }.filter { it.startsWith("setEntropy") },
        )
    }

    @Test
    fun `the recorder is actually recording`() {
        // Four assertions above are of the form "this call was never made", and
        // all of them would pass against a builder that recorded nothing.
        val builder = RecordingBuilder()

        LdkNodeConfig.configure(builder, plan(WalletNetwork.Bitcoin), "seed")

        assertEquals(
            listOf(
                "setEntropyBip39Mnemonic",
                "setLiquiditySourceLsps2",
                "setGossipSourceRgs",
                "setChainSourceElectrum",
            ),
            builder.calls.map { it.name },
        )
    }

    private fun iosBackgroundSync() = org.lightningdevkit.ldknode.BackgroundSyncConfig(
        onchainWalletSyncIntervalSecs = 30uL,
        lightningWalletSyncIntervalSecs = 30uL,
        feeRateCacheUpdateIntervalSecs = 300uL,
    )

    private fun RecordingBuilder.argsOf(name: String): List<Any?> = calls.single { it.name == name }.args

    private data class Call(val name: String, val args: List<Any?>)

    /**
     * A [BuilderInterface] that writes down what it was asked to do.
     *
     * Every method is implemented, including the ones this app never calls —
     * that is what turns "we do not configure a VSS store" into something the
     * tests above can assert rather than assume. The `build*` methods return
     * `Node`, which cannot be constructed without the native library; they throw
     * instead, and nothing here calls them.
     */
    private class RecordingBuilder : BuilderInterface {

        val calls = mutableListOf<Call>()

        private fun record(name: String, vararg args: Any?) {
            calls += Call(name, args.toList())
        }

        override fun setEntropySeedPath(seedPath: String) = record("setEntropySeedPath", seedPath)

        override fun setEntropySeedBytes(seedBytes: List<UByte>) = record("setEntropySeedBytes", seedBytes)

        override fun setEntropyBip39Mnemonic(mnemonic: String, passphrase: String?) =
            record("setEntropyBip39Mnemonic", mnemonic, passphrase)

        override fun setChainSourceEsplora(serverUrl: String, config: EsploraSyncConfig?) =
            record("setChainSourceEsplora", serverUrl, config)

        override fun setChainSourceElectrum(serverUrl: String, config: ElectrumSyncConfig?) =
            record("setChainSourceElectrum", serverUrl, config)

        override fun setChainSourceBitcoindRpc(
            rpcHost: String,
            rpcPort: UShort,
            rpcUser: String,
            rpcPassword: String,
        ) = record("setChainSourceBitcoindRpc", rpcHost, rpcPort, rpcUser, rpcPassword)

        override fun setChainSourceBitcoindRest(
            rpcHost: String,
            rpcPort: UShort,
            restHost: String,
            restPort: UShort,
            rpcUser: String,
            rpcPassword: String,
        ) = record("setChainSourceBitcoindRest", rpcHost, rpcPort, restHost, restPort, rpcUser, rpcPassword)

        override fun setGossipSourceP2p() = record("setGossipSourceP2p")

        override fun setGossipSourceRgs(rgsServerUrl: String) = record("setGossipSourceRgs", rgsServerUrl)

        override fun setPathfindingScoresSource(url: String) = record("setPathfindingScoresSource", url)

        override fun setLiquiditySourceLsps1(nodeId: String, address: String, token: String?) =
            record("setLiquiditySourceLsps1", nodeId, address, token)

        override fun setLiquiditySourceLsps2(nodeId: String, address: String, token: String?) =
            record("setLiquiditySourceLsps2", nodeId, address, token)

        override fun setStorageDirPath(storageDirPath: String) = record("setStorageDirPath", storageDirPath)

        override fun setFilesystemLogger(logFilePath: String?, maxLogLevel: LogLevel?) =
            record("setFilesystemLogger", logFilePath, maxLogLevel)

        override fun setLogFacadeLogger() = record("setLogFacadeLogger")

        override fun setCustomLogger(logWriter: LogWriter) = record("setCustomLogger", logWriter)

        override fun setNetwork(network: Network) = record("setNetwork", network)

        override fun setListeningAddresses(listeningAddresses: List<String>) =
            record("setListeningAddresses", listeningAddresses)

        override fun setAnnouncementAddresses(announcementAddresses: List<String>) =
            record("setAnnouncementAddresses", announcementAddresses)

        override fun setNodeAlias(nodeAlias: String) = record("setNodeAlias", nodeAlias)

        override fun setAsyncPaymentsRole(role: AsyncPaymentsRole?) = record("setAsyncPaymentsRole", role)

        override fun build(): Node = unsupported()

        override fun buildWithFsStore(): Node = unsupported()

        override fun buildWithVssStore(
            vssUrl: String,
            storeId: String,
            lnurlAuthServerUrl: String,
            fixedHeaders: Map<String, String>,
        ): Node = unsupported()

        override fun buildWithVssStoreAndFixedHeaders(
            vssUrl: String,
            storeId: String,
            fixedHeaders: Map<String, String>,
        ): Node = unsupported()

        override fun buildWithVssStoreAndHeaderProvider(
            vssUrl: String,
            storeId: String,
            headerProvider: VssHeaderProvider,
        ): Node = unsupported()

        private fun unsupported(): Nothing = throw UnsupportedOperationException(
            "Building a Node needs the native library. This fake exists to record " +
                "configuration, and LdkNodeConfig.configure never builds.",
        )
    }
}
