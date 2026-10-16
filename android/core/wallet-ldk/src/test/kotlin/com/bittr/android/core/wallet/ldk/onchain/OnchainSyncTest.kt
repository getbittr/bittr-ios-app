package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The BDK sync sequence, driven on the JVM with no native library.
 *
 * This is the test the four type parameters on [OnchainSync] exist for. BDK's
 * `Wallet`, `Update` and request types are all JNA-pointer objects, so a test
 * written against them would need an emulator; instantiated over `String` the
 * same sequence runs here, and what is asserted — the parameters going to
 * Electrum, which failures are fatal, and whether the wallet is re-checked — is
 * the whole of what `BdkSyncPort` cannot get wrong on its own.
 *
 * Two of these are negative controls rather than coverage:
 *
 * - `a persist failure still reports the sync as applied` is the one that fails
 *   if somebody "tidies" the persist into the same `return` shape as the steps
 *   above it. The cost of that mistranslation is a wallet that refuses to let
 *   its owner spend — see [OnchainSync]'s class comment.
 * - `a wallet replaced during the network call is not updated` fails if the
 *   identity re-check is dropped, which is easy to do because it looks like a
 *   re-read of something already in hand.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OnchainSyncTest {

    /**
     * A recording [OnchainSyncPort] over `String`.
     *
     * Every step can be made to throw, and [onFetch] runs *during* the network
     * call so the tests can do what a teardown does: replace the wallet while a
     * scan is in flight.
     */
    private class FakeSyncPort : OnchainSyncPort<String, String, String, String> {

        var wallet: String? = "wallet-1"

        /** Call names in order. The sequence under test is an order, so it is asserted as one. */
        val calls = mutableListOf<String>()

        var fullScanParameters: FullScanParameters? = null
        var lightSyncParameters: LightSyncParameters? = null

        var buildFailure: (() -> Exception)? = null
        var fetchFailure: (() -> Exception)? = null
        var applyFailure: (() -> Exception)? = null
        var persistFailure: (() -> Exception)? = null

        /** Runs inside the Electrum round trip. */
        var onFetch: (() -> Unit)? = null

        override fun currentWallet(): String? = wallet

        override fun startFullScan(wallet: String): String {
            calls += "startFullScan"
            buildFailure?.let { throw it() }
            return "full-scan-request"
        }

        override fun fullScan(request: String, parameters: FullScanParameters): String {
            calls += "fullScan"
            fullScanParameters = parameters
            onFetch?.invoke()
            fetchFailure?.let { throw it() }
            return "update-from-$request"
        }

        override fun startSyncWithRevealedSpks(wallet: String): String {
            calls += "startSyncWithRevealedSpks"
            buildFailure?.let { throw it() }
            return "sync-request"
        }

        override fun sync(request: String, parameters: LightSyncParameters): String {
            calls += "sync"
            lightSyncParameters = parameters
            onFetch?.invoke()
            fetchFailure?.let { throw it() }
            return "update-from-$request"
        }

        override fun applyUpdate(wallet: String, update: String) {
            calls += "applyUpdate($update)"
            applyFailure?.let { throw it() }
        }

        override fun persist(wallet: String) {
            calls += "persist"
            persistFailure?.let { throw it() }
        }

        var reconnectFailure: (() -> Exception)? = null

        override fun reconnectElectrum() {
            calls += "reconnectElectrum"
            reconnectFailure?.let { throw it() }
        }
    }

    /** A [BdkScanRecord] in memory. */
    private class FakeRecord : BdkScanRecord {
        var fullScanStored = false
        override var rebuildRequested = false
        override val hasStoredFullScan: Boolean get() = fullScanStored
        override fun storeFullScanCompletion() { fullScanStored = true }
        override fun clearFullScanCompletion() { fullScanStored = false }
        override fun requestRebuild() { rebuildRequested = true; fullScanStored = false }
        override fun clearRebuildRequest() { rebuildRequested = false }
    }

    /**
     * `closures = null` because this class is about the *sequence*: the order
     * of the steps and which failure stops it. The closure scan hanging off the
     * end of a sync that applied is `ChannelClosureRecorderTest`'s, and it
     * asserts its position there against the same class.
     */
    private fun sync(
        port: FakeSyncPort,
        scans: ScanCoordinator,
        record: BdkScanRecord? = null,
        reopenWallet: (() -> Boolean)? = null,
    ) = OnchainSync(port, scans, closures = null, record = record, reopenWallet = reopenWallet)

    /**
     * The step a sync stopped at, or a failure that says what happened instead.
     *
     * `outcome as SyncOutcome.NotApplied` reads the same and fails as a
     * `ClassCastException` with no message — which is what the negative control
     * for the identity re-check produces when the check is removed, and it is
     * the least useful thing to hand somebody who has just broken it.
     */
    private fun stepOf(outcome: SyncOutcome, expectation: String): SyncStep {
        assertTrue(
            "$expectation\n  Expected the sync to stop, but it completed: $outcome",
            outcome is SyncOutcome.NotApplied,
        )
        return (outcome as SyncOutcome.NotApplied).step
    }

    // --- The parameters that decide which coins are visible ------------------

    @Test
    fun `a full scan passes the parameters iOS passes`() = runTest {
        val port = FakeSyncPort()
        sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(
            "stopGap is how far past the last used address BDK looks. Below iOS's " +
                "25 the wallet hides coins iOS can see; above it, it shows coins " +
                "iOS cannot. Neither shows up as an error (BDKManager.swift:258–263).",
            FullScanParameters(stopGap = 25uL, batchSize = 25uL, fetchPrevTxouts = true),
            port.fullScanParameters,
        )
    }

    @Test
    fun `a light sync passes the parameters iOS passes`() = runTest {
        val port = FakeSyncPort()
        sync(port, ScanCoordinator(this)).runLightSync()

        assertEquals(
            "BDKManager.swift:332–336. No stop gap: a light sync only revisits " +
                "already-revealed scripts.",
            LightSyncParameters(batchSize = 25uL, fetchPrevTxouts = true),
            port.lightSyncParameters,
        )
    }

    @Test
    fun `each path uses its own request builder`() = runTest {
        val full = FakeSyncPort()
        sync(full, ScanCoordinator(this)).runFullScan()
        assertEquals(
            listOf("startFullScan", "fullScan", "applyUpdate(update-from-full-scan-request)", "persist"),
            full.calls,
        )

        val light = FakeSyncPort()
        sync(light, ScanCoordinator(this)).runLightSync()
        assertEquals(
            "A light sync run through the full-scan builder would still return an " +
                "Update — the wrong one, quietly.",
            listOf("startSyncWithRevealedSpks", "sync", "applyUpdate(update-from-sync-request)", "persist"),
            light.calls,
        )
    }

    // --- Which failures are fatal -------------------------------------------

    @Test
    fun `a persist failure still reports the sync as applied`() = runTest {
        val port = FakeSyncPort()
        val boom = IllegalStateException("sqlite is gone")
        port.persistFailure = { boom }

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        val applied = outcome as? SyncOutcome.Applied
        assertTrue(
            "iOS catches the persist and falls through to completion(true) " +
                "(BDKManager.swift:246–252). The update is already in the wallet, so the " +
                "balance on screen is correct. Reporting failure here would leave " +
                "hasBeenScanned false, and four iOS call sites read that to decide " +
                "whether the user may open the send screen at all. Got: $outcome",
            applied != null,
        )
        assertFalse("The store did not take it, and the caller should be able to see that", applied!!.persisted)
        assertSame(boom, applied.persistFailure)
    }

    @Test
    fun `an applyUpdate failure fails the sync`() = runTest {
        val port = FakeSyncPort()
        port.applyFailure = { IllegalStateException("cannot connect") }

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(
            SyncStep.ApplyUpdate,
            stepOf(outcome, "The wallet's view is unchanged, so a success here would report a pre-scan balance as a post-scan one."),
        )
        assertFalse("persist must not run after a failed apply", "persist" in port.calls)
    }

    @Test
    fun `a failed Electrum round trip stops before the wallet is touched`() = runTest {
        val port = FakeSyncPort()
        port.fetchFailure = { java.io.IOException("electrum unreachable") }

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(SyncStep.FetchUpdate, stepOf(outcome, "Electrum was unreachable."))
        assertEquals(listOf("startFullScan", "fullScan"), port.calls)
    }

    @Test
    fun `a failed request build is reported as its own step`() = runTest {
        val port = FakeSyncPort()
        port.buildFailure = { IllegalArgumentException("descriptor") }

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(SyncStep.BuildRequest, stepOf(outcome, "The request could not be built."))
        assertEquals(listOf("startFullScan"), port.calls)
    }

    @Test
    fun `no wallet is not a scan`() = runTest {
        val port = FakeSyncPort()
        port.wallet = null

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(SyncStep.NoWallet, stepOf(outcome, "There is no wallet to sync."))
        assertTrue("Nothing should have been attempted", port.calls.isEmpty())
        assertNull("A guard step throws nothing, so it carries no cause", (outcome as SyncOutcome.NotApplied).cause)
    }

    // --- The negative control for the identity re-check ----------------------

    @Test
    fun `a wallet replaced during the network call is not updated`() = runTest {
        val port = FakeSyncPort()
        // What a teardown-and-restart does while a 180-second scan is in flight.
        // On Android this is routine, not exotic: process death and
        // foreground-service restarts both produce it.
        port.onFetch = { port.wallet = "wallet-2" }

        val outcome = sync(port, ScanCoordinator(this)).runFullScan()

        assertEquals(
            SyncStep.WalletReplaced,
            stepOf(
                outcome,
                "iOS: `guard self.bdkWallet === bdkWallet else { return false }`. The update " +
                    "was built against the old wallet's chain view; applying it to the new " +
                    "one is the case worth refusing.",
            ),
        )
        assertEquals(listOf("startFullScan", "fullScan"), port.calls)
    }

    @Test
    fun `the same wallet object is not mistaken for a replacement`() = runTest {
        // The other half of the control: a check that always fires is as useless
        // as one that never does.
        val port = FakeSyncPort()
        val outcome = sync(port, ScanCoordinator(this)).runFullScan()
        assertTrue("An undisturbed scan must apply. Got: $outcome", outcome.applied)
    }

    // --- Composition with the scan coordinator -------------------------------

    @Test
    fun `a light sync stands down while a full scan is running`() = runTest {
        val scans = ScanCoordinator(this)
        val port = FakeSyncPort()
        val subject = sync(port, scans)

        val release = CompletableDeferred<Unit>()
        val running = async { scans.fullScan { release.await(); true } }
        testScheduler.runCurrent()

        val outcome = subject.runLightSync()

        assertEquals(
            SyncStep.FullScanInProgress,
            stepOf(
                outcome,
                "Both paths call applyUpdate and persist against the same wallet and " +
                    "connection, and BDK's Wallet is not safe to update from two places at " +
                    "once (BDKManager.swift:285–288).",
            ),
        )
        assertTrue("The light sync must not have touched the wallet", port.calls.isEmpty())

        release.complete(Unit)
        running.await()
    }

    @Test
    fun `a full scan reports through the coordinator`() = runTest {
        val scans = ScanCoordinator(this)
        val port = FakeSyncPort()

        assertTrue(sync(port, scans).fullScan())
        assertTrue("hasBeenScanned gates the send screen", scans.hasBeenScanned)
    }

    @Test
    fun `a full scan that fails does not open the send screen`() = runTest {
        val scans = ScanCoordinator(this)
        val port = FakeSyncPort()
        port.fetchFailure = { java.io.IOException("electrum unreachable") }

        assertFalse(sync(port, scans).fullScan())
        assertFalse(
            "A wallet that could not scan must not present itself as scanned — an " +
                "empty balance would read as 'no funds' rather than 'not yet known'",
            scans.hasBeenScanned,
        )
    }

    @Test
    fun `concurrent full scans produce one scan`() = runTest {
        val scans = ScanCoordinator(this)
        val port = FakeSyncPort()
        val subject = sync(port, scans)

        val release = CompletableDeferred<Unit>()
        port.onFetch = { }
        val callers = (1..3).map { async { subject.fullScan() } }
        testScheduler.runCurrent()
        release.complete(Unit)

        assertTrue(callers.map { it.await() }.all { it })
        assertEquals(
            "Three callers, one trip to Electrum",
            1,
            port.calls.count { it == "fullScan" },
        )
    }

    // --- The stored full scan (PR #99) ---------------------------------------

    @Test
    fun `a full scan that persisted is stored`() = runTest {
        val record = FakeRecord()

        assertTrue(sync(FakeSyncPort(), ScanCoordinator(this), record).fullScan())

        assertTrue(record.fullScanStored)
    }

    /** The stored data lacks this scan, so the next launch must scan again. */
    @Test
    fun `a full scan that did not persist forgets the stored one`() = runTest {
        val record = FakeRecord().apply { fullScanStored = true }
        val port = FakeSyncPort().apply { persistFailure = { IllegalStateException("disk full") } }

        assertTrue("still applied, as before", sync(port, ScanCoordinator(this), record).fullScan())

        assertFalse(record.fullScanStored)
    }

    @Test
    fun `a full scan that failed leaves the stored one as it was`() = runTest {
        val record = FakeRecord()
        val port = FakeSyncPort().apply { fetchFailure = { java.io.IOException("electrum unreachable") } }

        assertFalse(sync(port, ScanCoordinator(this), record).fullScan())

        assertFalse(record.fullScanStored)
    }

    // --- The rebuild, inside the scan ------------------------------------------

    @Test
    fun `a requested rebuild reopens the wallet before the scan`() = runTest {
        val record = FakeRecord().apply { rebuildRequested = true }
        val port = FakeSyncPort()
        val order = mutableListOf<String>()
        val subject = sync(port, ScanCoordinator(this), record) {
            order += "reopen(scans=${port.calls.size})"
            true
        }

        assertTrue(subject.fullScan())

        assertEquals("reopened before any scan step", listOf("reopen(scans=0)"), order)
        assertEquals(1, port.calls.count { it == "fullScan" })
    }

    @Test
    fun `a rebuild that could not reopen the wallet scans nothing`() = runTest {
        val record = FakeRecord().apply { rebuildRequested = true }
        val port = FakeSyncPort()
        val scans = ScanCoordinator(this)

        assertFalse(sync(port, scans, record) { false }.fullScan())

        assertEquals(emptyList<String>(), port.calls)
        assertFalse(scans.hasBeenScanned)
    }

    @Test
    fun `no rebuild is run unless one is requested`() = runTest {
        var reopened = false

        assertTrue(sync(FakeSyncPort(), ScanCoordinator(this), FakeRecord()) { reopened = true; true }.fullScan())

        assertFalse(reopened)
    }

    /** A running light sync still writes to the stored database, so the rebuild waits for it. */
    @Test
    fun `a rebuild waits for a running light sync to end`() = runTest {
        val scans = ScanCoordinator(this)
        val record = FakeRecord().apply { rebuildRequested = true }
        var reopened = false
        val claim = scans.claimLightSync()!!

        val scan = async { sync(FakeSyncPort(), scans, record) { reopened = true; true }.fullScan() }
        advanceTimeBy(OnchainSync.REBUILD_WAIT_MILLIS * 4)
        runCurrent()
        assertFalse("not while the light sync holds its claim", reopened)

        scans.endLightSync(claim)
        advanceTimeBy(OnchainSync.REBUILD_WAIT_MILLIS)
        runCurrent()

        assertTrue(scan.await())
        assertTrue(reopened)
        assertTrue("the rebuild releases the claim it took", scans.claimLightSync() != null)
    }

    @Test
    fun `a rebuild gives up after thirty seconds of a running light sync`() = runTest {
        val scans = ScanCoordinator(this, timeoutMillis = 60_000L)
        val record = FakeRecord().apply { rebuildRequested = true }
        var reopened = false
        scans.claimLightSync()!!

        val scan = async { sync(FakeSyncPort(), scans, record) { reopened = true; true }.fullScan() }
        advanceTimeBy(OnchainSync.REBUILD_WAIT_MILLIS * OnchainSync.REBUILD_WAIT_ATTEMPTS + 1)
        runCurrent()

        assertFalse(scan.await())
        assertFalse(reopened)
        assertTrue("the request stays, so the next start rebuilds", record.rebuildRequested)
    }

    // --- Light-sync outcomes -------------------------------------------------

    @Test
    fun `a light sync reports synced`() = runTest {
        assertEquals(LightSyncOutcome.Synced, sync(FakeSyncPort(), ScanCoordinator(this)).lightSync())
    }

    @Test
    fun `a light sync that failed is told apart from a skipped one`() = runTest {
        val port = FakeSyncPort().apply { fetchFailure = { java.io.IOException("electrum unreachable") } }

        assertEquals(LightSyncOutcome.Failed, sync(port, ScanCoordinator(this)).lightSync())
    }

    @Test
    fun `a light sync stands down while a full scan runs`() = runTest {
        val scans = ScanCoordinator(this)
        val gate = CompletableDeferred<Unit>()
        val scan = async { scans.fullScan { gate.await(); true } }
        runCurrent()

        val port = FakeSyncPort()
        assertEquals(LightSyncOutcome.SkippedForFullScan, sync(port, scans).lightSync())
        assertEquals(emptyList<String>(), port.calls)

        gate.complete(Unit)
        scan.await()
    }

    @Test
    fun `one light sync at a time`() = runTest {
        val scans = ScanCoordinator(this)
        val claim = scans.claimLightSync()!!
        val port = FakeSyncPort()

        assertEquals(LightSyncOutcome.SkippedForLightSync, sync(port, scans).lightSync())
        assertEquals(emptyList<String>(), port.calls)

        scans.endLightSync(claim)
        assertEquals(LightSyncOutcome.Synced, sync(port, scans).lightSync())
    }

    @Test
    fun `a light sync releases its claim when it ends, applied or not`() = runTest {
        val scans = ScanCoordinator(this)
        val port = FakeSyncPort().apply { fetchFailure = { java.io.IOException("electrum unreachable") } }

        sync(port, scans).lightSync()

        assertTrue(scans.claimLightSync() != null)
    }

    /** A hung light sync may have left the Electrum connection stuck, so the next opens a new one. */
    @Test
    fun `a light sync that takes over a hung one reconnects to Electrum first`() = runTest {
        var now = 0L
        val scans = ScanCoordinator(this, nowMillis = { now })
        scans.claimLightSync()!!
        now += ScanCoordinator.LIGHT_SYNC_CLAIM_LIMIT_MILLIS
        val port = FakeSyncPort()

        assertEquals(LightSyncOutcome.Synced, sync(port, scans).lightSync())

        assertEquals("reconnectElectrum", port.calls.first())
    }

    @Test
    fun `a failed reconnect fails the light sync`() = runTest {
        var now = 0L
        val scans = ScanCoordinator(this, nowMillis = { now })
        scans.claimLightSync()!!
        now += ScanCoordinator.LIGHT_SYNC_CLAIM_LIMIT_MILLIS
        val port = FakeSyncPort().apply { reconnectFailure = { java.io.IOException("unreachable") } }

        assertEquals(LightSyncOutcome.Failed, sync(port, scans).lightSync())
        assertEquals(listOf("reconnectElectrum"), port.calls)
    }

    // --- A scan that outlives a teardown -------------------------------------

    /**
     * A rebuild waiting for a light sync's claim when the wallet is torn down must not reopen
     * it afterwards: after a removal, that would open the removed seed's wallet.
     */
    @Test
    fun `a rebuild whose wallet was torn down while it waited does not reopen it`() = runTest {
        val scans = ScanCoordinator(this)
        val record = FakeRecord().apply { rebuildRequested = true }
        var reopened = false
        val claim = scans.claimLightSync()!!

        val scan = async { sync(FakeSyncPort(), scans, record) { reopened = true; true }.fullScan() }
        runCurrent()
        scans.clear()
        scans.endLightSync(claim)
        advanceTimeBy(OnchainSync.REBUILD_WAIT_MILLIS)
        runCurrent()

        assertFalse(scan.await())
        assertFalse(reopened)
        assertFalse(scans.hasBeenScanned)
    }

    // --- Errors reported with iOS's rows -------------------------------------

    @Test
    fun `failures are reported with iOS's rows`() = runTest {
        val rows = mutableListOf<Int>()
        fun reporting(port: FakeSyncPort, scans: ScanCoordinator) =
            OnchainSync(port, scans, closures = null, record = null, reopenWallet = null, onError = { _, row -> rows += row })

        reporting(FakeSyncPort().apply { fetchFailure = { java.io.IOException("down") } }, ScanCoordinator(this)).fullScan()
        reporting(FakeSyncPort().apply { persistFailure = { IllegalStateException("disk") } }, ScanCoordinator(this)).fullScan()
        reporting(FakeSyncPort().apply { buildFailure = { IllegalStateException("build") } }, ScanCoordinator(this)).lightSync()
        reporting(FakeSyncPort().apply { applyFailure = { IllegalStateException("apply") } }, ScanCoordinator(this)).lightSync()

        assertEquals(
            listOf(
                OnchainSync.ROW_FULL_SCAN_FETCH,
                OnchainSync.ROW_FULL_SCAN_PERSIST,
                OnchainSync.ROW_LIGHT_SYNC_BUILD,
                OnchainSync.ROW_LIGHT_SYNC_APPLY,
            ),
            rows,
        )
    }

    @Test
    fun `a failed reconnect is reported`() = runTest {
        var now = 0L
        val scans = ScanCoordinator(this, nowMillis = { now })
        scans.claimLightSync()!!
        now += ScanCoordinator.LIGHT_SYNC_CLAIM_LIMIT_MILLIS
        val rows = mutableListOf<Int>()
        val port = FakeSyncPort().apply { reconnectFailure = { java.io.IOException("unreachable") } }

        OnchainSync(port, scans, closures = null, record = null, reopenWallet = null, onError = { _, row -> rows += row }).lightSync()

        assertEquals(listOf(OnchainSync.ROW_RECONNECT), rows)
    }
}
