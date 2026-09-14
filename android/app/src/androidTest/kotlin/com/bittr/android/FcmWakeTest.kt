package com.bittr.android

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.host.BackgroundWake
import com.bittr.android.core.wallet.ldk.host.WakeOutcome
import com.bittr.android.di.WalletGraph
import com.bittr.android.messaging.BittrMessagingService
import dagger.hilt.android.EntryPointAccessors
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K2's wake leg: the background wake exists, on the installed app.**
 *
 * BIT-133. Until this branch there was no `FirebaseMessagingService` and no
 * `firebase-messaging` dependency, so `wallet-core-spec` §6's *"deliver an FCM
 * data message, assert node start reaches `Node.start()`"* had nothing to be
 * true or false about. `android/docs/wallet-node-device-tests.md` §1 recorded
 * that; this class is what replaced it.
 *
 * ## What this proves, and what it deliberately does not
 *
 * It proves the half that is **this repository's to get wrong**: the service
 * reaches the merged manifest and out-ranks the library's fallback, the Hilt
 * graph really hands the app's own `BackgroundWake` to a caller that is not a
 * `@AndroidEntryPoint`, and a data payload carrying the wake key reaches
 * `WalletService.start()` while one that does not is dropped.
 *
 * It does **not** prove that Google delivers the message. That leg needs three
 * things this job has none of, and they are recorded rather than assumed:
 *
 * 1. **A `google_apis` image, in a job of its own.** This suite runs `default`,
 *    an AOSP image, chosen because the backup half needs
 *    `com.android.localtransport`. AOSP images carry no Play services, so no FCM
 *    token can be minted and no message can arrive.
 *    [recordWhetherThisImageCouldEverDeliverAWake] asks the device rather than
 *    asserting it, so the doc's claim is fed by a measurement.
 * 2. **A non-production FCM project's service-account key**, as a repository
 *    secret. BIT-39 provisioned `bittr-regtest` for exactly this; the key is not
 *    in the repository and must never be `bittr-prod`'s.
 * 3. **A sender, and a way to address it.** Both are open — see §1.
 *
 * ## Why the delivery is driven through [BittrMessagingService.deliver]
 *
 * Because the platform will not let a test start a background service on API
 * 26+, and `FirebaseMessagingService`'s dispatch is reached by the framework
 * starting the service. So the boundary is drawn one call in: the framework's
 * half is Google's code plus a manifest entry, and the manifest entry is
 * asserted directly by [theAppsOwnServiceOutranksTheLibraryFallback] — which is
 * the part that can regress here, since a lost `<service>` block resolves to
 * `FirebaseMessagingService` itself and goes quiet rather than red.
 *
 * ## The wallet this plants, and why it is removed again
 *
 * The wake refuses to start a wallet that does not exist, so two of the methods
 * below need one. It is created through [WalletGraph] — the app's own
 * `WalletService`, not a second one assembled here — and removed in `@After`,
 * because `BackupExclusionTest` runs in this same APK and a seed left behind
 * would end up in a backup set it did not plant.
 */
@RunWith(AndroidJUnit4::class)
class FcmWakeTest {

    private companion object {
        const val MESSAGING_EVENT = "com.google.firebase.MESSAGING_EVENT"
        const val OUR_SERVICE = "com.bittr.android.messaging.BittrMessagingService"
        const val LIBRARY_FALLBACK = "com.google.firebase.messaging.FirebaseMessagingService"

        /** Any valid PIN. Completes setup; never a secret. */
        const val PIN = "1357"

        /** How long to wait for the launched start to settle. */
        const val SETTLE_MILLIS = 5_000L
    }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private val graph: WalletGraph
        get() = EntryPointAccessors.fromApplication(context, WalletGraph::class.java)

    @Before
    fun noWalletToBeginWith() = runBlockingOnDevice {
        // Not an assumption: a wallet inherited from another class in this APK
        // would make `a message with no wake key is dropped` pass for the wrong
        // reason — NoWallet and NotAWake are both "nothing started".
        graph.walletService().removeWallet()
    }

    @After
    fun takeTheWalletBackOut() = runBlockingOnDevice {
        graph.walletService().removeWallet()
    }

    @Test
    fun theAppsOwnServiceOutranksTheLibraryFallback() {
        // The one regression that is silent. firebase-messaging's AAR declares
        // its own FirebaseMessagingService for this action at
        // android:priority="-500", so an app that loses its <service> entry
        // still resolves a service — Google's, whose onMessageReceived does
        // nothing. Resolution ORDER is the assertion, and it is why this runs on
        // a device: Robolectric's package manager models filter priority poorly,
        // so FcmWakeWiringTest deliberately does not make this claim.
        val resolved = context.packageManager
            .queryIntentServices(Intent(MESSAGING_EVENT).setPackage(context.packageName), 0)
            .map { it.serviceInfo.name }

        assertTrue(
            "Nothing under ${context.packageName} handles $MESSAGING_EVENT. There is no " +
                "background wake in this APK at all.\nResolved: $resolved",
            resolved.isNotEmpty(),
        )
        assertEquals(
            "$LIBRARY_FALLBACK resolves ahead of $OUR_SERVICE, so a real data message would " +
                "reach firebase-messaging's empty base class and the wake would go quiet " +
                "without a single line in logcat. Check the <service> block in " +
                "app/src/main/AndroidManifest.xml: it must declare the " +
                "$MESSAGING_EVENT action and must not carry a negative android:priority.\n" +
                "Resolution order: $resolved",
            OUR_SERVICE,
            resolved.first(),
        )
    }

    @Test
    fun theWakeIsAggregatedIntoTheInstalledAppsGraph() {
        // The trap WalletGraph's own comment describes, asserted from the other
        // end. An @EntryPoint declared in androidTest compiles and is not
        // aggregated into the app's component, so it throws here rather than at
        // build time; resolving it is the only thing that tells a graph which
        // really carries BackgroundWake from one that merely compiled as if it
        // did.
        val first: BackgroundWake = graph.backgroundWake()
        val second: BackgroundWake = graph.backgroundWake()

        // And it is the singleton, not a fresh one per call. Two BackgroundWakes
        // would be two ForegroundPresences promoting one service, and — the
        // reason this is asserted rather than trusted — the `last` this suite
        // polls would belong to a different object from the one the delivery
        // went through, so `aWakeMessageReachesTheWalletStart` would time out
        // for a reason that has nothing to do with the wake.
        assertEquals(
            "WalletGraph hands out a new BackgroundWake per call. Check " +
                "@Singleton on WalletModule.provideBackgroundWake and on " +
                "provideWalletComposition.",
            System.identityHashCode(first),
            System.identityHashCode(second),
        )
    }

    @Test
    fun aWakeMessageReachesTheWalletStart() = runBlockingOnDevice {
        val wallet = graph.walletService()
        wallet.createWallet()
        wallet.setPin(PIN)
        assertNotEquals(
            "The planted wallet did not leave WalletState.Uninitialized, so the wake below " +
                "would be refused for want of a wallet rather than accepted.",
            WalletState.Uninitialized,
            wallet.state.value,
        )

        val outcome = BittrMessagingService.deliver(
            context,
            mapOf(BackgroundWake.WAKE_KEY to "payment"),
        )

        assertEquals(
            "A data message carrying ${BackgroundWake.WAKE_KEY} did not reach the wallet. " +
                "This is K2's wake leg: it is the whole reason BIT-133 exists.",
            WakeOutcome.Waking("payment"),
            outcome,
        )

        // And the launched start actually ran. In this APK — unconfigured, no
        // LdkEnvironment — that start is SeedWalletService's no-op, so what
        // `Woken` proves is that the wake reached the seam UnlockViewModel uses
        // and not that a node came up. A configured build binds the same seam to
        // WalletNodeHost.start(); RegtestEnvironmentTest is what tells the two
        // builds apart, and it runs in a different job.
        val settled = awaitOutcome { it is WakeOutcome.Woken }
        assertEquals(
            "The wake was launched and never completed within ${SETTLE_MILLIS}ms. Last seen: " +
                "$settled",
            WakeOutcome.Woken("payment"),
            settled,
        )
    }

    @Test
    fun aMessageWithoutTheWakeKeyIsDropped() = runBlockingOnDevice {
        // The negative control, and required by name for the same reason
        // SeedReadableWhileLockedTest's lock-state recorder is: "the wake ran"
        // and "every push starts a node" are the same green from the outside.
        // The FCM project this app registers in also carries ordinary payment
        // notifications — see shared/docs/privacy-disclosure.md — and each of
        // those would otherwise put a permanent foreground notification in front
        // of the user.
        val wallet = graph.walletService()
        wallet.createWallet()
        wallet.setPin(PIN)

        val outcome = BittrMessagingService.deliver(
            context,
            mapOf("title" to "Payment received", "body" to "1,000 sats"),
        )

        assertTrue(
            "A push with no ${BackgroundWake.WAKE_KEY} field started the wallet. Every " +
                "user-facing notification this app is sent would now start a Lightning node.\n" +
                "Outcome: $outcome",
            outcome is WakeOutcome.NotAWake,
        )
    }

    @Test
    fun recordWhetherThisImageCouldEverDeliverAWake() {
        // Recorded, not asserted — the same shape as
        // KeystoreKeyInfoTest#recordTheObservedSecurityLevel, and required by
        // name for the same reason: wallet-node-device-tests.md §1 claims this
        // job's image cannot deliver an FCM message, and a claim about a device
        // should be fed by the device rather than by a comment.
        //
        // On the `default` AOSP image this job runs, the expected reading is
        // "absent": no Play services, therefore no delivery, therefore the
        // separate google_apis job §1 asks for. If this ever reads "present",
        // the image has changed under this suite and the doc's argument needs
        // re-deriving — starting with whether com.android.localtransport is
        // still there for the backup half.
        val playServices = runCatching {
            context.packageManager.getPackageInfo("com.google.android.gms", 0).versionName
        }.getOrNull()

        val transport = runCatching {
            context.packageManager.getPackageInfo("com.android.localtransport", 0).versionName
        }.getOrNull()

        println(
            "FCM_WAKE_IMAGE playServices=${playServices ?: "absent"} " +
                "localTransport=${transport ?: "absent"} " +
                "canDeliverFcm=${playServices != null}",
        )
    }

    /**
     * Poll [WalletGraph.backgroundWake]'s last outcome until [predicate] holds.
     *
     * A poll rather than a flow collection because the start runs in the
     * wallet's own process-lifetime scope, on `Dispatchers.IO`, and this test
     * has no way to join it — which is the property under test rather than an
     * inconvenience: a wake that needed its caller to stay alive would not be a
     * background wake.
     */
    private fun awaitOutcome(predicate: (WakeOutcome?) -> Boolean): WakeOutcome? {
        val wake = graph.backgroundWake()
        val deadline = System.nanoTime() + SETTLE_MILLIS * 1_000_000
        while (System.nanoTime() < deadline) {
            val seen = wake.last.value
            if (predicate(seen)) return seen
            Thread.sleep(25)
        }
        return wake.last.value
    }

    /**
     * `runBlocking`, named for what it is doing here.
     *
     * The wallet's API is suspending and this is a plain JUnit4 instrumented
     * test, which has no coroutine runner — the same situation
     * `BackupExclusionTest` is in. Blocking the instrumentation thread is
     * correct: the calls being awaited are the ones the app itself awaits.
     */
    private fun runBlockingOnDevice(block: suspend () -> Unit) =
        kotlinx.coroutines.runBlocking { block() }
}
