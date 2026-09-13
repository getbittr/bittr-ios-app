package com.bittr.android.core.wallet.ldk.host

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.bittr.android.core.wallet.ldk.WalletSourceTree
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The service, and the one call that has to fail quietly.
 *
 * Almost nothing about the foreground service is a decision — the decisions are
 * [WalletNodeHost]'s and are proved against a recorder on the JVM. What is left
 * is four platform facts that a device would answer and a reviewer cannot:
 *
 * - it goes to the foreground *in* `onStartCommand`, inside the five seconds
 *   `startForegroundService` allows before it crashes the app;
 * - it returns `START_NOT_STICKY`, so a killed process does not get a node
 *   started for a wallet still behind a PIN;
 * - a refused promotion does not propagate into the node start;
 * - the manifest still declares it, with a type, and not exported.
 *
 * Pinned at 26 / 34 / 36 — `minSdk`, the level the CI emulator boots, and the
 * newest Robolectric 4.16.1 can instantiate. The range is the point here rather
 * than ceremony: `foregroundServiceType` became mandatory at 34, so a test that
 * only ran at 26 would prove the older half of the behaviour and call it done.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 34, 36])
class WalletForegroundServiceTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /**
     * **Foreground before anything else.**
     *
     * `startForegroundService` gives about five seconds to reach
     * `startForeground` and raises `ForegroundServiceDidNotStartInTimeException`
     * if it does not — a crash in the shipped app, on the path that brings the
     * user's wallet up.
     */
    @Test
    fun `it is in the foreground by the time onStartCommand returns`() {
        val controller = Robolectric.buildService(WalletForegroundService::class.java).create()

        val result = controller.get().onStartCommand(Intent(), 0, 1)

        val notification = shadowOf(controller.get()).lastForegroundNotification
        assertNotNull("the service never reached startForeground", notification)
        assertEquals(WalletForegroundService.NOTIFICATION_ID, shadowOf(controller.get()).lastForegroundNotificationId)
        assertEquals(Service.START_NOT_STICKY, result)
    }

    /**
     * The channel exists before the notification that names it.
     *
     * A notification posted against a channel that has not been created is
     * dropped silently from API 26 — which would leave a foreground service with
     * nothing visible, the state Play review rejects.
     */
    @Test
    fun `the notification channel is created, and is quiet`() {
        Robolectric.buildService(WalletForegroundService::class.java).create()
            .get().onStartCommand(Intent(), 0, 1)

        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = manager.getNotificationChannel(WalletForegroundService.CHANNEL_ID)

        assertNotNull("no channel was created", channel)
        assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
    }

    @Test
    fun `promoting starts the service`() {
        ServiceForegroundPresence(context).promote()

        val started = shadowOf(context as android.app.Application).nextStartedService
        assertNotNull("nothing was started", started)
        assertEquals(
            WalletForegroundService::class.java.name,
            started.component?.className,
        )
    }

    /**
     * **A refused promotion is not a failed node start.**
     *
     * From API 31 the platform throws
     * `ForegroundServiceStartNotAllowedException` when a backgrounded app starts
     * a foreground service without an exemption — which is precisely the case
     * the wallet most wants to run in, woken by a push. Letting it propagate
     * would fail a start that has nothing wrong with it, and the degraded
     * outcome it would be avoiding is the state the process was already in.
     */
    @Test
    fun `a refusal by the platform is reported, not thrown`() {
        val refused = SecurityException("ForegroundServiceStartNotAllowedException")
        var reported: Throwable? = null
        val hostile = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun startForegroundService(service: Intent?): android.content.ComponentName =
                throw refused

            override fun startService(service: Intent?): android.content.ComponentName =
                throw refused
        }

        ServiceForegroundPresence(hostile) { reported = it }.promote()

        assertEquals(refused, reported)
    }

    /**
     * The manifest half, as a source assertion rather than a merged-manifest
     * one.
     *
     * The component declaration is what makes the Kotlin above reachable at all,
     * and it is in a file no Kotlin test would notice the deletion of. Three
     * properties, each with a failure that is silent: no declaration at all
     * (`startForegroundService` does nothing), no `foregroundServiceType` (the
     * `startForeground` call throws on API 34+), and `exported="true"` (any app
     * on the device may start the wallet's service).
     */
    @Test
    fun `the service is declared, typed, and not exported`() {
        val manifest = File(WalletSourceTree.root, "src/main/AndroidManifest.xml")
        assertTrue("no library manifest at $manifest", manifest.isFile)
        val text = manifest.readText()

        assertTrue(
            "the <service> declaration is gone; startForegroundService would silently " +
                "do nothing",
            """android:name=".host.WalletForegroundService"""" in text,
        )
        assertTrue(
            "no android:foregroundServiceType; ServiceCompat.startForeground throws on " +
                "API 34+ when the type it is passed is not declared",
            """android:foregroundServiceType="dataSync"""" in text,
        )
        assertTrue(
            "the service must not be exported — nothing outside this app may start the " +
                "wallet",
            """android:exported="false"""" in text,
        )
    }

    /** `stopService` on something that is not running is the outcome asked for. */
    @Test
    fun `demoting a service that is not running is not an error`() {
        ServiceForegroundPresence(context).demote()

        assertNull(shadowOf(context as android.app.Application).nextStartedService)
    }
}
