package com.bittr.android

import android.os.Bundle
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.network.DeviceTokenLifecycle
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.DarkModeSetting
import com.bittr.android.navigation.BittrNavHost
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
        deviceTokens.onAppForegrounded()
        lifecycleScope.launch { deviceTokens.syncOnAppStart() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge on every API level, not only where targetSdk 36 forces it (35+).
        // Every screen already pads for the system bars itself — BittrCanvas, Home,
        // the map — because on 35+ it has to. Below 35 the framework used to fit the
        // window instead, which also swallowed the IME inset: `imePadding()` read zero,
        // fields behind the keyboard stayed "on screen" to Compose, and
        // `restore_wallet.yaml` could not reach field 7 on an API 34 emulator.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            val setting by preferences.darkMode.collectAsState()
            BittrTheme(darkTheme = setting.isDark()) {
                BittrApp()
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
 *    scaffold has no launch animation, so the marker is simply the root — accurate
 *    today. When the animation is ported, this tag must move to whatever composes
 *    *after* the cover is gone, or the flows will resume tapping into a cover that
 *    swallows the taps. That failure looks like a flaky test, not a bug.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun BittrApp() {
    Surface(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .semantics { testTagsAsResourceId = true }
                .testTag(TestID.Core.launchComplete),
        ) {
            BittrNavHost()
        }
    }
}
