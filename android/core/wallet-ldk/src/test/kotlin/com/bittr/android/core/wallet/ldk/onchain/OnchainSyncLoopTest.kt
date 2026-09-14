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

        fun loop() = OnchainSyncLoop(
            wallet = wallet,
            sync = OnchainSync(port, scans, closures = null),
            scans = scans,
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
