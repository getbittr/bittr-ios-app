package com.bittr.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.di.WalletGraph
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import dagger.hilt.android.EntryPointAccessors
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K2's delivery leg: the device half of it — BIT-135.**
 *
 * `FcmWakeTest` proves everything about the wake that this repository can get
 * wrong without Google: the `<service>` block out-ranks the library's fallback,
 * the graph hands out the app's own `BackgroundWake`, a keyed payload reaches
 * `WalletService.start()` and an unkeyed one does not. All of it drives
 * `BittrMessagingService.deliver` directly, which is the seam one call inside
 * Google's dispatch.
 *
 * **This class exists to remove that one call**, and it cannot do so alone. The
 * only thing that makes a real `onMessageReceived` happen is a real message from
 * Google, sent from a host that this device cannot itself be. So the claim is
 * split across three places, exactly as BIT-108 split the backup verdict:
 *
 * | who | what it does |
 * |---|---|
 * | this class | leaves the device in the state a wake needs: Play services present, this APK registered against `bittr-regtest`, a wallet on disk, and a registration token handed off |
 * | `ci-fcm-delivery.sh` | kills the process, sends through `send-fcm-wake.sh`, and reads logcat for what the app did when it came back |
 * | `check-fcm-delivery-results.py` | refuses a run in which the three methods below did not all execute |
 *
 * **None of the three is evidence alone**, and the middle one is where the claim
 * actually lands. A green here means the preconditions were created; grep the run
 * for `FCM delivery` to see whether a message then arrived.
 *
 * ## Why the token, and not a topic
 *
 * `wallet-node-device-tests.md` §1 left this open with two routes. The token is
 * chosen, and the reason the trade looked closer than it is:
 *
 * - The stated cost of the token route was *"a debug-only path in the app that
 *   surrenders it"*. **There is no such path and none is added.** Instrumented
 *   tests run inside the target application's process, so
 *   `FirebaseMessaging.getInstance()` below is the *app's* instance, initialised
 *   from the app's own `google-services.json`, and the token it mints is the app's
 *   own. Everything that surrenders it lives in `androidTest/`, which is compiled
 *   into the test APK and is not in any shipped artefact. `BittrMessagingService`
 *   is untouched and still logs the token's length and never its value.
 * - The decisive cost is on the other side. A `/topics/<name>` send returns HTTP
 *   200 with a message name **whether or not anything is subscribed** — so the one
 *   failure this job exists to tell apart, "Google did not deliver" versus "the
 *   wake did not fire", would be indistinguishable from the host. A `token` send
 *   returns `UNREGISTERED` or `INVALID_ARGUMENT` per message. Topic subscriptions
 *   also propagate asynchronously, which adds a third indistinguishable cause.
 *
 * So the route with no production code is also the route with the diagnosable
 * failure, and it is the one production uses.
 *
 * ## The wallet is planted and deliberately **not** removed
 *
 * `FcmWakeTest` removes its wallet in `@After` because `BackupExclusionTest` runs
 * in the same APK and would back up a seed it did not plant. Here the opposite is
 * required: `BackgroundWake` refuses a device with no wallet
 * (`WakeOutcome.NoWallet`), and the wake under test happens *after* Gradle has
 * exited. A wallet removed in `@After` would make the delivery leg fail for want
 * of a wallet — the same green as "no message arrived", which is the one
 * distinction this job is for.
 *
 * `ci-fcm-delivery.sh` clears the app's data at the end of its run. The two jobs
 * never share a device: this one boots `google_apis`, which has no local backup
 * transport at all, so no backup set can be produced here for anything to leak
 * into.
 */
@RunWith(AndroidJUnit4::class)
@RequiresPlayServices
class FcmDeliveryTest {

    private companion object {
        const val PLAY_SERVICES = "com.google.android.gms"

        /** The project BIT-39 provisioned for exactly this, and never `bittr-prod`. */
        const val REGTEST_PROJECT = "bittr-regtest"

        /** The debug build's applicationId — `applicationId` + `applicationIdSuffix`. */
        const val REGTEST_APP_ID = "com.bittr.android.regtest"

        /** Any valid PIN. Completes setup; never a secret. */
        const val PIN = "1357"

        /**
         * How long to wait for Play services to mint a token.
         *
         * Generous on purpose. On a cold `google_apis` emulator this is the first
         * thing that talks to Google at all, and it is a network round trip
         * through a GMS that has just booted. A short timeout here would fail the
         * job as "no token" when the truthful reading is "not yet".
         */
        const val TOKEN_TIMEOUT_SECONDS = 120L

        /**
         * Where the host picks the token up.
         *
         * Under `no_backup` and named alongside `backup_handoff.txt` for the same
         * reason BIT-108 put that one there: it is a hand-off between a test and
         * the host phase that follows it, and nothing about it should ever reach a
         * backup set. `ci-fcm-delivery.sh` reads it with `run-as`, masks it into
         * the run's log with `::add-mask::` before doing anything else with it,
         * and deletes it at the end.
         */
        const val HANDOFF_FILE = "fcm_delivery_handoff.txt"

        /** What the host greps for, so a truncated or half-written file is legible. */
        const val HANDOFF_MARKER = "FCM_DELIVERY_HANDOFF ready"
    }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private val graph: WalletGraph
        get() = EntryPointAccessors.fromApplication(context, WalletGraph::class.java)

    @Test
    fun playServicesAreOnThisImage() {
        // ASSERTED here, RECORDED in FcmWakeTest. The difference is which job is
        // asking. There, "absent" is the expected reading and a claim about the
        // `default` image; here, "absent" means this job booted the wrong image
        // and every other result it produces is vacuous — no Play services means
        // no token can be minted, no message can be delivered, and the send below
        // would fail against a device that was never addressable.
        //
        // It is also the guard that makes the annotation filter safe. If
        // `notAnnotation` is ever dropped from ci-wallet-instrumented.sh, this
        // class runs on AOSP and fails HERE, naming the image, rather than
        // somewhere downstream that reads like an FCM problem.
        val version = runCatching {
            context.packageManager.getPackageInfo(PLAY_SERVICES, 0).versionName
        }.getOrNull()

        println("FCM_DELIVERY_IMAGE playServices=${version ?: "absent"}")

        assertTrue(
            "$PLAY_SERVICES is not installed on this device, so no FCM registration " +
                "token can be minted and no message can be delivered to it. This job must " +
                "boot a `google_apis` image; `default` and `aosp_atd` are AOSP and carry no " +
                "Play services. If you are seeing this in the `wallet-instrumented` job " +
                "instead, that job lost its " +
                "`-Pandroid.testInstrumentationRunnerArguments.notAnnotation=" +
                "com.bittr.android.RequiresPlayServices` argument — this class is not " +
                "meant to run there, and that job's image cannot be changed because " +
                "BackupExclusionTest needs com.android.localtransport.",
            version != null,
        )
    }

    @Test
    fun thisApkSendsAndReceivesThroughTheRegtestProject() {
        // BIT-123's standing note, asserted on the device rather than trusted.
        //
        // GoogleServicesConfigTest already pins each committed google-services.json
        // to its build type on the JVM. This is the other end of the same claim:
        // what FirebaseApp actually initialised with in the APK that is installed,
        // after the google-services plugin processed the file and aapt packaged
        // the resources. A build that somehow resolved the production project
        // would be addressable by the production sender, which is the single
        // outcome the two-project split exists to prevent — and the host phase is
        // about to point a real credential at this device.
        //
        // The applicationId is asserted alongside it because that is the key
        // Firebase resolves the client config BY. Agreeing on the project while
        // disagreeing on the package would mean the token minted below belongs to
        // a client that is not this one.
        val options = FirebaseApp.getInstance().options

        assertEquals(
            "This APK initialised FirebaseApp against project '${options.projectId}', not " +
                "$REGTEST_PROJECT. Sending to it needs a credential for that project, and " +
                "the only other Bittr project is bittr-prod — whose sender addresses real " +
                "user devices. BIT-123's standing note forbids that path outright. Check " +
                "app/src/debug/google-services.json and the google-services plugin.",
            REGTEST_PROJECT,
            options.projectId,
        )
        assertEquals(
            "The installed package is ${context.packageName}, not $REGTEST_APP_ID. Firebase " +
                "resolves client config by package name, so this build is not the client " +
                "app/src/debug/google-services.json describes. Check applicationId and the " +
                "debug applicationIdSuffix in app/build.gradle.kts.",
            REGTEST_APP_ID,
            context.packageName,
        )
    }

    @Test
    fun aWalletAndARegistrationTokenAreLeftForTheHostToWake() {
        // Everything the host phase needs, created in one method so that a partial
        // state is impossible: a wallet with no token is a device nothing can
        // address, and a token with no wallet is a device that answers
        // WakeOutcome.NoWallet — and NoWallet and "no message arrived" are the
        // same silence from the host's side.
        val wallet = graph.walletService()
        kotlinx.coroutines.runBlocking {
            // Blocking the instrumentation thread is correct here for the reason
            // FcmWakeTest gives: the calls being awaited are the ones the app
            // itself awaits.
            wallet.createWallet()
            wallet.setPin(PIN)
        }
        assertNotEquals(
            "The planted wallet did not leave WalletState.Uninitialized, so BackgroundWake " +
                "would answer NoWallet to the message the host is about to send and the run " +
                "would look exactly like an undelivered one.",
            WalletState.Uninitialized,
            wallet.state.value,
        )

        // The APP's token, not a second Firebase client's: instrumented tests run
        // in the target application's process, so this is the same
        // FirebaseMessaging singleton BittrMessagingService would see.
        val token = Tasks.await(
            FirebaseMessaging.getInstance().token,
            TOKEN_TIMEOUT_SECONDS,
            TimeUnit.SECONDS,
        )

        assertTrue(
            "Play services returned an empty registration token. Nothing can be addressed " +
                "to this install, so the send below would be aimed at nothing. On a cold " +
                "emulator this is usually GMS not yet having reached Google; if it recurs, " +
                "check that the emulator has network and that $REGTEST_PROJECT has Cloud " +
                "Messaging enabled.",
            token.isNotBlank(),
        )

        // The token is NOT printed, here or anywhere. It is a per-install device
        // identifier and shared/docs/privacy-disclosure.md lists it as one; a
        // println lands in <system-out>, in the HTML report and in the job log.
        // Its LENGTH is printed, which is what BittrMessagingService.onNewToken
        // does and is enough to tell "a token arrived" from "a blank one did".
        println("FCM_DELIVERY_TOKEN handed off (${token.length} chars); value not logged.")

        val handoff = File(context.noBackupFilesDir, HANDOFF_FILE)
        // Two lines, marker first: the host greps the marker before reading the
        // token, so a file that was half-written — the instrumentation dying
        // mid-test — reads as "no hand-off" rather than as a truncated token
        // aimed at nothing.
        handoff.writeText("$HANDOFF_MARKER\n$token\n")

        assertTrue(
            "Could not write the hand-off at ${handoff.absolutePath}. Without it the host " +
                "phase has no address to send to and will report that it did not look, " +
                "rather than reporting a delivery failure.",
            handoff.isFile && handoff.length() > HANDOFF_MARKER.length,
        )
    }
}
