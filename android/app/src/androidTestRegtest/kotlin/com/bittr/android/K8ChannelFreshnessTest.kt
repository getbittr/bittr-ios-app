package com.bittr.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.di.LdkEnvironmentConfig
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K8, the freshness half — the channel is still usable after an idle window,
 * and the node catches the chain up.**
 *
 * `wallet-core-spec` §6, carried on BIT-132, designed in
 * `android/docs/wallet-node-device-tests.md` §4. The spec's wording is:
 *
 * > Node lifecycle is correct across Doze and App Standby: soak with
 * > `adb shell dumpsys deviceidle force-idle`, assert **channel-monitor
 * > freshness** after wake.
 *
 * ## This test does not measure channel-monitor freshness, and says so
 *
 * That is the honest headline and it belongs at the top rather than in a
 * footnote. `LightningNodePort` exposes channels, peers, payments and balances.
 * [ChannelView] carries **no monitor update id**, and ldk-node 0.7.0 offers
 * none — so there is no reading of *"the monitor is current"* for any test above
 * this seam to assert. Adding one would mean a new FFI surface chosen by a test,
 * which is the shape BIT-6 says to flag rather than write.
 *
 * What is observable, and what this measures instead, is three proxies:
 *
 * 1. **The channel is still `isChannelReady` and `isUsable`** after the wake, and
 *    it is the *same* channel — matched by `userChannelId` against the reading
 *    taken before the window, not merely "some channel exists".
 * 2. **The peer is connected again.** Doze suspends the app's network; a node
 *    that comes out of it and never re-establishes is one a counterparty sees no
 *    response from, which is the force-close risk §4 names.
 * 3. **The node's view of the chain advanced past blocks mined while it was
 *    idle.** The host sends to the node's on-chain wallet and mines *during* the
 *    window; a balance that rises afterwards is ldk-node having processed a
 *    transaction confirmed in a block it could not have seen at the time.
 *
 * Each of those is a real property. **None of them is the spec's sentence.** So
 * this row lands in `wallet-node-device-tests.md` as *passing with a narrowed
 * claim*, with the narrowing in this comment, in the assertion text, and in the
 * table. The dishonest row would be the one that keeps the spec's wording over a
 * test measuring proxies.
 *
 * ## Why it is `@HostDriven`, and why it runs after K7
 *
 * It needs a funded, open channel, and on this network one exists only after
 * K7's phase 2. The alternative — a second funding and a second channel open for
 * K8's own use — costs two more mined-and-waited phases for a channel identical
 * to the one already there, on a job with a 90-minute ceiling.
 *
 * **The price of that choice, stated rather than discovered:** a red K7 phase 2
 * makes this test *unrunnable* rather than merely unreadable. The gate then
 * reports it as "did not run at all", which is the accurate verdict — and is why
 * [RegtestWallet.start] is called with `mayCreate = false` here. A fresh wallet
 * would have no channel, and the failure would read as a Doze finding when it is
 * really "the install was replaced between K7 and K8".
 *
 * ## One method, not four, and that is a platform fact rather than a preference
 *
 * K7 is four instrumented runs because it has to observe its own restart. This
 * is the opposite constraint: the node has to be **alive for the whole window**,
 * and the framework tears the instrumented process down when a method returns —
 * which is precisely the mechanism K7 uses as its kill. Split across phases,
 * there would be no node in the idle window at all and the test would measure a
 * dead process dozing.
 *
 * So the soak is inside one method, and the host's work happens *while it
 * blocks*. The hand-off is two channels, for the reason [Doze] gives:
 * device → host over logcat, host → device over a file under `/data/local/tmp`.
 *
 * This method is in `check-wallet-regtest-results.py`'s `REQUIRED` set by name,
 * per BIT-132's definition of done.
 */
@RunWith(AndroidJUnit4::class)
class K8ChannelFreshnessTest {

    /** The same vacuity guard K7 and [K8DozeMachineryTest] restate. */
    @Before
    fun thisBuildHasANodeInIt() {
        assertEquals(
            "This APK was built without a complete LdkEnvironment, so it composes " +
                "SeedWalletService and has no node and no channel. K8 is not a claim " +
                "about this build.",
            emptyList<String>(),
            LdkEnvironmentConfig.missingFields(),
        )
    }

    /** See [K8DozeMachineryTest.leaveTheDeviceAwake]. Same reason, same cost if omitted. */
    @After
    fun leaveTheDeviceAwake() {
        Doze.leaveForcedIdle()
    }

    /**
     * The soak, and the three proxies measured across it.
     *
     * The order of what follows is load-bearing:
     *
     * - **Baselines before the window.** A channel that was already unusable, or
     *   a peer already disconnected, must read as "it was like that before"
     *   rather than as "Doze did it". Every assertion after the wake has a
     *   before-reading to compare against.
     * - **The window is asserted to have been a window.** The deep-idle state is
     *   sampled throughout, not only at its ends; a device that dropped back to
     *   `ACTIVE` thirty seconds in spent most of it awake and both end-readings
     *   would still say `IDLE`.
     * - **The chain is asserted to have moved, by the device.** The host is the
     *   only thing that can mine, so the tempting shape is to take its word for
     *   the heights. That would make the whole claim host-asserted. The device
     *   reads Esplora itself, on both sides of the window, and the
     *   host's hand-off is only the *signal* that it is worth looking. Same
     *   principle K7 applied to its kill window.
     * - **Only then, the catch-up.** If the chain did not move while we were
     *   idle, there is nothing to catch up to, and a node that "caught up"
     *   to a chain that never moved is a pass that measured nothing.
     */
    @HostDriven
    @Test
    fun theChannelSurvivesAForcedIdleWindowAndTheNodeCatchesUp() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig())
        val graph = RegtestWallet.graph()
        RegtestWallet.start(graph.walletService(), mayCreate = false)
        val node = graph.lightningNode()

        // ---- Baselines, before anything is forced. -----------------------------

        val channelBefore = awaitOrNull(CHANNEL_TIMEOUT_MS, "K7's channel to be usable") {
            node.listChannels().firstOrNull { it.isChannelReady && it.isUsable }
        }
        assertNotNull(
            "No channel is ready and usable before the idle window. Channels this " +
                "node has: ${node.listChannels().map { it.summary() }}. K8's freshness " +
                "half runs over the channel K7 phase 2 opened and never closed — an " +
                "empty list here means K7 did not get that far, or the install was " +
                "replaced between the two. Either way this is not a Doze finding.",
            channelBefore,
        )
        requireNotNull(channelBefore)

        val peerConnectedBefore = awaitOrNull(PEER_TIMEOUT_MS, "the peer to connect") {
            node.listPeers().firstOrNull {
                it.nodeId == environment.lightningNodeId && it.isConnected
            }
        }
        assertNotNull(
            "The node is not connected to ${environment.lightningNodeId} before the " +
                "idle window. Peers: ${node.listPeers()}. Reconnecting after the wake " +
                "is one of the three things this test measures, and it cannot measure " +
                "a reconnection that was never a connection.",
            peerConnectedBefore,
        )

        val heightBefore = RegtestWallet.esploraTipHeight(environment.chainSourceUrl)
        assertNotNull(
            "Esplora at ${environment.chainSourceUrl} did not answer a tip height " +
                "before the window. RegtestEnvironmentTest asserts this path works; if " +
                "it is green and this is null, the network went away between the two.",
            heightBefore,
        )
        val onchainBefore = node.listBalances()?.totalOnchainBalanceSats
        assertNotNull(
            "listBalances() is null before the idle window, which is " +
                "LightningNodePort's contract for 'there is no node'.",
            onchainBefore,
        )

        // The address the host will pay into DURING the window. Revealed here
        // rather than derived on the host: ldk-node 0.7.0's derivation path is
        // not recoverable from the shipped .so, and a guessed address funds
        // something nothing is watching — K7 phase 1 pays for that finding
        // already, and NodeOnchainPort is where it is written down.
        val address = graph.nodeOnchain().newReceiveAddress().address
        assertTrue(
            "The node returned a blank on-chain address, so the host has nowhere to " +
                "send the coins whose arrival is this test's proof that the chain " +
                "advanced.",
            address.isNotBlank(),
        )

        // ---- The window. -------------------------------------------------------

        val windowMs = argumentMs(ARG_SOAK_WINDOW_MS) ?: SOAK_WINDOW_MS
        Doze.shell("rm -f $HANDOFF_PATH")
        val entered = Doze.enterForcedIdle()
        val bucket = Doze.setStandbyBucket(REQUESTED_BUCKET)

        // The line android/scripts/k8-doze-soak.sh is polling logcat for. It
        // carries the address because the host has no other way to learn it, and
        // the heights and balance so a red run's logcat says what the device
        // believed at the moment the host started mining.
        Doze.announce(
            "$MARKER_IDLE address=$address heightBefore=$heightBefore " +
                "onchainSatsBefore=$onchainBefore windowMs=$windowMs " +
                "channel=${channelBefore.userChannelId} $entered bucket=$bucket",
        )
        assertTrue(
            "The device did not reach deep idle for this window: $entered. " +
                "K8DozeMachineryTest#theDeviceCanBeForcedIntoDeepIdleAtAll says what " +
                "that means — it is a verdict about the emulator image, not about the " +
                "node — and this test refuses to report a survival it never tested.",
            entered.isDeepIdle,
        )

        val (observed, handoff) = holdWindowWatchingForTheHost(windowMs)
        Doze.leaveForcedIdle()

        assertEquals(
            "The device left deep idle during the window: $observed. The node spent " +
                "part of it awake, so a pass would overstate what was measured.",
            listOf(Doze.DEEP_IDLE),
            observed.distinct(),
        )

        // ---- Did anything happen while we were away? ---------------------------

        assertNotNull(
            "The host never wrote $HANDOFF_PATH during a ${windowMs / 1000}s window, " +
                "so it never mined while this node was idle. There is nothing for the " +
                "node to have missed and nothing for it to catch up to — a pass from " +
                "here would be a node that stayed level with a chain that never moved. " +
                "Failing instead. android/scripts/k8-doze-soak.sh writes that file " +
                "after it sends and mines; check its output for a bitcoind that would " +
                "not send to '$address'.",
            handoff,
        )
        assertTrue(
            "The hand-off says '$handoff', which does not report the host as having " +
                "mined. Only $MARKER_MINED is the state this test is about.",
            handoff!!.contains(MARKER_MINED),
        )

        val heightAfter = RegtestWallet.esploraTipHeight(environment.chainSourceUrl)
        assertNotNull(
            "Esplora did not answer a tip height after the wake, and did before it. " +
                "The network went away during the window, which makes every reading " +
                "below unattributable.",
            heightAfter,
        )
        assertTrue(
            "The chain is at height $heightAfter and was at $heightBefore before the " +
                "window. The host reported mining ('$handoff') and the chain did not " +
                "move, so the two disagree and this test has no missed blocks to " +
                "measure a catch-up against. Read as an infrastructure failure, not a " +
                "wallet one.",
            (heightAfter ?: 0) > (heightBefore ?: 0),
        )

        // ---- Proxy 3: the node caught up. --------------------------------------
        //
        // First, because it is the one with a wait in it and the other two are
        // instant reads of state that will not change while it runs.
        val caughtUp = awaitOrNull(CATCHUP_TIMEOUT_MS, "the node to see the coins mined while idle") {
            node.listBalances()?.totalOnchainBalanceSats?.takeIf { it > onchainBefore!! }
        }
        assertNotNull(
            "The node's on-chain balance is still " +
                "${node.listBalances()?.totalOnchainBalanceSats} sats, " +
                "${CATCHUP_TIMEOUT_MS / 1000}s after leaving a forced deep-idle " +
                "window, and was $onchainBefore before it. The host sent to $address " +
                "and mined it to height $heightAfter WHILE the node was idle, so this " +
                "is a node that did not resume its chain sync after the wake. That is " +
                "the K8 finding: ldk-node's 30-second sync intervals run on Rust " +
                "threads Doze freezes, and the foreground service is the whole of the " +
                "mitigation. A node that never catches up is one whose channel " +
                "monitors go stale — see wallet-node-device-tests.md §4.",
            caughtUp,
        )

        // ---- Proxies 1 and 2: the channel and the peer. ------------------------

        val channelAfter = node.listChannels().firstOrNull {
            it.userChannelId == channelBefore.userChannelId
        }
        assertNotNull(
            "The channel ${channelBefore.userChannelId} is GONE after the idle " +
                "window. Channels now: ${node.listChannels().map { it.summary() }}. A " +
                "channel that disappeared across a doze is the force-close outcome §4 " +
                "names: the counterparty saw no response and took the money on-chain, " +
                "which costs fees and liquidity.",
            channelAfter,
        )
        requireNotNull(channelAfter)
        assertTrue(
            "The channel survived the window and is not usable: " +
                "${channelAfter.summary()} (before: ${channelBefore.summary()}). " +
                "`isChannelReady` and `isUsable` are two separate flags and both are " +
                "asserted: ready-but-not-usable is the shape of a peer we cannot " +
                "reach, which is proxy 2 failing rather than proxy 1.",
            channelAfter.isChannelReady && channelAfter.isUsable,
        )

        val peerAfter = awaitOrNull(PEER_TIMEOUT_MS, "the peer to reconnect after the wake") {
            node.listPeers().firstOrNull {
                it.nodeId == environment.lightningNodeId && it.isConnected
            }
        }
        assertNotNull(
            "The node did not reconnect to ${environment.lightningNodeId} within " +
                "${PEER_TIMEOUT_MS / 1000}s of leaving the idle window, and was " +
                "connected before it. Peers: ${node.listPeers()}. PeerReconnect is the " +
                "code this exercises; a node that comes out of Doze and never " +
                "re-establishes is one a counterparty sees no response from.",
            peerAfter,
        )

        Doze.announce(
            "freshnessResult windowMs=$windowMs states=${observed.distinct()} " +
                "bucketRequested=$REQUESTED_BUCKET bucketObserved=$bucket " +
                "heightBefore=$heightBefore heightAfter=$heightAfter " +
                "onchainSatsBefore=$onchainBefore onchainSatsAfter=$caughtUp " +
                "channel=${channelAfter.summary()} peerReconnected=true " +
                "claim=narrowed-proxies-not-monitor-freshness " +
                "proxies=channel-usable,peer-reconnected,chain-advanced",
        )
    }

    // ---- The window, and the host's half of it. --------------------------------

    /**
     * Sit in the idle window for [windowMs], watching for the host's hand-off.
     *
     * Held for the whole window even once the hand-off arrives — which it will,
     * early, because the host mines as soon as it sees the logcat marker. The
     * point of the remaining time is the soak: ldk-node's sync intervals have to
     * come due and be missed several times over for "the node caught up" to mean
     * more than "the node was briefly interrupted".
     *
     * The per-tick announcement is what keeps AGP's runner hearing from a test
     * that is otherwise silent for minutes. A silent one gets reported as *"Test
     * failed to run to completion"*, which is a harness verdict that would be
     * read as a K8 failure.
     *
     * @return every deep-idle state observed, and the hand-off contents or null.
     */
    private fun holdWindowWatchingForTheHost(windowMs: Long): Pair<List<String>, String?> {
        val observed = mutableListOf(Doze.deepIdleState())
        var handoff: String? = null
        val deadline = System.currentTimeMillis() + windowMs
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(minOf(POLL_INTERVAL_MS, maxOf(0L, deadline - System.currentTimeMillis())))
            val state = Doze.deepIdleState()
            observed += state
            if (handoff == null) {
                handoff = Doze.shell("cat $HANDOFF_PATH").trim().ifBlank { null }
                if (handoff != null) Doze.announce("handoffSeen '$handoff'")
            }
            Doze.announce(
                "tick window=freshness remainingMs=" +
                    "${maxOf(0L, deadline - System.currentTimeMillis())} deepIdle=$state " +
                    "bucket=${Doze.standbyBucket()} handoff=${handoff != null}",
            )
        }
        return observed to handoff
    }

    /**
     * Poll [read] until it answers non-null or [timeoutMs] elapses.
     *
     * Null on timeout rather than a throw, so every caller says in its own words
     * what did not happen and what the last reading was. Copied from K7 for that
     * reason rather than shared: a common "timed out waiting for $what" would be
     * the same sentence for a channel that never came back and a peer that never
     * reconnected, and those are different investigations.
     */
    private fun <T : Any> awaitOrNull(timeoutMs: Long, what: String, read: () -> T?): T? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            runCatching(read).getOrNull()?.let { return it }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        Doze.announce("waitTimedOut what='$what' afterMs=$timeoutMs")
        return null
    }

    private fun argumentMs(name: String): Long? =
        InstrumentationRegistry.getArguments().getString(name)?.toLongOrNull()

    private fun ChannelView.summary() =
        "[$userChannelId ready=$isChannelReady usable=$isUsable out=${outboundCapacityMsat}msat]"

    private companion object {

        /**
         * How long the forced window is held, by default.
         *
         * Five minutes, against a 90-minute job that K7 already spends five
         * `connectedDebugAndroidTest` invocations of. It buys roughly ten of
         * ldk-node's 30-second sync intervals falling due inside the window, so
         * "the node caught up afterwards" is a claim about a node that had
         * repeatedly failed to sync rather than one that was briefly paused.
         *
         * A longer soak is one instrumentation argument away
         * (`k8SoakWindowMs`), and that is what a human dispatching
         * `wallet-regtest-nightly.yml` by hand to investigate a real Doze report
         * should reach for. No value of this constant makes the claim into
         * elapsed wall-clock: a forced window is the platform being told what to
         * believe, and K8's rows say so.
         */
        const val SOAK_WINDOW_MS = 300_000L

        /** `-Pandroid.testInstrumentationRunnerArguments.k8SoakWindowMs=…`. */
        const val ARG_SOAK_WINDOW_MS = "k8SoakWindowMs"

        /** Requested and recorded, never asserted — see [Doze.setStandbyBucket]. */
        const val REQUESTED_BUCKET = "rare"

        /**
         * Where the host says it has mined.
         *
         * Duplicated in `android/scripts/k8-doze-soak.sh` and pinned against it
         * by `android/scripts/test_k8_doze_soak.sh`. `/data/local/tmp` because
         * this direction is host → device and writing into `/data/data/` would
         * need `adb root`, which some images refuse.
         */
        const val HANDOFF_PATH = "/data/local/tmp/k8-chain-state"

        /** The logcat marker the host waits for before it mines. */
        const val MARKER_IDLE = "state=IDLE"

        /** What the host writes into the hand-off once it has sent and mined. */
        const val MARKER_MINED = "state=MINED"

        const val POLL_INTERVAL_MS = 15_000L

        /** The channel K7 left, after a cold node start and a peer re-establish. */
        const val CHANNEL_TIMEOUT_MS = 240_000L

        /** Reconnect and re-establish, on either side of the window. */
        const val PEER_TIMEOUT_MS = 180_000L

        /**
         * How long the node gets to see the blocks mined while it was idle.
         *
         * Esplora-paced rather than block-paced: ldk-node polls its chain source
         * on its own schedule and the sync it does on waking is a full one. This
         * is the timeout whose red IS the K8 finding, so it is generous —
         * a tight one would report a slow resume as a failed resume.
         */
        const val CATCHUP_TIMEOUT_MS = 300_000L
    }
}
