package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
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
    }

    private fun sync(port: FakeSyncPort, scans: ScanCoordinator) = OnchainSync(port, scans)

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
}
