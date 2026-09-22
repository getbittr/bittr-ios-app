package com.bittr.android

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.network.DeviceTokenLifecycle
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.DarkModeSetting
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.lightning.BittrPeerConnection
import com.bittr.android.navigation.BittrNavHost
import com.bittr.android.home.RemovedWalletReset
import com.bittr.android.push.PushCoordinator
import com.bittr.android.push.PushOverlayHost
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.launch

/**
 * The single Activity. Navigation is Compose Navigation inside it — see
 * [BittrNavHost].
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /**
     * Read here, at the root, because the dark-mode choice has to be known before the
     * first frame — [BittrTheme] takes it as a parameter and deliberately does not
     * read it itself, so that the theme stays a pure function of its arguments and
     * every preview and screenshot can force either mode.
     */
    @Inject
    lateinit var preferences: AppPreferences

    /**
     * BIT-41 item 5's second entry point — the one `onNewToken` cannot cover.
     *
     * FCM delivers `onNewToken` at most once, to a process that may not exist. A token rotated
     * during a restore, a data clear or a long idle period therefore produces no callback at
     * all, and without this reconciliation the customer's payout route would die at the first
     * rotation they were not watching, permanently and silently.
     */
    @Inject
    lateinit var deviceTokens: DeviceTokenLifecycle

    @Inject
    lateinit var pushCoordinator: PushCoordinator

    @Inject
    lateinit var transactionConfirmations: com.bittr.android.events.TransactionConfirmations

    /** Empties what the app holds in memory about a wallet once it is removed — see [RemovedWalletReset]. */
    @Inject
    lateinit var removedWalletReset: RemovedWalletReset

    /** Whether the app is on screen, for a swap push's status screen. */
    @Inject
    lateinit var appForeground: AppForeground

    @Inject
    lateinit var wallet: WalletService

    /** `elapsedRealtime` at the last [onStop], or 0 before the first one. */
    private var backgroundedAt: Long = 0L

    /** Reconnected on every foreground while the node runs, as iOS's `SceneDelegate` does. */
    @Inject
    lateinit var bittrPeer: BittrPeerConnection

    /**
     * `api-contract` §2.3 rule 2's per-foreground reset, plus the reconciliation above.
     *
     * Hung off the activity rather than off `ProcessLifecycleOwner`, which would be the more
     * literal reading of "app foreground". This is a single-activity app — `MainActivity` is the
     * only `<activity>` in the manifest — so its `ON_START` *is* the process coming to the
     * foreground, and the alternative is an `androidx.lifecycle:lifecycle-process` dependency
     * for a distinction this app cannot currently express. Revisit if a second activity ever
     * lands.
     *
     * The reconciliation is launched rather than awaited: it does network work, and blocking
     * `onStart` on it would delay the first frame behind a call that is allowed to take as long
     * as a socket timeout. `lifecycleScope` cancels it if the activity goes away.
     */
    override fun onStart() {
        super.onStart()
        // Long enough that stepping out to a maps app, a browser or the share sheet — which
        // every flow and half the screens do — comes back to where the user was, short enough
        // that a phone left on a table does not stay open. iOS gets this from the system
        // killing a backgrounded app; Android's foreground service means it never happens.
        val away = SystemClock.elapsedRealtime() - backgroundedAt
        if (backgroundedAt > 0L && away >= LOCK_AFTER_BACKGROUND_MS) wallet.lock()
        appForeground.setActive(true)
        deviceTokens.onAppForegrounded()
        lifecycleScope.launch { deviceTokens.syncOnAppStart() }
        // Before unlock there's no node yet; the node start's `bittr-peer` runner connects then.
        if (wallet.state.value == WalletState.Ready) {
            lifecycleScope.launch { bittrPeer.ensureConnected() }
        }
    }

    override fun onStop() {
        appForeground.setActive(false)
        backgroundedAt = SystemClock.elapsedRealtime()
        super.onStop()
    }

    /**
     * Swiped out of Recents. The activity goes, the process usually does not — the node holds a
     * foreground service — so without this the next launch walks straight back into an unlocked
     * wallet. `isFinishing` keeps a rotation from locking the screen under the user.
     */
    override fun onDestroy() {
        if (isFinishing) wallet.lock()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super: the splash theme is swapped for Theme.Bittr here, and the platform
        // keeps the mark on screen until the first frame is ready.
        installSplashScreen()
        // Edge-to-edge on every API level, not only where targetSdk 36 forces it (35+).
        // Every screen already pads for the system bars itself — BittrCanvas, Home,
        // the map — because on 35+ it has to. Below 35 the framework used to fit the
        // window instead, which also swallowed the IME inset: `imePadding()` read zero,
        // fields behind the keyboard stayed "on screen" to Compose, and
        // `restore_wallet.yaml` could not reach field 7 on an API 34 emulator.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        removedWalletReset.start()
        setContent {
            val setting by preferences.darkMode.collectAsState()
            BittrTheme(darkTheme = setting.isDark()) {
                BittrApp(pushCoordinator, transactionConfirmations.transactionScreenOpen)
            }
        }
    }
}

/**
 * The Device screen's three-way choice resolved against the system.
 *
 * iOS's `UIViewController.darkModeIsOn()`, and the same three branches — with the
 * difference DEV-03 records: `Device` really does follow the system here, where iOS
 * treats its `.device` case as a read of the trait collection only at the moment a
 * screen recolours. Recomposition does the rest.
 */
@Composable
private fun DarkModeSetting.isDark(): Boolean = when (this) {
    DarkModeSetting.Light -> false
    DarkModeSetting.Dark -> true
    DarkModeSetting.Device -> isSystemInDarkTheme()
}

/**
 * App root.
 *
 * Two things here are load-bearing for the Maestro harness and are easy to delete
 * by accident:
 *
 * 1. **`testTagsAsResourceId = true`.** Compose `Modifier.testTag` is invisible to
 *    UIAutomator — and therefore to Maestro — unless this is set on an ancestor. It
 *    is set once here and inherited by everything below. Without it every
 *    `assertVisible: id:` in `shared/flows/` fails with "element not found" while
 *    the app looks perfectly correct on screen.
 *
 * 2. **The `core.launchComplete` tag.** iOS sets this once its launch animation
 *    finishes, and every flow gates on it via `helpers/wait_for_launch.yaml`. The
 *    animation is ported now ([LaunchAnimation]), so the tag arrives with it: the root
 *    carries it only once the cover is gone, which is what stops a flow tapping into a
 *    cover that swallows the taps.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun BittrApp(pushCoordinator: PushCoordinator, transactionScreenOpen: kotlinx.coroutines.flow.StateFlow<Boolean>) {
    Surface(modifier = Modifier.fillMaxSize()) {
        var launched by rememberSaveable { mutableStateOf(false) }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .semantics { testTagsAsResourceId = true }
                .then(if (launched) Modifier.testTag(TestID.Core.launchComplete) else Modifier),
        ) {
            BittrNavHost()
            // What a push shows, over every screen — see PushOverlayHost.
            PushOverlayHost(pushCoordinator, transactionScreenOpen)
            // Over everything until it is done, and only on a real launch: a rotation or any
            // other recreation keeps `launched`, so the animation does not replay mid-session.
            if (!launched) LaunchAnimation(onFinished = { launched = true })
        }
    }
}

/** Two minutes away from the app and the PIN is asked for again. */
private const val LOCK_AFTER_BACKGROUND_MS = 2 * 60 * 1000L
