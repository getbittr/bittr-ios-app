package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `startBDK()` + `BackgroundSync`, driven on virtual time with no BDK.
 *
 * The loop is the piece that was missing after BIT-124 — `BdkWalletFactory.open`
 * and [OnchainSync] both existed with no caller — so what is asserted here is
 * the *sequence*: what has to succeed before the timer starts, what the timer
 * does, and what happens on the way out. All of it on the JVM, because
 * [OnchainSyncLoop] names no BDK type and [OnchainSync] is instantiated over
 * `String`.
 *
 * Three of these are negative controls rather than coverage:
 *
 * - `a failed full scan starts no light-sync timer` fails if the `return` after
 *   [OnchainLoopEvent.FullScanFailed] is softened into a fall-through. A light
 *   sync only revisits scripts the wallet has revealed, so a timer on an
 *   unscanned wallet is round trips that cannot find anything.
 * - `a second run does not re-scan` fails if `hasBeenScanned` is dropped, which
 *   is tempting because [BdkStore] wipes the store on every *process* start and
 *   the branch then looks redundant. It is not: a node restart inside one
 *   process would otherwise pay for a second full scan.
 * - `cancellation clears the scan state before closing the wallet` fails if the
 *   teardown is written in the iOS listing's order. The generation bump has to
 *   land while the flags still describe a live wallet.
 *
 * BIT-144 added a fourth: the balance read borrows this loop's clock rather than
 * bringing a timer of its own, and `the balance read runs after each sync, not
 * before` fails if it is hoisted above the sync. `OnchainSync` runs the closure
 * scan at the end of a sync that applied, and the read's last cache write clears
 * the very outpoint that scan is about to need.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OnchainSyncLoopTest {

    /** A recording [OnchainWalletPort]. Idempotent, like `didStartBDK`. */
    private class FakeWallet(private var canOpen: Boolean = true) : OnchainWalletPort {

        val calls = mutableListOf<String>()
        var isOpen = false

        fun refuseToOpen() { canOpen = false }

        override fun open(): Boolean {
            calls += "open"
            if (!canOpen) return false
            isOpen = true
            return true
        }

        override fun close() {
            calls += "close"
            isOpen = false
        }
    }

    /**
     * The minimum [OnchainSyncPort] this test needs: applies unless told not to.
     *
     * [OnchainSyncTest] is where the sequence inside a single sync is asserted.
     * What matters here is only whether it reported success.
     */
    private class StubPort : OnchainSyncPort<String, String, String, String> {

        var wallet: String? = "wallet"
        var applies = true
        var fullScans = 0
        var lightSyncs = 0

        override fun currentWallet(): String? = wallet

        override fun startFullScan(wallet: String): String = "full-scan-request"

        override fun fullScan(request: String, parameters: FullScanParameters): String {
            fullScans += 1
            if (!applies) throw IllegalStateException("electrum unreachable")
            return "update"
        }

        override fun startSyncWithRevealedSpks(wallet: String): String = "sync-request"

        override fun sync(request: String, parameters: LightSyncParameters): String {
            lightSyncs += 1
            if (!applies) throw IllegalStateException("electrum unreachable")
            return "update"
        }

        override fun applyUpdate(wallet: String, update: String) = Unit

        override fun persist(wallet: String) = Unit
    }

    private class Fixture(val scope: TestScope, canOpen: Boolean = true) {

        val wallet = FakeWallet(canOpen)
        val port = StubPort()
        val scans = ScanCoordinator(scope)
        val events = mutableListOf<OnchainLoopEvent>()

        fun loop(balances: WalletBalanceRead? = null) = OnchainSyncLoop(
            wallet = wallet,
            sync = OnchainSync(port, scans, closures = null),
            scans = scans,
            balances = balances,
            report = { events += it },
        )
    }

    @Test
    fun `a start scans and then light-syncs on the iOS interval`() = runTest {
        val fixture = Fixture(this)
        val runner = launch { fixture.loop().run() }

        runCurrent()
        assertEquals(listOf(OnchainLoopEvent.FullScanApplied), fixture.events)
        assertEquals("no light sync before the first interval", 0, fixture.port.lightSyncs)

        // `BackgroundSync.swift:18` — first fire at +30s, then every 30s.
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()
        assertEquals(1, fixture.port.lightSyncs)

        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS * 3)
        runCurrent()
        assertEquals(4, fixture.port.lightSyncs)
        assertEquals(
            listOf(
                OnchainLoopEvent.FullScanApplied,
                OnchainLoopEvent.LightSyncApplied,
                OnchainLoopEvent.LightSyncApplied,
                OnchainLoopEvent.LightSyncApplied,
                OnchainLoopEvent.LightSyncApplied,
            ),
            fixture.events,
        )

        runner.cancelAndJoin()
    }

    @Test
    fun `a wallet that will not open ends the runner and scans nothing`() = runTest {
        val fixture = Fixture(this, canOpen = false)

        fixture.loop().run()

        assertEquals(listOf(OnchainLoopEvent.WalletUnavailable), fixture.events)
        assertEquals(0, fixture.port.fullScans)
        // iOS's `guard let cachedMnemonic else { return false }` is a teardown,
        // not an error, and the close still runs.
        assertEquals(listOf("open", "close"), fixture.wallet.calls)
    }

    @Test
    fun `a failed full scan starts no light-sync timer`() = runTest {
        val fixture = Fixture(this)
        fixture.port.applies = false

        fixture.loop().run()

        assertEquals(listOf(OnchainLoopEvent.FullScanFailed), fixture.events)
        assertEquals(1, fixture.port.fullScans)
        // The negative control: the loop returned rather than falling through to
        // `delay`, so no amount of virtual time produces a light sync.
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS * 10)
        runCurrent()
        assertEquals(0, fixture.port.lightSyncs)
        assertFalse(fixture.scans.hasBeenScanned)
    }

    @Test
    fun `a second run does not re-scan`() = runTest {
        val fixture = Fixture(this)

        val first = launch { fixture.loop().run() }
        runCurrent()
        assertEquals(1, fixture.port.fullScans)
        first.cancelAndJoin()

        // `ScanCoordinator.clear()` runs on the way out, so the *shared*
        // coordinator a second node start would be handed is a fresh one — which
        // is why this fixture rebuilds the loop against a coordinator that was
        // deliberately not cleared. iOS's `bdkWalletHasBeenScanned` is a property
        // of the process, and this is the branch that reads it.
        val scans = ScanCoordinator(this)
        scans.fullScan { true }
        assertTrue(scans.hasBeenScanned)

        val port = StubPort()
        val events = mutableListOf<OnchainLoopEvent>()
        val second = launch {
            OnchainSyncLoop(
                wallet = FakeWallet(),
                sync = OnchainSync(port, scans, closures = null),
                scans = scans,
                balances = null,
                report = { events += it },
            ).run()
        }
        runCurrent()

        assertEquals(listOf(OnchainLoopEvent.AlreadyScanned), events)
        assertEquals("no second full scan", 0, port.fullScans)

        // It still gets the timer — iOS's `guard !hasBeenScanned else { restart
        // the light sync timer; return }`.
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()
        assertEquals(1, port.lightSyncs)

        second.cancelAndJoin()
    }

    @Test
    fun `a light sync that does not apply is reported and the timer continues`() = runTest {
        val fixture = Fixture(this)
        val runner = launch { fixture.loop().run() }
        runCurrent()

        // The connectivity case: the wallet scanned, then Electrum went away.
        fixture.port.applies = false
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()
        assertEquals(OnchainLoopEvent.LightSyncSkipped, fixture.events.last())

        // And it recovers, rather than the loop having ended on the failure.
        fixture.port.applies = true
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()
        assertEquals(OnchainLoopEvent.LightSyncApplied, fixture.events.last())

        runner.cancelAndJoin()
    }

    // ---- The balance read, which borrows this loop's clock. ----

    /**
     * A [WalletBalanceRead] that records when it ran and can report no node.
     *
     * `WalletBalanceReaderTest` owns what a read *does*. What matters here is
     * only when the loop calls it and what it reports.
     */
    private class FakeBalanceRead(var hasNode: Boolean = true) : WalletBalanceRead {
        var reads = 0
        override fun read(): Boolean {
            reads += 1
            return hasNode
        }
    }

    /**
     * The ordering the closure scan depends on.
     *
     * `OnchainSync` records a closure at the end of a sync that applied, using
     * the funding outpoint this read wrote on an earlier tick — and the read's
     * third cache write *clears* that outpoint once a closure is pending. Hoist
     * the read above `sync.lightSync()` and the clear lands in the same tick the
     * scan was about to use it, so the closing transaction is never recorded.
     *
     * The event sequence is what pins it: `BalancesRead` after each sync event,
     * never before.
     */
    @Test
    fun `the balance read runs after each sync, not before`() = runTest {
        val fixture = Fixture(this)
        val balances = FakeBalanceRead()
        val runner = launch { fixture.loop(balances).run() }

        runCurrent()
        assertEquals(
            listOf(OnchainLoopEvent.FullScanApplied, OnchainLoopEvent.BalancesRead),
            fixture.events,
        )

        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS * 2)
        runCurrent()
        assertEquals(
            listOf(
                OnchainLoopEvent.FullScanApplied,
                OnchainLoopEvent.BalancesRead,
                OnchainLoopEvent.LightSyncApplied,
                OnchainLoopEvent.BalancesRead,
                OnchainLoopEvent.LightSyncApplied,
                OnchainLoopEvent.BalancesRead,
            ),
            fixture.events,
        )
        assertEquals("one read per tick, plus the one at the start", 3, balances.reads)

        runner.cancelAndJoin()
    }

    /**
     * The read is a *node* read. BDK failing to reach Electrum says nothing about
     * whether a channel has opened or closed, so a skipped light sync still gets
     * one — otherwise a wallet with a flaky Electrum server would stop watching
     * its channel for as long as the server was down.
     */
    @Test
    fun `a light sync that did not apply still reads the balances`() = runTest {
        val fixture = Fixture(this)
        val balances = FakeBalanceRead()
        val runner = launch { fixture.loop(balances).run() }
        runCurrent()

        fixture.port.applies = false
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()

        assertEquals(
            listOf(OnchainLoopEvent.LightSyncSkipped, OnchainLoopEvent.BalancesRead),
            fixture.events.takeLast(2),
        )

        runner.cancelAndJoin()
    }

    /** A stop between two ticks. Reported rather than silent, and the loop continues. */
    @Test
    fun `no node to read is reported and the timer keeps running`() = runTest {
        val fixture = Fixture(this)
        val balances = FakeBalanceRead(hasNode = false)
        val runner = launch { fixture.loop(balances).run() }
        runCurrent()
        assertEquals(OnchainLoopEvent.BalancesUnavailable, fixture.events.last())

        balances.hasNode = true
        advanceTimeBy(OnchainSyncLoop.LIGHT_SYNC_INTERVAL_MILLIS)
        runCurrent()
        assertEquals(OnchainLoopEvent.BalancesRead, fixture.events.last())

        runner.cancelAndJoin()
    }

    /**
     * The cost `OnchainSyncLoop`'s class comment states, asserted rather than
     * only written down: the balance read has no clock of its own, so the
     * `return` after a failed full scan takes it too.
     *
     * This is not the behaviour anybody would choose if the read had a consumer
     * beyond the closure scan — which also only runs off an applied sync. It is
     * pinned here so that the day one appears, this test is what says the answer
     * is a runner of its own rather than a softened `return`.
     */
    @Test
    fun `a failed full scan takes the balance read with it`() = runTest {
        val fixture = Fixture(this)
        val balances = FakeBalanceRead()
        fixture.port.applies = false

        fixture.loop(balances).run()

        assertEquals(listOf(OnchainLoopEvent.FullScanFailed), fixture.events)
        assertEquals(0, balances.reads)
    }

    /**
     * A second node inside one process skips the full scan and still reads.
     *
     * The outpoint to watch is a question about the channels *this* node reports,
     * and `ScanCoordinator.hasBeenScanned` says nothing about them.
     */
    @Test
    fun `an already-scanned wallet still reads the balances at the start`() = runTest {
        val scans = ScanCoordinator(this)
        scans.fullScan { true }
        assertTrue(scans.hasBeenScanned)

        val balances = FakeBalanceRead()
        val events = mutableListOf<OnchainLoopEvent>()
        val runner = launch {
            OnchainSyncLoop(
                wallet = FakeWallet(),
                sync = OnchainSync(StubPort(), scans, closures = null),
                scans = scans,
                balances = balances,
                report = { events += it },
            ).run()
        }
        runCurrent()

        assertEquals(
            listOf(OnchainLoopEvent.AlreadyScanned, OnchainLoopEvent.BalancesRead),
            events,
        )

        runner.cancelAndJoin()
    }

    @Test
    fun `cancellation closes the wallet`() = runTest {
        val fixture = Fixture(this)
        val runner = launch { fixture.loop().run() }
        runCurrent()
        assertTrue(fixture.wallet.isOpen)

        runner.cancelAndJoin()

        // ARC does this on iOS; here it is the `finally`, and it is the reason
        // the loop has one — a stop on Android arrives as a cancellation.
        assertEquals(listOf("open", "close"), fixture.wallet.calls)
        assertFalse(fixture.wallet.isOpen)
    }

    @Test
    fun `cancellation clears the scan state before closing the wallet`() = runTest {
        val fixture = Fixture(this)
        val order = mutableListOf<String>()

        // `hasBeenScanned` is true until `clear()`, so reading it from inside
        // `close()` says which of the two ran first.
        val wallet = object : OnchainWalletPort {
            override fun open(): Boolean = true
            override fun close() {
                order += if (fixture.scans.hasBeenScanned) "close-before-clear" else "close-after-clear"
            }
        }

        val runner = launch {
            OnchainSyncLoop(
                wallet = wallet,
                sync = OnchainSync(fixture.port, fixture.scans, closures = null),
                scans = fixture.scans,
                balances = null,
            ).run()
        }
        runCurrent()
        assertTrue(fixture.scans.hasBeenScanned)

        runner.cancelAndJoin()

        // The negative control. Written in the iOS listing's order — references
        // first, flags after — this reads `close-before-clear`, and a watchdog
        // still armed for the abandoned scan could mark the next node's.
        assertEquals(listOf("close-after-clear"), order)
    }
}
