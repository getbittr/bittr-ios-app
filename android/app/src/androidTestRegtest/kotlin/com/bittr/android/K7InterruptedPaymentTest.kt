package com.bittr.android

import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.PaymentStatusView
import com.bittr.android.core.wallet.ldk.lightning.PaymentView
import com.bittr.android.di.LdkEnvironmentConfig
import com.bittr.android.di.WalletGraph
import dagger.hilt.android.EntryPointAccessors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlinx.coroutines.runBlocking

/**
 * **K7 — an interrupted payment resolves to exactly one terminal outcome.**
 *
 * `wallet-core-spec` §6, carried on BIT-132 and written up in
 * `android/docs/wallet-node-device-tests.md` §3. The claim:
 *
 * > Killing the process mid-`bolt11Payment().send` leaves no double-spend and no
 * > lost claim: on restart, LDK's payment state resolves to exactly **one**
 * > terminal outcome.
 *
 * This is the largest single fund-safety risk BIT-6's notes name — *"no path
 * where a user can lose funds"* — and until this class ran, nothing covered it.
 * `WalletNodeHostTest` proves our own ordering rules on the JVM against a fake
 * node, which is a claim about our code and not about LDK's durability across a
 * `SIGKILL`. `FsyncDurabilityTest` proves `LdkStateStore` reaches the disk. What
 * neither can reach is the state where an HTLC is on the wire, our record of it
 * may or may not be durable, and the process dies.
 *
 * ## Four phases, because the test cannot observe its own restart
 *
 * Each method below is one `connectedDebugAndroidTest` invocation filtered to
 * that method, driven by `android/scripts/k7-interrupted-payment.sh` against one
 * emulator boot. Between them the host funds the wallet, mines, holds an HTLC and
 * kills the process. The methods are `@HostDriven` so the undirected suite in
 * `ci-wallet-regtest.sh` never runs them — see that annotation for why an
 * ordering mistake here would be worse than a failure.
 *
 * 1. [phase1RevealTheAddressTheHostMustFund] — start the node, reveal the
 *    on-chain address. The host sends to it and mines.
 * 2. [phase2OpenAChannelToTheRegtestPeer] — wait for the coins, open the channel
 *    to LND. The host mines it to ready.
 * 3. [phase3PayTheHoldInvoiceAndLeaveItInFlight] — pay an invoice whose preimage
 *    the counterparty is withholding, and hold the process open until the host
 *    confirms the HTLC is *accepted and stuck* at LND.
 * 4. [phase4TheInterruptedPaymentResolvedToExactlyOneOutcome] — after the kill
 *    and after the host settled the invoice, restart and assert the payment
 *    resolves once and stays resolved.
 *
 * Wallet state survives between phases: it lives under `no_backup`, and neither
 * `am instrument` nor the `adb install -r` AGP performs clears app data. The
 * phases run with `leaveApksInstalledAfterRun=true` so AGP does not uninstall it
 * out from under phase 4 — the same precaution, for the same reason, that
 * `ci-wallet-instrumented.sh` takes for the device-transfer backup.
 *
 * ## Where the kill window comes from, and why there is no seam in the send path
 *
 * `wallet-node-device-tests.md` §3 asked for a *deterministic interception
 * point* and rejected the obvious one. A latch inside `LdkNodeSurface.sendBolt11`
 * is a branch in the fund-handling path that exists only to be taken: it either
 * ships in the release APK — a way to wedge a real payment — or it does not, in
 * which case the thing under test is not the thing that ships. It would also
 * prove less, because a seam can only pause where *we* are, before the FFI call
 * or after it returns, never inside `ChannelManager::send_payment`.
 *
 * The interception point is in the **counterparty**. LND's `addholdinvoice`
 * withholds the preimage, so the HTLC arrives, is accepted, and stays accepted
 * until the host settles or cancels it. The window is as wide as the test wants,
 * it is observable from the host (`lncli lookupinvoice` reports
 * `state: ACCEPTED` exactly while the HTLC is in flight), and reaching it needs
 * no test-only code anywhere near the money. That is why the network in
 * `android/regtest/` runs LND: `invoicesrpc` is compiled into every released
 * LND, where Core Lightning and Eclair both need a plugin.
 *
 * ## What kills the process, stated exactly
 *
 * Phase 3 returns as soon as the host tells it the HTLC is held. The framework
 * then tears the instrumented process down, which is a real process death and not
 * a graceful shutdown — nothing calls `WalletService.stop`, no ldk-node teardown
 * runs, and whatever LDK had not persisted is gone. The host does not rely on
 * that alone: after the phase it issues `am kill` and then refuses to start phase
 * 4 until no process of the package exists. The pid it observed *during* the
 * window is handed to phase 4, which asserts it is not its own — so "the process
 * died" is a checked fact rather than an assumption about instrumentation
 * teardown.
 *
 * `am kill` and never `am force-stop`: force-stop puts the package in Android's
 * *stopped state*, which is a different event from process death and one the
 * platform treats differently. `wallet-node-device-tests.md` §2 is the same
 * correction for K2.
 *
 * ## The window this does NOT enter, said here rather than discovered later
 *
 * There is a second, narrower window inside `send`: between `ChannelManager`
 * committing the outbound payment and that state being persisted. It is not
 * reachable this way, because for part of it no HTLC exists for any counterparty
 * to hold. It is also a **smaller** claim — with nothing on the wire there is
 * nothing to double-spend and nothing to lose, so the worst it exposes is a
 * forgotten payment that never went out, which costs a retry rather than money.
 *
 * The distinction is load-bearing, because a run that killed the process in the
 * narrow window and passed would look exactly like a K7 result and would not be
 * one. So it is refused rather than labelled: phase 3 does not return until the
 * host has seen `state: ACCEPTED`, the host writes that state into the hand-off,
 * and [phase3PayTheHoldInvoiceAndLeaveItInFlight] asserts on its contents. A run
 * where the HTLC never reached LND fails in phase 3 and never reaches the kill.
 *
 * ## Which outcome is expected, and why settle rather than cancel
 *
 * The host **settles** the hold invoice while the app is dead. That is the
 * asymmetric direction: the money has left, LND holds the preimage, and the
 * wallet must come back knowing the payment succeeded. A wallet that reported
 * `Failed` there has lost the claim — it would show the user a failed payment
 * they were charged for, and a retry would pay twice. Cancelling instead tests
 * the cheaper direction (funds returned, payment failed), and is the obvious
 * second run for this suite once the first is green; it is not a substitute.
 *
 * Every method here is in `check-wallet-regtest-results.py`'s `REQUIRED` set by
 * name, per BIT-132's definition of done.
 */
@RunWith(AndroidJUnit4::class)
class K7InterruptedPaymentTest {

    /**
     * The same vacuity guard `RegtestEnvironmentTest` runs, restated per phase.
     *
     * Not redundant with that class, because these phases do not run in the same
     * instrumentation — or even necessarily in the same job, once someone
     * dispatches the K7 script by hand. A phase that ran against an unconfigured
     * build would reach [WalletGraph.nodeOnchain] and get
     * `NodeUnavailableException`, which reads as "the node died" when the truth
     * is "there was never a node". Those call for opposite investigations.
     */
    @Before
    fun thisBuildHasANodeInIt() {
        assertEquals(
            "This APK was built without a complete LdkEnvironment, so it composes " +
                "SeedWalletService and has no node to interrupt. K7 is not a claim " +
                "about this build. Run android/regtest/up.sh and supply the values " +
                "android/scripts/regtest-ldk-env.py prints.",
            emptyList<String>(),
            LdkEnvironmentConfig.missingFields(),
        )
    }

    /**
     * **Phase 1.** Start the node and reveal the address the host must fund.
     *
     * The host cannot derive this address and the shortcut that looks like it
     * should work does not: deriving it on the host needs ldk-node 0.7.0's exact
     * derivation path, which is not recoverable from the shipped artefact —
     * `strings` over `libldk_node.so` in all three ABIs finds the descriptor and
     * BIP-32 machinery and no path literal. A guess funds an address nothing is
     * watching and then fails at `openChannel` with an insufficient-funds error
     * that says nothing about derivation. So the device is asked, and asking is
     * the phase. See `NodeOnchainPort`.
     *
     * **ldk-node's on-chain wallet, never BDK's.** They are two wallets over one
     * seed and only the first is the one `openChannel` spends from. Funding the
     * other one is the quiet failure: the transaction confirms, the chain is
     * right, BDK reports a balance, and the channel open fails for want of funds.
     */
    @HostDriven
    @Test
    fun phase1RevealTheAddressTheHostMustFund() {
        val graph = walletGraph()
        startTheWalletTheAppComposed(graph.walletService(), mayCreate = true)

        val address = graph.nodeOnchain().newReceiveAddress().address
        assertTrue(
            "The node returned a blank on-chain address. There is nothing for the " +
                "host to fund and every later phase would fail at openChannel.",
            address.isNotBlank(),
        )

        // The pid is here for the same reason phase 3 prints one: it is the only
        // way a reader of a red run can tell "the node restarted between phases"
        // from "the node never came up".
        evidence("phase=1 fundingAddress=$address pid=${android.os.Process.myPid()}")
    }

    /**
     * **Phase 2.** Wait for the host's coins, then open the channel to LND.
     *
     * Returns as soon as `openChannel` has accepted the request rather than
     * waiting for the channel to become ready, and that is the phase boundary
     * rather than impatience: the funding transaction has to be **mined**, and
     * the only thing that can mine on this network is the host. A phase that
     * waited for ready inside the instrumentation would wait for a block nobody
     * was going to produce, and die on the job's timeout looking like a stalled
     * channel open.
     *
     * The confirmed balance is waited for rather than assumed for the mirror
     * reason: the host sent and mined before starting this phase, but ldk-node
     * learns about it from Esplora on its own sync schedule, so "the chain has
     * it" and "the node has it" are minutes apart and only the second one can
     * spend.
     */
    @HostDriven
    @Test
    fun phase2OpenAChannelToTheRegtestPeer() {
        val environment = requireNotNull(LdkEnvironmentConfig.fromBuildConfig())
        val graph = walletGraph()
        startTheWalletTheAppComposed(graph.walletService())
        val node = graph.lightningNode()

        val funded = awaitOrNull(FUNDING_TIMEOUT_MS, "the node to see its confirmed coins") {
            val spendable = node.listBalances()?.spendableOnchainBalanceSats ?: 0uL
            if (spendable >= CHANNEL_SATS + ONCHAIN_HEADROOM_SATS) spendable else null
        }
        assertNotNull(
            "The node's spendable on-chain balance did not reach " +
                "${CHANNEL_SATS + ONCHAIN_HEADROOM_SATS} sats within " +
                "${FUNDING_TIMEOUT_MS / 1000}s. Last reading: " +
                "${node.listBalances()?.spendableOnchainBalanceSats}. Either the " +
                "host funded a different address than phase 1 printed — BDK's " +
                "rather than the node's is the classic one — or the node is not " +
                "reaching Esplora, which RegtestEnvironmentTest would have caught.",
            funded,
        )

        // No push to the counterparty. The payment under test is ours to LND, so
        // what this channel needs is OUTBOUND capacity; pushing would hand LND
        // inbound liquidity we then have to route back, for nothing.
        val userChannelId = node.openChannel(
            nodeId = environment.lightningNodeId,
            address = environment.lightningNodeAddress,
            channelAmountSats = CHANNEL_SATS,
            pushToCounterpartyMsat = null,
        )
        assertTrue(
            "openChannel returned a blank user channel id.",
            userChannelId.isNotBlank(),
        )

        evidence(
            "phase=2 userChannelId=$userChannelId spendableOnchainSats=$funded " +
                "channelSats=$CHANNEL_SATS peer=${environment.lightningNodeId}",
        )
    }

    /**
     * **Phase 3.** Pay the hold invoice, and stay alive until the HTLC is stuck.
     *
     * The invoice arrives as an instrumentation argument, and so does the payment
     * hash the host chose the preimage for. Those two being consistent is
     * asserted rather than trusted, because ldk-node's BOLT11 `PaymentId` **is**
     * the payment hash, and phase 4 looks the payment up by the host's copy of it.
     * If that identity ever stops holding, this assertion says so — where the
     * alternative is phase 4 looking up nothing, finding no payment, and
     * reporting a fund-safety violation that is really a key mismatch.
     *
     * Then it waits for the hand-off. The wait is the whole design: returning
     * immediately after `send` would tear the process down somewhere inside the
     * *narrow* window, where no HTLC exists yet and the claim K7 makes is not
     * under test. The hand-off is written by the host only after
     * `lncli lookupinvoice` reports `state: ACCEPTED`, and its contents are
     * asserted here so that "the window was wide" is a device-side fact.
     */
    @HostDriven
    @Test
    fun phase3PayTheHoldInvoiceAndLeaveItInFlight() {
        val invoice = requireArgument(ARG_INVOICE)
        val expectedHash = requireArgument(ARG_PAYMENT_HASH)
        val graph = walletGraph()
        startTheWalletTheAppComposed(graph.walletService())
        val node = graph.lightningNode()

        val channel = awaitOrNull(CHANNEL_READY_TIMEOUT_MS, "the channel to become usable") {
            node.listChannels().firstOrNull { it.isChannelReady && it.isUsable }
        }
        assertNotNull(
            "No channel reached ready-and-usable within " +
                "${CHANNEL_READY_TIMEOUT_MS / 1000}s. Channels this node has: " +
                "${node.listChannels().map { it.summary() }}. The host mines the " +
                "funding transaction between phases 2 and 3, so an empty list here " +
                "means the open never broadcast and a pending one means it was " +
                "never mined.",
            channel,
        )
        requireNotNull(channel)
        assertTrue(
            "The channel is usable with ${channel.outboundCapacityMsat} msat " +
                "outbound, which cannot carry a $PAYMENT_AMOUNT_MSAT msat payment. " +
                "Raise CHANNEL_SATS, or lower the amount the host invoices for — " +
                "they are two constants that have to agree and this is where they " +
                "are checked against each other.",
            channel.outboundCapacityMsat >= PAYMENT_AMOUNT_MSAT,
        )

        val paymentId = node.sendBolt11(invoice, routeLimits = null)
        assertEquals(
            "ldk-node returned payment id '$paymentId' for an invoice whose payment " +
                "hash the host chose as '$expectedHash'. BIT-132 relies on those " +
                "being the same value: it is what lets phase 4 be handed the id to " +
                "look up as an argument rather than reading a file the kill may have " +
                "caught mid-write. They are not the same, so that assumption is now " +
                "wrong and phase 4 would look up nothing.",
            expectedHash,
            paymentId,
        )

        // Alive until the counterparty is holding it. See the class comment on
        // the two windows; this is the one that makes the run a K7 result.
        val handoff = awaitOrNull(HTLC_HELD_TIMEOUT_MS, "the host to see the HTLC accepted") {
            shell("cat $HANDOFF_PATH").trim().ifBlank { null }
        }
        assertNotNull(
            "The host never wrote $HANDOFF_PATH within " +
                "${HTLC_HELD_TIMEOUT_MS / 1000}s, so it never saw the HTLC accepted " +
                "at LND. Returning now would kill this process inside the NARROW " +
                "window — before anything is on the wire — and a pass from there is " +
                "not a K7 result. Failing instead. Look at the LND logs the job " +
                "prints: a route that could not be found, or a channel that went " +
                "unusable between the check above and the send.",
            handoff,
        )
        assertTrue(
            "The hand-off says '$handoff', which does not report the invoice as " +
                "ACCEPTED. Only an accepted HTLC is the wide window; anything else " +
                "means the host wrote the file for a state that is not the one this " +
                "test is about.",
            handoff!!.contains(HANDOFF_ACCEPTED),
        )

        val recorded = node.payment(paymentId)
        evidence(
            "phase=3 paymentId=$paymentId pid=${android.os.Process.myPid()} " +
                "window=wide-htlc-held-by-counterparty handoff='$handoff' " +
                "statusBeforeKill=${recorded?.status} " +
                "channelOutboundMsat=${channel.outboundCapacityMsat}",
        )
    }

    /**
     * **Phase 4.** After the kill and the settle: one outcome, and it sticks.
     *
     * Three separate assertions, because the claim has three ways to be false and
     * they are not the same failure:
     *
     * 1. **The process really did die.** Asserted against the pid the host read
     *    while the HTLC was held. Without it a phase 4 that happened to run in
     *    the same process would pass having interrupted nothing — the vacuous
     *    green this whole suite is built to refuse.
     * 2. **Exactly one record.** A payment that came back as two entries for one
     *    hash is the double-spend shape: the wallet believes it owes the money
     *    twice, and a retry screen built on `listPayments()` would offer to pay
     *    it again.
     * 3. **It is terminal, it is `Succeeded`, and it stays that way.** The host
     *    settled while the app was dead, so LND has the preimage and the money is
     *    gone. `Failed` here is the lost claim — the worst available outcome and
     *    the one this test exists for. `Pending` forever is the second worst.
     *    Stability is re-read rather than assumed because a status that flips
     *    after the first read is not one outcome, it is two.
     */
    @HostDriven
    @Test
    fun phase4TheInterruptedPaymentResolvedToExactlyOneOutcome() {
        val paymentHash = requireArgument(ARG_PAYMENT_HASH)
        val killedPid = requireArgument(ARG_KILLED_PID).toIntOrNull()
        assertNotNull(
            "The host passed $ARG_KILLED_PID='${argument(ARG_KILLED_PID)}', which is " +
                "not a pid. It is the process it observed holding the in-flight " +
                "payment, and without it this phase cannot show the process died.",
            killedPid,
        )
        assertNotEquals(
            "This phase is running in pid ${android.os.Process.myPid()}, the same " +
                "process that sent the payment. Nothing was interrupted, so a pass " +
                "here would measure nothing. The host's kill did not take.",
            killedPid,
            android.os.Process.myPid(),
        )

        val graph = walletGraph()
        startTheWalletTheAppComposed(graph.walletService())
        val node = graph.lightningNode()

        val resolved = awaitOrNull(RESOLUTION_TIMEOUT_MS, "the payment to reach a terminal state") {
            node.payment(paymentHash)?.takeIf { it.status != PaymentStatusView.Pending }
        }
        assertNotNull(
            "Payment $paymentHash was still ${node.payment(paymentHash)?.status} after " +
                "${RESOLUTION_TIMEOUT_MS / 1000}s of a restarted node. The host " +
                "settled the hold invoice while this process was dead, so LND has " +
                "the preimage and the funds have left. A payment that never resolves " +
                "is money the wallet cannot account for. If the record is null " +
                "instead, the send was not durable across the kill at all, which is " +
                "the other half of K7's claim.",
            resolved,
        )
        requireNotNull(resolved)

        val forThisHash = node.listPayments().filter { it.cacheId == paymentHash || it.id == paymentHash }
        assertEquals(
            "listPayments() holds ${forThisHash.size} records for payment hash " +
                "$paymentHash: ${forThisHash.map { it.summary() }}. Exactly one is " +
                "the claim — more than one is the double-spend shape, where the " +
                "wallet believes it owes the same invoice twice.",
            1,
            forThisHash.size,
        )

        assertEquals(
            "The interrupted payment resolved to ${resolved.status}. The host " +
                "settled the hold invoice, so the counterparty holds the preimage " +
                "and the money is gone — a wallet reporting Failed has LOST THE " +
                "CLAIM: it would show the user a failed payment they were charged " +
                "for, and any retry pays twice. This is the fund-safety finding K7 " +
                "was written to produce; it is not a flake and must not be rerun " +
                "away. Record: ${resolved.summary()}.",
            PaymentStatusView.Succeeded,
            resolved.status,
        )

        // One outcome, not one reading. A status that moves after the first look
        // is two outcomes with a delay between them.
        val settled = mutableListOf(resolved.status)
        repeat(STABILITY_READS) {
            Thread.sleep(STABILITY_INTERVAL_MS)
            node.payment(paymentHash)?.let { settled += it.status }
        }
        assertEquals(
            "The payment's status moved after it was already terminal: $settled. " +
                "'Exactly one terminal outcome' is a claim about the sequence, not " +
                "about a single read.",
            listOf(PaymentStatusView.Succeeded),
            settled.distinct(),
        )

        evidence(
            "phase=4 paymentId=$paymentHash pid=${android.os.Process.myPid()} " +
                "killedPid=$killedPid outcome=${resolved.status} " +
                "records=${forThisHash.size} statuses=$settled " +
                "amountMsat=${resolved.amountMsat} feePaidMsat=${resolved.feePaidMsat}",
        )
    }

    // ---- The wallet the app composed, and how a phase gets into it. ------------

    /**
     * The `WalletService` and ports the running application built for itself.
     *
     * `EntryPointAccessors.fromApplication`, over an `@EntryPoint` declared in
     * `:app`'s **main** source set. That placement was measured rather than
     * assumed — the `androidTest` one compiles and produces no aggregating
     * metadata, so this call would fail at run time in a job that compiled clean.
     * `WalletGraph`'s own comment carries the evidence.
     */
    private fun walletGraph(): WalletGraph = EntryPointAccessors.fromApplication(
        InstrumentationRegistry.getInstrumentation().targetContext.applicationContext,
        WalletGraph::class.java,
    )

    /**
     * Get the wallet to [WalletState.Ready] with a node running, from whatever
     * state this phase found the device in.
     *
     * Phase 1 finds no wallet and creates one. Phases 2 to 4 find the wallet
     * phase 1 created — it is under `no_backup`, which survives `adb install -r`
     * and survives the kill — and only have to unlock and start.
     *
     * `start()` is called unconditionally rather than only when locked, because
     * it is the app's own idempotent way in (`WalletNodeHost.start`) and the
     * state after a process death is *Locked with no node*, which is not
     * distinguishable here from *Ready with a node that just died*.
     */
    private fun startTheWalletTheAppComposed(
        wallet: WalletService,
        mayCreate: Boolean = false,
    ) = runBlocking {
        if (wallet.state.value == WalletState.Uninitialized) {
            // Phases 2 to 4 must NOT create one, and this is the assertion that
            // makes a wiped device say so. The four phases share one install:
            // AGP reinstalls with `adb install -r` between them, which preserves
            // app data, and `leaveApksInstalledAfterRun=true` stops it
            // uninstalling at the end of each. If either of those ever stops
            // holding, a later phase would silently create a SECOND wallet and
            // then wait out its timeout for coins that were sent to the first
            // one's address — a harness failure wearing the costume of a chain
            // problem.
            assertTrue(
                "This phase found no wallet on the device. Phase 1 created one and " +
                    "the phases share one install, so the data directory was cleared " +
                    "between them: AGP uninstalled the app despite " +
                    "leaveApksInstalledAfterRun, or something else reinstalled it. " +
                    "Creating a fresh wallet here would leave the funded one behind " +
                    "and fail later for a reason that is not about K7.",
                mayCreate,
            )
            wallet.createWallet()
            wallet.setPin(PIN)
        }
        if (wallet.state.value != WalletState.Ready) {
            assertTrue(
                "unlock('$PIN') was refused on a wallet this suite created with that " +
                    "PIN. The device is carrying a wallet from something other than " +
                    "K7 — a previous suite, or a phase 1 that half-completed. The " +
                    "phases share one install by design; they cannot share it with " +
                    "another test's wallet.",
                wallet.unlock(PIN),
            )
        }
        wallet.start()
        assertEquals(
            "The wallet did not reach Ready after start(). There is no node to " +
                "interrupt, so nothing below would be a K7 result.",
            WalletState.Ready,
            wallet.state.value,
        )
    }

    // ---- Host hand-off and arguments. ------------------------------------------

    /**
     * Read a file as the shell user, through `UiAutomation`.
     *
     * The hand-off cannot be a file in the app's own data directory in *this*
     * direction. The host writes it, and a host writing into `/data/data/<pkg>/`
     * needs `adb root`, which is a "cannot look" on any image that refuses it —
     * and a hand-off that silently never arrives would leave phase 3 returning
     * early, killing the process in the narrow window, and producing a pass that
     * is not a K7 result. `/data/local/tmp` is writable by `adb shell` on every
     * image, and `UiAutomation.executeShellCommand` runs as that same shell user,
     * so the read needs nothing the app does not already have.
     *
     * (`BackupExclusionTest`'s hand-off goes the other way — test writes, host
     * reads — which is why it can live under `no_backup`.)
     */
    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand(command)
            .let { descriptor ->
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
                    it.readBytes().decodeToString()
                }
            }

    private fun argument(name: String): String? =
        InstrumentationRegistry.getArguments().getString(name)

    private fun requireArgument(name: String): String = requireNotNull(argument(name)) {
        "Instrumentation argument '$name' was not supplied. These phases are driven " +
            "by android/scripts/k7-interrupted-payment.sh, which passes it as " +
            "-Pandroid.testInstrumentationRunnerArguments.$name. A phase run by hand " +
            "has to supply it too."
    }

    /**
     * Poll [read] until it answers non-null or [timeoutMs] elapses.
     *
     * Returns null on timeout rather than throwing, so every caller can say in
     * its own words what did not happen and what the last reading was. A shared
     * "timed out waiting for $what" would be the same sentence for a node that
     * never synced and a channel that never confirmed, and those are different
     * investigations.
     */
    private fun <T : Any> awaitOrNull(timeoutMs: Long, what: String, read: () -> T?): T? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            runCatching(read).getOrNull()?.let { return it }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        println("$EVIDENCE waitTimedOut what='$what' afterMs=$timeoutMs")
        return null
    }

    private fun evidence(line: String) = println("$EVIDENCE $line")

    private fun ChannelView.summary() =
        "[$userChannelId ready=$isChannelReady usable=$isUsable out=${outboundCapacityMsat}msat]"

    private fun PaymentView.summary() =
        "[$id ${direction}/${status} amount=${amountMsat}msat kind=${kind::class.simpleName}]"

    private companion object {

        /**
         * The PIN phase 1 sets and every later phase unlocks with.
         *
         * The same literal `SeedReadableWhileLockedTest` uses, deliberately: this
         * suite and that one never share a device, and one throwaway PIN in the
         * repository is easier to grep for than two.
         */
        const val PIN = "2468"

        /**
         * The channel this suite opens, and the payment it carries.
         *
         * Sized so the payment is comfortably inside the outbound capacity after
         * LDK's reserve — the counterparty's `unspendablePunishmentReserve` is 1%
         * of capacity by default and the anchor reserve is on top of it. Phase 3
         * checks the two against each other rather than trusting this arithmetic,
         * because the reserve is LDK's policy and not ours.
         */
        const val CHANNEL_SATS = 1_000_000uL

        /** 50,000 sats. Big enough to be visible in a balance, small enough to route in one hop. */
        const val PAYMENT_AMOUNT_MSAT = 50_000_000uL

        /**
         * On-chain sats the node must hold *beyond* the channel amount before
         * phase 2 will try to open.
         *
         * Not a safety margin for its own sake. ldk-node reserves for anchor
         * outputs out of the on-chain wallet — BIT-126's finding that the on-chain
         * balance the app shows is ldk-node's rather than BDK's is the same fact
         * from the other side — and a channel open that consumes the whole
         * balance fails with an error about the reserve rather than about the
         * amount.
         */
        const val ONCHAIN_HEADROOM_SATS = 100_000uL

        const val ARG_INVOICE = "k7Invoice"
        const val ARG_PAYMENT_HASH = "k7PaymentHash"
        const val ARG_KILLED_PID = "k7KilledPid"

        /**
         * Where the host says the HTLC is stuck.
         *
         * Duplicated in `android/scripts/k7-interrupted-payment.sh`, and the
         * duplication is checked rather than trusted:
         * `android/scripts/test_k7_host_phase.sh` pins this path and the marker
         * below against that script in the build job. A drift makes phase 3 wait
         * out its timeout and fail — which is the safe direction, and still a
         * wasted emulator hour at 03:20 UTC.
         */
        const val HANDOFF_PATH = "/data/local/tmp/k7-htlc-state"

        /** LND's own word for it, as `lncli lookupinvoice` prints it. */
        const val HANDOFF_ACCEPTED = "ACCEPTED"

        const val POLL_INTERVAL_MS = 2_000L

        /** Chain sync after the host funds and mines. Esplora, not a block race. */
        const val FUNDING_TIMEOUT_MS = 240_000L

        /** The channel open the host mined between phases 2 and 3. */
        const val CHANNEL_READY_TIMEOUT_MS = 240_000L

        /** How long the host gets to see the HTLC land at LND. Route-finding, not chain. */
        const val HTLC_HELD_TIMEOUT_MS = 180_000L

        /** Reconnect, re-establish, and LND replaying the settle it made while we were dead. */
        const val RESOLUTION_TIMEOUT_MS = 300_000L

        const val STABILITY_READS = 3
        const val STABILITY_INTERVAL_MS = 3_000L

        /** The prefix `check-wallet-regtest-results.py` greps out of `<system-out>`. */
        const val EVIDENCE = "K7_INTERRUPTED_PAYMENT"
    }
}
