package com.bittr.android

import android.app.ActivityManager
import android.app.NotificationManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.host.WalletForegroundService
import com.bittr.android.di.LdkEnvironmentConfig
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K8, the machinery half — the node and its foreground service survive a
 * forced deep-idle window.**
 *
 * `wallet-core-spec` §6, carried on BIT-132, designed in
 * `android/docs/wallet-node-device-tests.md` §4. K8 is **two** tests because its
 * two halves need different set-ups, and that split was settled before either
 * was written rather than after:
 *
 * - *This class* needs a running node and **no channel**, so it lives in the
 *   undirected suite `ci-wallet-regtest.sh` runs, beside
 *   [RegtestEnvironmentTest].
 * - [K8ChannelFreshnessTest] needs a funded, open channel, which on this network
 *   exists only after K7's phase 2 — so it is `@HostDriven` and runs after K7,
 *   over the channel K7 left.
 *
 * ## What this class claims, stated narrowly on purpose
 *
 * > With a node running and its foreground service up, a **forced** deep-idle
 * > window does not take the node, the service, or the notification with it.
 *
 * Three narrowings are in that sentence and each one is real:
 *
 * 1. **Forced.** `dumpsys deviceidle force-idle` bypasses the screen-off and
 *    unplugged preconditions the platform waits on by itself. Deep idle is the
 *    same state either way, but arriving at it on demand is not evidence about
 *    how a device gets there. See [Doze].
 * 2. **A window, not a night.** The default is [IDLE_WINDOW_MS], because the
 *    nightly job has 90 minutes and K7 spends five `connectedDebugAndroidTest`
 *    invocations of it. A longer soak is one instrumentation argument away
 *    (`k8IdleWindowMs`) and is what a human dispatching this by hand should use.
 * 3. **App Standby is recorded, not asserted.** The bucket is requested and read
 *    back into the evidence line. [Doze.setStandbyBucket] carries the argument:
 *    an app with a live foreground service is one the platform re-derives as
 *    `ACTIVE`, so a read-back of `10` is the mitigation under test *working*,
 *    and a red saying "the wallet was protected" is the most misleading verdict
 *    this suite could produce.
 *
 * ## What it does not claim
 *
 * That channel monitors stay fresh. There is no channel here — that is
 * [K8ChannelFreshnessTest]'s half, and it is narrowed further still, because
 * `ChannelView` carries no monitor update id and ldk-node offers none.
 *
 * And it says nothing about the API 35 `dataSync` six-hour cap
 * ([WalletForegroundService]'s own comment names it). A window measured in
 * minutes cannot reach it. What happens to a wallet left open all day is
 * undecided and still undecided after this test is green.
 *
 * Every method here is in `check-wallet-regtest-results.py`'s `REQUIRED` set by
 * name, per BIT-132's definition of done.
 */
@RunWith(AndroidJUnit4::class)
class K8DozeMachineryTest {

    /**
     * The same vacuity guard K7 restates per phase, and it matters more here.
     *
     * An unconfigured build composes `SeedWalletService`: no `WalletNodeHost`,
     * no `WalletForegroundService`, no ldk-node. Every assertion below would
     * then be about an app with nothing to protect — and the *service* ones
     * would fail with "no foreground service is running", which reads as a
     * platform finding and is really "there was never a node".
     */
    @Before
    fun thisBuildHasANodeInIt() {
        assertEquals(
            "This APK was built without a complete LdkEnvironment, so it composes " +
                "SeedWalletService: no WalletNodeHost, no WalletForegroundService and " +
                "no ldk-node. There is nothing here for Doze to freeze, so K8 is not a " +
                "claim about this build. Run android/regtest/up.sh and supply the " +
                "values android/scripts/regtest-ldk-env.py prints.",
            emptyList<String>(),
            LdkEnvironmentConfig.missingFields(),
        )
    }

    /**
     * Leave the emulator as it was found, whatever happened above.
     *
     * A device left in forced idle with its battery unplugged is a device every
     * later test in this boot runs against — and the symptom, a suite that
     * starts failing from wherever K8 sits in the run order, names K8 last of
     * anything. `@After` rather than only a `finally`, so an assertion that
     * throws from inside the window is also covered.
     */
    @After
    fun leaveTheDeviceAwake() {
        Doze.leaveForcedIdle()
    }

    /**
     * **The negative control, and it runs first because it is cheap.**
     *
     * Without this, a green [theNodeAndItsForegroundServiceSurviveAForcedIdleWindow]
     * could be a device that was never in Doze at all — the exact vacuous pass
     * `RegtestEnvironmentTest` exists to refuse one level up. `force-idle` fails
     * in two ways that both look like success from a distance: the controller
     * refuses with *"Unable to go deep idle; not enabled"* when deep idle is
     * off, and an image stripped of the idle machinery answers nothing useful at
     * all.
     *
     * A red here is an **infrastructure verdict about the emulator image**, not
     * a finding about the wallet, and the assertion says so — the two call for
     * opposite investigations, and a nightly job at 03:20 UTC should not make a
     * reader guess which one they have. `wallet-regtest-nightly.yml` runs the
     * `default` image rather than `aosp_atd` for precisely this reason, which is
     * already written down in that workflow.
     */
    @Test
    fun theDeviceCanBeForcedIntoDeepIdleAtAll() {
        val reading = Doze.enterForcedIdle()
        Doze.announce(
            "forcedIdleProbe $reading bucket=${Doze.standbyBucket()} " +
                "package=${Doze.packageUnderTest}",
        )
        assertTrue(
            "This emulator did not reach deep idle on demand: $reading. That is a " +
                "verdict about the IMAGE, not about the wallet — the Doze machinery " +
                "`dumpsys deviceidle` drives is one of the components ATD images are " +
                "stripped of, and wallet-regtest-nightly.yml runs `default` for that " +
                "reason. Nothing else in K8 measures anything until this is green, so " +
                "read this red before reading any other.",
            reading.isDeepIdle,
        )
        // Asserted as "not idle" rather than as `ACTIVE`, and the difference is
        // deliberate. `unforce` returns the controller to whatever the real
        // inputs say, and on a `-no-window` emulator whose screen the framework
        // may consider off that is legitimately `INACTIVE` — a state on the way
        // to idle rather than in it. What this test needs to know is that the
        // FORCED state was released; pinning the exact resting state would fail
        // for a display setting rather than for the thing being checked.
        Doze.leaveForcedIdle()
        val released = Doze.deepIdleState()
        assertTrue(
            "The device is still reporting $released after `dumpsys deviceidle " +
                "unforce`. Every test that runs after K8 on this boot is now running " +
                "on a dozing device, and the first one to fail will not look like it " +
                "was K8's doing.",
            released != Doze.DEEP_IDLE,
        )
    }

    /**
     * **The claim.** A node that was running before the window is running after it.
     *
     * Four observations, because "the node survived" has four ways to be false
     * and they are not the same failure:
     *
     * 1. **The foreground service is still registered.** This is the mitigation
     *    itself. `WalletForegroundService` exists only so the process holding
     *    the node is not a cached process the system may freeze or kill, and a
     *    window that ends with the service gone has removed the protection while
     *    the wallet still believes it has it.
     * 2. **Its notification is still posted.** A separate reading, not a second
     *    look at the same one: on API 34+ a foreground service whose
     *    notification has gone is a service the user can no longer see is
     *    running, which is the state Play reviews reject and the user cannot
     *    explain.
     * 3. **The wallet is still `Ready`.** Nothing calls `start()` after the
     *    window — deliberately. A test that restarted the node and then found a
     *    node would be measuring `WalletService.start`, which
     *    `WalletNodeHostTest` already covers on the JVM against a fake.
     * 4. **The node still answers.** `listBalances()` returning null is
     *    `LightningNodePort`'s contract for *there is no node*, and it is the
     *    only reading here that distinguishes a live node from a
     *    `NodeLifecycle` holding a dead one.
     *
     * The baseline for all four is taken **before** the window, so a build where
     * the service never started reads as "it was never there" rather than as
     * "Doze took it".
     */
    @Test
    fun theNodeAndItsForegroundServiceSurviveAForcedIdleWindow() {
        val graph = RegtestWallet.graph()
        val wallet = graph.walletService()
        RegtestWallet.start(wallet, mayCreate = true)
        val node = graph.lightningNode()

        assertTrue(
            "No ${SERVICE_NAME.substringAfterLast('.')} was running BEFORE the idle " +
                "window, so there is no protection here for Doze to take away. " +
                "Running services: ${runningServices()}. WalletNodeHost promotes the " +
                "process before a node start begins; if the wallet is Ready and this " +
                "is empty, the promotion was refused — ServiceForegroundPresence " +
                "swallows that by design, and this is where it becomes visible.",
            foregroundServiceIsRunning(),
        )
        assertTrue(
            "The foreground service is running and its notification " +
                "(id ${WalletForegroundService.NOTIFICATION_ID}) was not posted BEFORE " +
                "the window. Active notification ids: ${activeNotificationIds()}.",
            serviceNotificationIsPosted(),
        )
        val balanceBefore = node.listBalances()
        assertNotNull(
            "listBalances() was already null before the idle window, which is " +
                "LightningNodePort's contract for 'there is no node'. The wallet " +
                "reported Ready, so this is a node that died between start() and " +
                "here — not a K8 result.",
            balanceBefore,
        )

        val windowMs = argumentMs(ARG_IDLE_WINDOW_MS) ?: IDLE_WINDOW_MS
        val entered = Doze.enterForcedIdle()
        val bucketAfterRequest = Doze.setStandbyBucket(REQUESTED_BUCKET)
        Doze.announce(
            "windowOpen half=machinery $entered requestedBucket=$REQUESTED_BUCKET " +
                "bucket=$bucketAfterRequest windowMs=$windowMs " +
                "onchainSatsBefore=${balanceBefore?.totalOnchainBalanceSats}",
        )
        assertTrue(
            "The device did not reach deep idle for this window: $entered. " +
                "theDeviceCanBeForcedIntoDeepIdleAtAll says what that means and it " +
                "is a verdict about the image rather than about the node. Refusing to " +
                "report a survival that was never tested.",
            entered.isDeepIdle,
        )

        val observed = Doze.holdWindow(windowMs, "machinery")
        Doze.leaveForcedIdle()

        // Asserted over the WHOLE window rather than at its ends. A device that
        // dropped back to ACTIVE thirty seconds in spent most of the window
        // awake, and the two dumpsys calls either side would both say IDLE.
        assertEquals(
            "The device left deep idle during the window: $observed. The node was " +
                "then not under the condition this test claims to measure for most " +
                "of it. Something woke the device — an `am` command from another " +
                "suite sharing this boot is the usual cause.",
            listOf(Doze.DEEP_IDLE),
            observed.distinct(),
        )

        assertTrue(
            "The foreground service is GONE after a ${windowMs / 1000}s forced " +
                "deep-idle window. Running services: ${runningServices()}. This is " +
                "the mitigation failing: WalletForegroundService is the only thing " +
                "keeping the process holding a Lightning node out of the cached, " +
                "freezable state, and a channel monitor that is not watched is how a " +
                "counterparty's stale commitment goes unchallenged. See " +
                "wallet-node-device-tests.md §4 on why the cost is fees and " +
                "liquidity rather than principal.",
            foregroundServiceIsRunning(),
        )
        assertTrue(
            "The service survived the window and its notification did not " +
                "(id ${WalletForegroundService.NOTIFICATION_ID}; still posted: " +
                "${activeNotificationIds()}). A foreground service the user cannot " +
                "see is running is not the thing this app declared.",
            serviceNotificationIsPosted(),
        )
        assertEquals(
            "The wallet is ${wallet.state.value} after the idle window. Nothing here " +
                "called start() again on purpose — a test that restarted the node and " +
                "then found a node would be measuring WalletService.start, which " +
                "WalletNodeHostTest already proves on the JVM.",
            WalletState.Ready,
            wallet.state.value,
        )
        val balanceAfter = node.listBalances()
        assertNotNull(
            "listBalances() is null after the idle window and was not before it. " +
                "That is LightningNodePort's contract for 'there is no node': the " +
                "wallet still reports Ready while NodeLifecycle holds nothing, which " +
                "is the shape a frozen-then-collected node leaves behind.",
            balanceAfter,
        )

        Doze.announce(
            "machineryResult windowMs=$windowMs states=${observed.distinct()} " +
                "bucketRequested=$REQUESTED_BUCKET bucketObserved=$bucketAfterRequest " +
                "serviceRunning=${foregroundServiceIsRunning()} " +
                "notificationPosted=${serviceNotificationIsPosted()} " +
                "walletState=${wallet.state.value} " +
                "onchainSatsAfter=${balanceAfter?.totalOnchainBalanceSats} " +
                "claim=forced-idle-window-not-elapsed-wall-clock",
        )
    }

    /**
     * The reading, printed rather than asserted.
     *
     * Required by name for the reason
     * `RegtestEnvironmentTest#recordTheEnvironmentThisRunSaw` is: a future reader
     * deciding whether a green K8 row is worth anything needs to know *which*
     * machinery this run had. The API level and the two idle-state readings are
     * what separate "the node survived Doze" from "this image has no Doze", and
     * the bucket reading is the narrowing this class makes rather than hides — a
     * run where the platform held the app at `ACTIVE` throughout measured
     * something weaker than one where it did not, and only this line says which
     * happened.
     */
    @Test
    fun recordTheIdleMachineryThisRunSaw() {
        Doze.announce(
            "machinery sdk=${android.os.Build.VERSION.SDK_INT} " +
                "fingerprint=${android.os.Build.FINGERPRINT} " +
                "package=${Doze.packageUnderTest} " +
                "deep=${Doze.deepIdleState()} light=${Doze.lightIdleState()} " +
                "bucket=${Doze.standbyBucket()} " +
                "defaultWindowMs=$IDLE_WINDOW_MS " +
                "service=$SERVICE_NAME running=${foregroundServiceIsRunning()}",
        )
    }

    // ---- The two platform readings. --------------------------------------------

    /**
     * Whether `WalletForegroundService` is registered as running.
     *
     * `getRunningServices` is unavailable to third-party apps from API 26 — with
     * one exception, and it is the exception this uses: it still returns the
     * **caller's own** services. An instrumented test runs inside the
     * application's own process, so the app's services are exactly what it can
     * see. (That property is this repository's already: it is why
     * `androidTest` can reach the app's own FirebaseApp.)
     */
    private fun foregroundServiceIsRunning(): Boolean = runningServices().any { it == SERVICE_NAME }

    @Suppress("DEPRECATION")
    private fun runningServices(): List<String> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val activityManager = context.getSystemService(ActivityManager::class.java)
        return activityManager?.getRunningServices(Int.MAX_VALUE)
            ?.map { it.service.className }
            .orEmpty()
    }

    /**
     * Whether the service's ongoing notification is still on screen.
     *
     * `getActiveNotifications` needs no listener permission for an app's *own*
     * notifications, which is all this asks about. Read separately from the
     * service record because the two can disagree: on API 34+ the platform can
     * take the notification while leaving the service, and that state — a
     * foreground service with nothing visible — is the one
     * `WalletForegroundService` sets `setOngoing(true)` to avoid.
     */
    private fun serviceNotificationIsPosted(): Boolean =
        activeNotificationIds().contains(WalletForegroundService.NOTIFICATION_ID)

    private fun activeNotificationIds(): List<Int> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager?.activeNotifications?.map { it.id }.orEmpty()
    }

    private fun argumentMs(name: String): Long? =
        InstrumentationRegistry.getArguments().getString(name)?.toLongOrNull()

    private companion object {

        /** Fully qualified, because that is what `getRunningServices` reports. */
        val SERVICE_NAME: String = WalletForegroundService::class.java.name

        /**
         * How long the forced window is held, by default.
         *
         * Two minutes, and the number is a budget decision rather than a
         * platform one. The nightly job has 90 minutes; K7 spends five
         * `connectedDebugAndroidTest` invocations of it, each waiting on a chain
         * sync or a channel. What two minutes buys is a node that has been
         * through the deep-idle transition and sat in it across several of
         * ldk-node's own 30-second sync intervals — enough for the intervals to
         * have been due and missed.
         *
         * It is **not** enough to say anything about the API 35 `dataSync`
         * six-hour cap, and no arithmetic on this constant will make it so.
         */
        const val IDLE_WINDOW_MS = 120_000L

        /** `-Pandroid.testInstrumentationRunnerArguments.k8IdleWindowMs=…` for a hand-dispatched soak. */
        const val ARG_IDLE_WINDOW_MS = "k8IdleWindowMs"

        /**
         * The bucket this test asks for. Requested and recorded, never asserted —
         * [Doze.setStandbyBucket] carries the argument.
         */
        const val REQUESTED_BUCKET = "rare"
    }
}
