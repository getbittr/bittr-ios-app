package com.bittr.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.di.LdkEnvironmentConfig
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **The precondition K7 and K8 are actually blocked on, measured on the device.**
 *
 * BIT-132. `android/docs/wallet-node-device-tests.md` closed K7 and K8 unrun and
 * named this as the thing upstream of hardware: *the `wallet-instrumented` job
 * builds a wallet with no node in it.* `LdkEnvironmentConfig.fromBuildConfig()`
 * returns null unless all six `BuildConfig` fields arrive at build time, their
 * committed defaults are the empty string, and a build with no environment
 * composes `SeedWalletService` — no `WalletNodeHost`, no `WalletForegroundService`,
 * no ldk-node.
 *
 * This class is the assertion that a given APK is on the other side of that
 * branch, and that the network it was compiled to reach is actually there. It is
 * the vacuity guard for everything BIT-132 builds on top: **K7 and K8 can fail
 * for a hundred reasons, and "there was no node and no network" must not be one
 * of the ones they report as a fund-safety result.**
 *
 * ## Why it is in its own source set
 *
 * `src/androidTestRegtest/`, added to `:app`'s `androidTest` source set by
 * `app/build.gradle.kts` **only when at least one `BITTR_LDK_*` value was
 * supplied**. So this class is in the test APK the nightly regtest job builds and
 * is not in the one `wallet-instrumented` builds.
 *
 * That is a build-time switch rather than a JUnit `@Assume`, and the reason is
 * `check-wallet-instrumented-results.py`: it treats **any** `<skipped/>` in the
 * results as a failed run, on the argument that a skipped test does not fail a
 * build and so is the quietest way for a suite to stop measuring anything. An
 * assumption here would have made BIT-132's first commit turn a green job red.
 *
 * The cost of a source set nothing normally compiles is that it can rot
 * unnoticed, so the `build` job compiles it with throwaway values — see the
 * "Compile the regtest instrumented sources" step in `android-maestro.yml`. A
 * suite that only compiles at night is a suite that breaks at night.
 *
 * ## Why this is not `LdkEnvironmentConfigTest`
 *
 * That test runs on the JVM and asserts the *opposite* case: with nothing
 * supplied, the compiled constants carry no node credentials. It is the guard
 * that keeps a clone and every other CI job unconfigured, and it is right.
 *
 * Nothing on the JVM can assert the case here, for two reasons. The values only
 * exist in a build somebody supplied them to — Gradle properties or the
 * environment, never the repository — so there is no configured APK to read
 * outside the job that made one. And half of what this class checks is not a
 * property of the APK at all: it is whether the emulator can reach the host.
 *
 * ## Why the reachability checks are raw sockets
 *
 * This matters more than it looks. `http://10.0.2.2:3002` is **cleartext**, and
 * the app sets no `usesCleartextTraffic` and no network security config — so for
 * `targetSdk` 28 and above the platform's default is to refuse it. A
 * `HttpURLConnection` here would fail with a cleartext policy error on a network
 * that was working perfectly.
 *
 * ldk-node is unaffected, and that asymmetry is the whole point: its Esplora
 * client is Rust, it opens its own sockets, and Android's cleartext policy is
 * enforced in the Java networking stack rather than in the kernel. So a
 * Java-level HTTP check would measure a rule that does not apply to the code
 * under test, and would report a red for a green network.
 *
 * Raw sockets measure what ldk-node and BDK actually do: connect to a TCP port on
 * 10.0.2.2 and speak a protocol. `server.version` and `GET /blocks/tip/height`
 * are hand-written over the socket for the same reason.
 *
 * ## What it deliberately does not do
 *
 * It does not start a node, open a channel or pay anything. Those belong to
 * [K7InterruptedPaymentTest] — written, and driven by
 * `android/scripts/k7-interrupted-payment.sh` because a process death takes the
 * instrumentation with it (the lesson `BackupExclusionTest` learned from
 * `bmgr restore`) — and to [K8DozeMachineryTest] and [K8ChannelFreshnessTest],
 * which are **written and not yet run**;
 * `android/docs/wallet-node-device-tests.md` §4 says what a first run tests
 * first, and why the freshness half's claim is narrower than the spec's wording.
 *
 * Both are worth nothing until this class is green, and that ordering is
 * enforced rather than hoped for: `ci-wallet-regtest.sh` runs this suite first
 * and K7's phases after it.
 *
 * Every method here is in `check-wallet-regtest-results.py`'s `REQUIRED` set by
 * name.
 */
@RunWith(AndroidJUnit4::class)
class RegtestEnvironmentTest {

    /**
     * A guard against the one way this class can be present and meaningless.
     *
     * The source set it lives in is only added to the build when at least one
     * `BITTR_LDK_*` value was supplied — see `app/build.gradle.kts` — so on an
     * unconfigured build these classes do not exist and cannot be skipped,
     * reported or counted. That is the mechanism, and it is a build-time one
     * rather than an assumption, because `check-wallet-instrumented-results.py`
     * treats **any** `<skipped/>` as a failed run: an `@Assume` here would turn
     * the existing `wallet-instrumented` job red for doing exactly what it is
     * supposed to do.
     *
     * What the source-set rule cannot catch is a build that supplied *some* of the
     * fields. It compiles this class in, it composes `SeedWalletService` anyway,
     * and every assertion below about an endpoint would then be an assertion about
     * a URL nothing is using. `LdkEnvironmentConfig`'s "partially configured is not
     * configured" paragraph is about that state; this is where it becomes a red.
     */
    @Before
    fun thisBuildIsFullyConfiguredAndNotPartly() {
        val missing = LdkEnvironmentConfig.missingFields()
        assertEquals(
            "This APK supplied ${SUPPLIED_FIELDS.count { it.isNotBlank() }} of the six " +
                "BITTR_LDK_* fields, so the regtest test sources compiled in — and " +
                "left $missing blank, so fromBuildConfig() returns null and the app " +
                "composes SeedWalletService. Partially configured is not configured. " +
                "Use the -P arguments " +
                "`python3 android/scripts/regtest-ldk-env.py --format gradle` prints.",
            emptyList<String>(),
            missing,
        )
    }

    /**
     * The APK was compiled with all six fields, and with regtest ones.
     *
     * `missingFields()` is asserted rather than `fromBuildConfig() != null`,
     * because the two differ in exactly the case worth reading: a build with four
     * of the five supplied returns null from the second and names the gap in the
     * first. A job that spent twenty minutes booting an emulator should not
     * report "the environment was absent" when it can report which property was
     * blank.
     */
    @Test
    fun theBuildCarriesAConfiguredRegtestEnvironment() {
        val missing = LdkEnvironmentConfig.missingFields()
        assertEquals(
            "This APK was built without a complete LdkEnvironment, so it composes " +
                "SeedWalletService and has no node in it. Blank fields: $missing. " +
                "Supply them with the -P arguments " +
                "`python3 android/scripts/regtest-ldk-env.py --format gradle` prints, " +
                "after `bash android/regtest/up.sh`.",
            emptyList<String>(),
            missing,
        )

        val environment = LdkEnvironmentConfig.fromBuildConfig()
        assertNotNull(
            "missingFields() was empty and fromBuildConfig() still returned null, " +
                "which means the two disagree about what 'configured' means.",
            environment,
        )
        requireNotNull(environment)

        // The one assertion here that could stop the job spending real money.
        // BuildConfig.BITCOIN_NETWORK is what LdkEnvironmentConfig derives the
        // node's network from — deliberately, so a regtest build cannot have a
        // mainnet node — and this is where that wiring is checked against a
        // running device rather than against NodeConfigPlanTest's fixtures.
        assertEquals(
            "This APK's node network is not regtest. BIT-132: never mainnet keys, " +
                "never production node access, never real funds. Refusing to run a " +
                "payment suite against it.",
            WalletNetwork.Regtest,
            environment.network,
        )
    }

    /**
     * Every endpoint names the emulator's own host, and nothing else.
     *
     * The twin of `regtest-ldk-env.py`'s `check_emitted()`, on the other side of
     * the build. That script refuses to *emit* a value whose host is not
     * 10.0.2.2; this refuses to *run* against one. Two checks for one rule
     * because they fail at different times and catch different mistakes: the
     * script catches a bad facts file, and this catches an APK built by hand, by
     * a developer who supplied a staging URL to see what would happen.
     */
    @Test
    fun everyEndpointNamesTheEmulatorsOwnHost() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig()) {
            "No LdkEnvironment; theBuildCarriesAConfiguredRegtestEnvironment says why."
        }
        for ((name, value) in listOf(
            "chainSourceUrl" to environment.chainSourceUrl,
            "electrumUrl" to environment.electrumUrl,
            "lightningNodeAddress" to environment.lightningNodeAddress,
        )) {
            assertEquals(
                "$name is '$value', whose host is not the emulator's own. A regtest " +
                    "APK may only reach services published on the runner that booted " +
                    "it. See check_emitted() in android/scripts/regtest-ldk-env.py.",
                EMULATOR_HOST,
                hostOf(value),
            )
        }

        // Not the same endpoint. LdkEnvironment.electrumUrl's own comment is
        // about this collapse: point BDK at the Esplora URL and ElectrumClient
        // talks the wrong protocol to the right machine, which fails as an
        // on-chain balance that reads zero forever.
        assertTrue(
            "chainSourceUrl and electrumUrl are the same endpoint " +
                "('${environment.chainSourceUrl}'). On regtest they are two " +
                "protocols on two ports — Esplora over HTTP for ldk-node, Electrum " +
                "over TCP for BDK.",
            environment.chainSourceUrl != environment.electrumUrl,
        )
    }

    /**
     * Esplora answers a tip height, over HTTP, from this device.
     *
     * ldk-node's very first call on a non-mainnet network, so a failure here is
     * the difference between a node that syncs and a node that reports a zero
     * balance forever with nothing in logcat that names a port.
     *
     * The height is asserted to be **at least 101** rather than merely present.
     * `up.sh` mines to 101 because a coinbase output needs 100 confirmations
     * before it is spendable, so a chain shorter than that is a chain with no
     * usable coins on it — a network that answers every query and cannot fund a
     * channel, which is precisely the vacuous-green shape this class exists to
     * refuse.
     */
    @Test
    fun esploraAnswersASpendableTipHeight() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig())
        val port = portOf(environment.chainSourceUrl)
        val body = httpGet(port, "/blocks/tip/height")
        val height = body.trim().toIntOrNull()
        assertNotNull(
            "Esplora at ${environment.chainSourceUrl}/blocks/tip/height did not " +
                "answer a number. It said: '$body'. Is electrs still indexing? Its " +
                "compose healthcheck polls this exact path.",
            height,
        )
        assertTrue(
            "The regtest chain is at height $height, below the 101 blocks " +
                "android/regtest/up.sh mines. Coinbase outputs mature at 100 " +
                "confirmations, so nothing on this chain can fund a channel and " +
                "every payment test would fail for a reason that is not about " +
                "payments.",
            (height ?: 0) >= 101,
        )
        println("$EVIDENCE esplora=${environment.chainSourceUrl} tipHeight=$height")
    }

    /**
     * Electrum answers `server.version` over TCP, from this device.
     *
     * BDK's endpoint, and a *separate* assertion from the one above rather than a
     * second reading of the same fact. They are one `electrs` process listening
     * twice, so a run where Esplora answers and Electrum does not is a run where
     * the Electrum listener was misconfigured or the port mapping is wrong — and
     * the consequence is specific: the Lightning half works, the on-chain
     * balance is permanently zero. That is the failure
     * `LdkEnvironmentConfig.missingFields()` calls out for the Electrum URL, and
     * it deserves its own red.
     */
    @Test
    fun electrumAnswersServerVersion() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig())
        val port = portOf(environment.electrumUrl)
        val response = jsonRpcLine(
            port,
            """{"id":1,"method":"server.version","params":["bittr-k7","1.4"]}""",
        )
        assertTrue(
            "Electrum at ${environment.electrumUrl} did not answer server.version. " +
                "It said: '$response'. BDK's ElectrumClient makes this call when it " +
                "opens; without it the on-chain balance reads zero forever while the " +
                "Lightning half works.",
            response.contains("\"result\""),
        )
        println("$EVIDENCE electrum=${environment.electrumUrl} version=$response")
    }

    /**
     * The Lightning peer accepts a TCP connection from this device.
     *
     * Deliberately only a connect, and deliberately not a handshake. The BOLT 8
     * Noise handshake needs our static key, which lives in the node this suite
     * has not started yet, so trying would either duplicate ldk-node's transport
     * in a test or require the node — and the node needs this to be true first.
     *
     * A connect is enough to separate the two failures that matter: "the peer is
     * not listening / not mapped to 10.0.2.2" from "the peer is there and refused
     * us", and only the first of those could make K7 look like a fund-safety
     * finding.
     */
    @Test
    fun theLightningPeerAcceptsAConnection() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig())
        val address = environment.lightningNodeAddress
        val port = address.substringAfterLast(':').toIntOrNull()
        assertNotNull(
            "lightningNodeAddress '$address' has no port. ldk-node takes a bare " +
                "host:port with no scheme.",
            port,
        )
        Socket().use { socket ->
            socket.connect(InetSocketAddress(EMULATOR_HOST, port!!), CONNECT_TIMEOUT_MS)
            assertTrue(
                "Connected to $address and the socket is not connected, which should " +
                    "not be reachable.",
                socket.isConnected,
            )
        }
        println("$EVIDENCE lightningPeer=$address nodeId=${environment.lightningNodeId}")
    }

    /**
     * The reading, printed rather than asserted.
     *
     * Required by name for the reason `SeedReadableWhileLockedTest`'s
     * `recordTheLockStateTheseReadsHappenedIn` is: this suite's green means
     * "a configured APK reached a live regtest network", and a future reader
     * deciding whether a K7 result is trustworthy needs to know *which* network.
     * The node id in particular is per-bring-up, so it is the one value that ties
     * a K7 run to the LND instance that held its HTLC.
     *
     * `check-wallet-regtest-results.py` lifts these lines out of the JUnit XML
     * into the job log, because on this public repository an annotation is
     * readable without a token and an artefact is not.
     */
    @Test
    fun recordTheEnvironmentThisRunSaw() {
        val environment = LdkEnvironmentConfig.fromBuildConfig()
        println(
            "$EVIDENCE configured=${environment != null} " +
                "missing=${LdkEnvironmentConfig.missingFields()} " +
                "network=${environment?.network} " +
                "chainSource=${environment?.chainSourceUrl} " +
                "electrum=${environment?.electrumUrl} " +
                "peer=${environment?.lightningNodeAddress} " +
                "peerNodeId=${environment?.lightningNodeId} " +
                "rgs=${environment?.rapidGossipSyncUrl} " +
                "lsps2Token='${environment?.lsps2Token}'",
        )
    }

    // ---- Socket helpers. See the class comment on why these are not HTTP APIs. --

    private fun hostOf(value: String): String =
        value.substringAfter("://").substringBefore(':')

    private fun portOf(value: String): Int =
        requireNotNull(value.substringAfterLast(':').toIntOrNull()) {
            "'$value' has no port to connect to."
        }

    private fun httpGet(port: Int, path: String): String = Socket().use { socket ->
        socket.connect(InetSocketAddress(EMULATOR_HOST, port), CONNECT_TIMEOUT_MS)
        socket.soTimeout = READ_TIMEOUT_MS
        // HTTP/1.0 with no keep-alive, so the server closes the connection when
        // the body ends and `readText()` terminates. On 1.1 it would wait for a
        // second request until soTimeout, turning every green check into a
        // five-second pause.
        socket.getOutputStream().write(
            "GET $path HTTP/1.0\r\nHost: $EMULATOR_HOST:$port\r\n\r\n".toByteArray(),
        )
        socket.getOutputStream().flush()
        val text = socket.getInputStream().reader().readText()
        // The body is what the caller wants; the status line is what it needs on a
        // failure, so a non-200 is returned verbatim rather than reduced to "".
        if (!text.startsWith("HTTP/1.") || " 200" !in text.substringBefore("\r\n")) {
            return@use text.substringBefore("\r\n\r\n")
        }
        text.substringAfter("\r\n\r\n")
    }

    private fun jsonRpcLine(port: Int, request: String): String = Socket().use { socket ->
        socket.connect(InetSocketAddress(EMULATOR_HOST, port), CONNECT_TIMEOUT_MS)
        socket.soTimeout = READ_TIMEOUT_MS
        socket.getOutputStream().write("$request\n".toByteArray())
        socket.getOutputStream().flush()
        // One line. The Electrum protocol is newline-delimited JSON, so a full
        // read would block until the server closed — which for a subscription
        // server is never.
        BufferedReader(InputStreamReader(socket.getInputStream())).readLine().orEmpty()
    }

    private companion object {
        /**
         * The emulator's alias for the host that published the containers' ports.
         *
         * Restated here rather than read from the environment under test, on
         * purpose: the assertions above compare the APK's compiled values against
         * this, so taking it from those values would make every one of them
         * tautological.
         */
        const val EMULATOR_HOST = "10.0.2.2"

        /**
         * All six `BITTR_LDK_*` constants, as this APK was compiled with them.
         *
         * `com.bittr.android.BuildConfig` — the app's, not the test APK's. Both
         * carry the same values (AGP copies `defaultConfig`'s `buildConfigField`s
         * into the androidTest component), and the app's is the one the code
         * under test reads, so it is the one asserted about.
         *
         * All six, including the two that are legitimately blank on regtest, so
         * that "somebody configured this build" is true of a build that supplied
         * only an RGS URL. That build is misconfigured and must say so rather
         * than skip.
         */
        val SUPPLIED_FIELDS = listOf(
            BuildConfig.LDK_CHAIN_SOURCE_URL,
            BuildConfig.LDK_ELECTRUM_URL,
            BuildConfig.LDK_RAPID_GOSSIP_SYNC_URL,
            BuildConfig.LDK_LIGHTNING_NODE_ID,
            BuildConfig.LDK_LIGHTNING_NODE_ADDRESS,
            BuildConfig.LDK_LSPS2_TOKEN,
        )

        const val CONNECT_TIMEOUT_MS = 5_000
        const val READ_TIMEOUT_MS = 10_000

        /**
         * The prefix `check-wallet-regtest-results.py` greps out of `<system-out>`.
         * Same mechanism as `BACKUP_EXCLUSION` and `SEED_WHILE_LOCKED`.
         */
        const val EVIDENCE = "REGTEST_ENVIRONMENT"
    }
}
