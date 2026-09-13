package com.bittr.android.core.wallet.ldk.host

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.bittr.android.core.wallet.ldk.R

/**
 * The thing that stops Android freezing the wallet.
 *
 * It is deliberately almost empty. It owns no node, no scope and no state — see
 * [WalletNodeHost]'s class comment for why the scope is the host's and not this
 * service's. All it does is exist, in the foreground, for as long as a node is
 * meant to be running, so that the process holding that node is not a cached
 * process the system may freeze or kill.
 *
 * That is the entire mitigation available for the problem
 * `NodeConfigPlan.BackgroundSyncPlan` names: ldk-node's 30-second sync intervals
 * run on Rust threads that Doze and App Standby freeze along with everything
 * else, so the intervals are a request and not a guarantee. A foreground service
 * while the wallet is in use plus the app's push wake is the answer, and **how
 * well it works is unmeasured** — K8 (`wallet-core-spec` §6) is the measurement
 * and it needs a device. BIT-123 owns it. Nothing in this file should be read as
 * evidence that channel-monitor freshness survives a doze.
 *
 * ## `dataSync`, and what it costs
 *
 * API 34 made a foreground service type mandatory. The honest one here is
 * `dataSync`: the service exists so a network sync keeps running, which is what
 * that type is for. `connectedDevice` and `specialUse` would both be closer to a
 * story than to a description, and `specialUse` additionally needs a Play
 * Console justification string reviewed by hand.
 *
 * The cost is real and should be written down rather than discovered: **on API
 * 35 `dataSync` is capped at roughly 6 hours in any 24**, after which the system
 * stops the service and a later `startForeground` for the same type throws. A
 * wallet a user leaves open all day will hit it. What happens then is not
 * decided here — the node keeps running unprotected until the process is frozen
 * — and deciding it is part of the same measurement K8 is, because the right
 * answer depends on how long the node actually survives a freeze.
 *
 * ## `START_NOT_STICKY`, on purpose
 *
 * A sticky restart hands the service a null intent after a process kill and asks
 * it to carry on. There is nothing here to carry on with: the node is gone with
 * the process, the seed is behind a PIN the user has not entered, and starting a
 * node for a locked wallet — or for one that has since been removed — is work
 * nobody asked for, done under a notification the user cannot explain.
 *
 * The restart path is the app's: a fresh process has no node and no start in
 * flight, `NodeStartGate` answers "proceed" correctly because it has no memory,
 * and `UnlockViewModel` calls `WalletService.start()` once the PIN is in. The
 * stale-node case — a service restart finding an old object — is
 * `NodeLifecycle.buildAndStart`'s, and it discards before it builds.
 *
 * ## The copy in this notification is not approved
 *
 * `R.string.wallet_node_service_*` is placeholder copy. It is user-visible and
 * permanently on screen while the wallet runs, which puts it squarely inside the
 * approved-copy process (`shared/strings/README.md`), and it has no iOS
 * analogue to port from because iOS has no foreground service. It must not ship
 * as written. See the issue this landed under for the follow-up.
 *
 * Proved by `WalletForegroundServiceTest`.
 */
class WalletForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Before anything else. `startForegroundService` gives the service about
        // five seconds to get here and crashes the app with
        // ForegroundServiceDidNotStartInTimeException if it does not, so nothing
        // that can block or throw belongs above this line.
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        createChannel()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.wallet_node_service_title))
            .setContentText(getString(R.string.wallet_node_service_text))
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(launchIntent())
            // Ongoing and non-dismissable: the notification is the user's only
            // signal that the wallet is holding the process, and a dismissed one
            // on API 34+ would leave a foreground service with nothing visible.
            .setOngoing(true)
            // LOW, not MIN: MIN hides it from the shade on some OEM builds, and a
            // foreground service the user cannot see is the pattern Play reviews
            // reject. It still makes no sound and no heads-up.
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            // Nothing about the wallet on the lock screen. There is no balance in
            // this notification today and there must not be one added later
            // without this line being reconsidered first.
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }

    /**
     * Tapping the notification opens the app.
     *
     * Resolved through the package manager rather than by naming `MainActivity`,
     * which lives in `:app` and is not on this module's classpath — and should
     * not be: a library module that names the activity it is hosted by cannot be
     * hosted by anything else. Null when there is no launcher activity, which is
     * the case in a test harness and is not an error.
     */
    private fun launchIntent(): PendingIntent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.wallet_node_service_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
            },
        )
    }

    companion object {
        const val CHANNEL_ID = "wallet_node"

        /** Arbitrary and non-zero: `startForeground` rejects 0. */
        const val NOTIFICATION_ID = 4101
    }
}

/**
 * [ForegroundPresence] over [WalletForegroundService].
 *
 * Split from the service because the ordering decisions are [WalletNodeHost]'s
 * and are proved on the JVM against a recorder — what is left here is the two
 * platform calls and the one exception that has to be swallowed.
 *
 * Proved by `WalletForegroundServiceTest`.
 */
class ServiceForegroundPresence(
    context: Context,
    /**
     * Where a refused promotion goes. Defaulted to a no-op rather than to a
     * throw: see [promote].
     */
    private val onRefused: (Throwable) -> Unit = {},
) : ForegroundPresence {

    private val appContext = context.applicationContext

    /**
     * Start the service, or note that Android would not let us.
     *
     * From API 31, starting a foreground service from the background throws
     * `ForegroundServiceStartNotAllowedException` unless the app holds one of a
     * short list of exemptions. That is a routine outcome, not a bug: the app
     * may be responding to a push while backgrounded, which is exactly when the
     * wallet most wants to run and exactly when the platform is least willing to
     * let it announce itself.
     *
     * It is swallowed because the alternative is worse in both directions. A
     * throw would propagate out of [WalletNodeHost.start] and fail a node start
     * that has nothing wrong with it; and the degraded state — a node running in
     * a process with no foreground protection — is *the state the process was
     * already in*, so refusing to start is a strictly larger loss than
     * continuing without the service.
     *
     * The general `catch` is deliberate. The specific type is API 31+ only, so
     * naming it means a version guard, and the set of things the platform throws
     * from this call has grown with every release (API 34 added the type
     * mismatch, API 35 the `dataSync` time cap). A promotion that fails for a
     * reason we have not heard of yet must degrade the same way.
     */
    override fun promote() {
        try {
            ContextCompat.startForegroundService(appContext, intent())
        } catch (refused: Exception) {
            onRefused(refused)
        }
    }

    override fun demote() {
        // `stopService` on a service that is not running is a no-op returning
        // false, which is the outcome asked for. Not guarded.
        runCatching { appContext.stopService(intent()) }
    }

    private fun intent() = Intent(appContext, WalletForegroundService::class.java)
}
