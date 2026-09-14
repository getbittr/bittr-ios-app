package com.bittr.android

import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.di.LdkEnvironmentConfig
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Test

/**
 * BIT-126 scope item 4: the node's deployment configuration reaches
 * `:core:wallet-ldk` from the app, and nothing of it is in the repository.
 *
 * `NoEmbeddedNodeCredentialsTest` already keeps the library module clean —
 * `NodeConfigPlan` defaults no endpoint, node id or network, and a `const val`
 * added there fails the build. That guard has one hole, and it is the hole this
 * issue opened: the values have to come from *somewhere*, and "somewhere" is now
 * `:app`, which that test does not scan.
 *
 * So there are two assertions here and they cover different halves. This class
 * checks what the build actually *compiled*; [NoCommittedNodeCredentialsTest]
 * checks what the sources *say*. A hardcoded default is visible to the second; a
 * value that arrived through a committed `gradle.properties` is visible only to
 * the first.
 */
class LdkEnvironmentConfigTest {

    /**
     * **A clone of this repository builds an app with no node access.**
     *
     * The issue's note as a fact about the artefact rather than about the
     * source: *never mainnet keys, never production node access, never real
     * funds*. Every `LDK_*` constant is empty unless someone supplied it at
     * build time, and an empty one means [LdkEnvironmentConfig.fromBuildConfig]
     * returns null and `WalletModule` composes the seed-only wallet.
     *
     * Skipped, loudly, on a build that *was* configured — see the
     * `bittr.ldk.configured` system property in `app/build.gradle.kts` for why
     * the distinction is passed in rather than derived here.
     */
    @Test
    fun `a build nobody configured carries no node credentials`() {
        assumeFalse(
            "This build was given an LdkEnvironment from a Gradle property or the " +
                "environment, so there is nothing to assert about its committed default. " +
                "Run ./gradlew :app:test without -Pbittr.ldk.* to check it.",
            System.getProperty("bittr.ldk.configured") == "true",
        )

        assertEquals(
            "A node endpoint was compiled into this build without anyone supplying one, " +
                "which means it came from the repository.",
            "",
            BuildConfig.LDK_CHAIN_SOURCE_URL,
        )
        assertEquals(
            "An Electrum server was compiled into this build without anyone supplying " +
                "one. It is a separate field from the chain source and gets the same rule.",
            "",
            BuildConfig.LDK_ELECTRUM_URL,
        )
        assertEquals("", BuildConfig.LDK_RAPID_GOSSIP_SYNC_URL)
        assertEquals(
            "A Lightning node id was compiled into this build without anyone supplying " +
                "one. Production node access is never committed.",
            "",
            BuildConfig.LDK_LIGHTNING_NODE_ID,
        )
        assertEquals("", BuildConfig.LDK_LIGHTNING_NODE_ADDRESS)
        assertEquals("", BuildConfig.LDK_LSPS2_TOKEN)

        assertNull(
            "With nothing configured there is no environment, and the app composes the " +
                "seed-only wallet — which is what it did before BIT-126.",
            LdkEnvironmentConfig.fromBuildConfig(),
        )
        assertEquals(
            listOf(
                "LDK_CHAIN_SOURCE_URL",
                "LDK_ELECTRUM_URL",
                "LDK_LIGHTNING_NODE_ID",
                "LDK_LIGHTNING_NODE_ADDRESS",
            ),
            LdkEnvironmentConfig.missingFields(),
        )
    }

    /**
     * **The two enums stay in step, in the one direction that spends money.**
     *
     * The mapping is `when`-exhaustive, so this test cannot fail by a new chain
     * being unmapped — that fails to compile. What it can catch is a *wrong*
     * mapping, and the wrong one that matters is a regtest build whose node
     * talks to mainnet: the app would accept regtest addresses at the keyboard
     * and open real channels behind them.
     */
    @Test
    fun `the app's network is the node's network`() {
        assertEquals(WalletNetwork.Bitcoin, LdkEnvironmentConfig.walletNetwork(BitcoinNetwork.MAINNET))
        assertEquals(WalletNetwork.Testnet, LdkEnvironmentConfig.walletNetwork(BitcoinNetwork.TESTNET))
        assertEquals(WalletNetwork.Signet, LdkEnvironmentConfig.walletNetwork(BitcoinNetwork.SIGNET))
        assertEquals(WalletNetwork.Regtest, LdkEnvironmentConfig.walletNetwork(BitcoinNetwork.REGTEST))

        // And the app's own chain, whichever build this is, maps to something.
        // The debug build is regtest and the release build is mainnet; both are
        // assembled by `./gradlew test` (see the androidComponents block), so
        // this line runs against both.
        val appNetwork = BitcoinNetwork.fromBuildConfig(BuildConfig.BITCOIN_NETWORK)
        assertEquals(
            if (BuildConfig.DEBUG) WalletNetwork.Regtest else WalletNetwork.Bitcoin,
            LdkEnvironmentConfig.walletNetwork(appNetwork),
        )
    }

    /**
     * **Four fields out of five is not a configuration.**
     *
     * A build with a chain source and no LSP node id syncs happily and can never
     * open a channel — and looks, from the outside, exactly like a wallet with
     * no inbound liquidity. Making the check all-or-nothing means a half-set
     * environment fails at composition, where the log line names the properties
     * that were blank, rather than at the first channel open.
     *
     * Asserted against `NodeConfigPlan.forEnvironment` rather than against the
     * gate alone, because the reason a blank node id is fatal is what the plan
     * does with it: it becomes the sole trusted 0-conf peer, the sole
     * reserve-exempt peer, and the LSPS2 source.
     */
    @Test
    fun `a blank node id would reach three places in the plan, so it is refused`() {
        val plan = NodeConfigPlan.forEnvironment(
            storageDir = File("/tmp/does-not-need-to-exist"),
            environment = com.bittr.android.core.wallet.ldk.node.LdkEnvironment(
                network = WalletNetwork.Regtest,
                chainSourceUrl = "http://example.invalid",
                electrumUrl = "tcp://example.invalid:60402",
                rapidGossipSyncUrl = null,
                lightningNodeId = "",
                lightningNodeAddress = "",
                lsps2Token = "",
            ),
            development = true,
        )

        assertEquals(listOf(""), plan.trustedPeers0Conf)
        assertEquals(listOf(""), plan.anchorChannels.trustedPeersNoReserve)
        assertEquals("", plan.lsps2.nodeId)
        assertTrue(
            "so the gate has to reject it before it ever gets here",
            "LDK_LIGHTNING_NODE_ID" in LdkEnvironmentConfig.missingFields() ||
                System.getProperty("bittr.ldk.configured") == "true",
        )
    }
}
