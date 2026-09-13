package com.bittr.android.core.wallet.ldk.node

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port parity for the node's configuration, line by line against
 * `BitcoinManager.didStartLDK()`.
 *
 * This is the deliverable's "versions compatible with what iOS runs" clause
 * extended to the *settings* iOS runs, which matter as much and are easier to
 * drift: an anchor reserve that does not match means channels that cannot be
 * fee-bumped the way the product assumes, and a missing `trustedPeers0conf`
 * means the LSP's zero-conf channels are not usable on the network the user
 * just onboarded onto.
 *
 * The endpoints are test values. None of them appear in production code — see
 * `NoEmbeddedNodeCredentialsTest`.
 */
class NodeConfigPlanTest {

    private val signet = LdkEnvironment(
        network = WalletNetwork.Signet,
        chainSourceUrl = "https://esplora.example.test/api",
        rapidGossipSyncUrl = "https://rgs.example.test/snapshot",
        lightningNodeId = "02".repeat(33),
        lightningNodeAddress = "203.0.113.10:39735",
        lsps2Token = "",
    )

    private fun plan(
        environment: LdkEnvironment = signet,
        development: Boolean = true,
    ) = NodeConfigPlan.forEnvironment(File("/tmp/ldk"), environment, development)

    @Test
    fun `the constants are iOS's`() {
        val plan = plan()

        assertEquals(3uL, plan.probingLiquidityLimitMultiplier)
        assertEquals(1_000uL, plan.anchorChannels.perChannelReserveSats)
        assertEquals(30uL, plan.backgroundSync.onchainWalletSyncIntervalSecs)
        assertEquals(30uL, plan.backgroundSync.lightningWalletSyncIntervalSecs)
        assertEquals(300uL, plan.backgroundSync.feeRateCacheUpdateIntervalSecs)
    }

    @Test
    fun `the LSP is trusted for zero-conf and exempt from the anchor reserve`() {
        // Two separate fields on iOS (`trustedPeers0conf` and
        // `anchorChannelsConfig.trustedPeersNoReserve`), both naming the same
        // node. Setting one and not the other is the drift this asserts against:
        // it would compile, start, and only show up as the user's first receive
        // failing to be spendable.
        val plan = plan()

        assertEquals(listOf(signet.lightningNodeId), plan.trustedPeers0Conf)
        assertEquals(listOf(signet.lightningNodeId), plan.anchorChannels.trustedPeersNoReserve)
        assertEquals(signet.lightningNodeId, plan.lsps2.nodeId)
        assertEquals(signet.lightningNodeAddress, plan.lsps2.address)
    }

    @Test
    fun `the listening port follows the build, as on iOS`() {
        assertEquals(listOf("0.0.0.0:19735"), plan(development = true).listeningAddresses)
        assertEquals(listOf("0.0.0.0:9735"), plan(development = false).listeningAddresses)
    }

    @Test
    fun `mainnet is the only network on Electrum`() {
        val mainnet = signet.copy(network = WalletNetwork.Bitcoin)
        assertTrue(
            plan(mainnet, development = false).chainSource is NodeConfigPlan.ChainSourcePlan.Electrum,
        )

        listOf(WalletNetwork.Testnet, WalletNetwork.Signet, WalletNetwork.Regtest).forEach { network ->
            assertTrue(
                "$network should use Esplora, as on iOS.",
                plan(signet.copy(network = network)).chainSource is
                    NodeConfigPlan.ChainSourcePlan.Esplora,
            )
        }
    }

    @Test
    fun `regtest and signet get no gossip source`() {
        // Not an oversight being ported: neither network has an RGS server, and
        // pointing them at the mainnet one would feed a node the wrong graph.
        assertNull(plan(signet.copy(network = WalletNetwork.Regtest)).rapidGossipSyncUrl)
        assertNull(plan(signet.copy(network = WalletNetwork.Signet)).rapidGossipSyncUrl)

        assertEquals(
            signet.rapidGossipSyncUrl,
            plan(signet.copy(network = WalletNetwork.Testnet)).rapidGossipSyncUrl,
        )
        assertEquals(
            signet.rapidGossipSyncUrl,
            plan(signet.copy(network = WalletNetwork.Bitcoin), development = false)
                .rapidGossipSyncUrl,
        )
    }
}
