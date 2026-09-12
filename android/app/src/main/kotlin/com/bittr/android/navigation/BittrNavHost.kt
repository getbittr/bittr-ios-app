package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.feature.home.HomeScreen
import com.bittr.android.feature.settings.DeviceScreen
import com.bittr.android.feature.settings.DeviceViewModel
import com.bittr.android.feature.settings.LightningQuestionScreen
import com.bittr.android.feature.settings.SettingsScreen
import com.bittr.android.feature.settings.WebsitePage
import com.bittr.android.feature.settings.WebsiteScreen
import com.bittr.android.feature.signup.CreateWalletScreen
import com.bittr.android.feature.signup.RestoreWalletScreen

/**
 * Route constants. Kept as plain strings rather than type-safe routes so that the
 * set of destinations stays greppable against the iOS screen inventory while the
 * port is in flight.
 */
object Routes {
    const val SIGNUP_START = "signup/start"
    const val SIGNUP_RESTORE = "signup/restore"
    const val PIN_UNLOCK = "pin/unlock"
    const val HOME = "home"
    const val SETTINGS = "settings"
    const val DEVICE = "settings/device"
    const val LIGHTNING_QUESTION = "settings/device/lightning"

    /** The three `getbittr.com` pages, keyed by [WebsitePage] name. */
    const val WEBSITE_ARG = "page"
    const val WEBSITE = "settings/website/{$WEBSITE_ARG}"

    fun website(page: WebsitePage) = "settings/website/${page.name}"
}

/**
 * Single-activity navigation graph.
 *
 * The start destination is the wallet's state, which is the branch the iOS app makes
 * at launch: no key material → signup, key material present → PIN, unlocked → home.
 * [WalletState] is read once for the start destination and then observed, so
 * unlocking moves the user off the PIN screen without the screen knowing about
 * navigation.
 *
 * The whole create-wallet arc is one destination — see
 * `CreateWalletScreen`'s documentation for why the twelve words must not travel as
 * navigation arguments.
 *
 * ### Settings is a destination, iOS's is a pop-up
 *
 * `CoreViewController.showSettings` springs Settings up over Home as a child view
 * controller, with Device details and the website pages presented modally over it.
 * Here the three are ordinary destinations stacked on Home. `features/settings.yaml`
 * cannot tell the difference — it enters on `nav.settingsButton` and leaves on
 * `header.downButton` — and the back stack it produces is the one Android's Back
 * gesture already knows how to walk.
 */
@Composable
fun BittrNavHost(
    navController: NavHostController = rememberNavController(),
    viewModel: WalletGateViewModel = hiltViewModel(),
) {
    val walletState by viewModel.walletState.collectAsState()

    // See [NotPortedDialog]. Held here rather than in a screen because it is
    // scaffolding for the port, not app behaviour, and keeping it out of the feature
    // modules is what makes it a single deletion when Wave 1 and Wave 3 finish.
    var notPorted by remember { mutableStateOf<String?>(null) }
    notPorted?.let { NotPortedDialog(screen = it, onDismiss = { notPorted = null }) }

    NavHost(
        navController = navController,
        startDestination = when (walletState) {
            WalletState.Uninitialized -> Routes.SIGNUP_START
            WalletState.Locked -> Routes.PIN_UNLOCK
            WalletState.Ready -> Routes.HOME
        },
    ) {
        composable(Routes.SIGNUP_START) {
            CreateWalletScreen(
                onFinished = {
                    navController.navigate(Routes.HOME) {
                        // The arc is finished; Back must not walk into a signup flow
                        // for a wallet that now exists.
                        popUpTo(Routes.SIGNUP_START) { inclusive = true }
                    }
                },
                onRestoreWallet = { navController.navigate(Routes.SIGNUP_RESTORE) },
            )
        }

        // Restore *is* a separate destination, where the create arc's seven steps are
        // one — the two are not inconsistent. What must not cross a destination
        // boundary is the phrase, and here it never leaves RestoreWalletViewModel.
        // Signup1 → Restore is a real back-stack edge on iOS too (`moveToPage(3)`
        // returns), so making it one here is what gives the user a working Back.
        composable(Routes.SIGNUP_RESTORE) {
            RestoreWalletScreen(
                onFinished = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.SIGNUP_START) { inclusive = true }
                    }
                },
                onCancelled = { navController.popBackStack() },
            )
        }

        composable(Routes.PIN_UNLOCK) {
            UnlockScreen(
                onUnlocked = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.PIN_UNLOCK) { inclusive = true }
                    }
                },
                // Ten wrong PINs: the wallet is off the device, so the PIN screen must
                // not be on the back stack. `inclusive` is what stops Back returning to
                // a pad that would unlock nothing.
                onWalletWiped = {
                    navController.navigate(Routes.SIGNUP_START) {
                        popUpTo(Routes.PIN_UNLOCK) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.HOME) {
            HomeScreen(
                onSettings = { navController.navigate(Routes.SETTINGS) },
                // Wave 1, other issues: the BTCMap screen (`features/bitcoin_map`)
                // and the price screen (`features/bitcoin_value`). The entry points
                // are here so that porting either is a one-line change to this file.
                onMap = { notPorted = "The bitcoin map" },
                onCurrency = { notPorted = "The bitcoin price" },
                // Wave 2, behind BIT-6. Reached only once `walletHasSynced` is true,
                // so today Home's own guard answers first and these are unreachable —
                // they are wired anyway so that flipping that flag does not leave a
                // dead button behind it.
                onSend = { notPorted = "Sending bitcoin" },
                onReceive = { notPorted = "Receiving bitcoin" },
                onBalanceDetails = { notPorted = "Your balance" },
                // Wave 3. Not guarded by the sync on iOS either — see HomeScreen.
                onBuy = { notPorted = "Buying bitcoin" },
                onAcademy = { notPorted = "The academy" },
            )
        }

        settingsArea(navController)
    }
}

/**
 * The Settings area — Settings, the three website pages, Device details and the
 * Lightning question card — as one installable graph.
 *
 * Extracted from [BittrNavHost] so that `SettingsFlowTest` can walk
 * `features/settings.yaml` against **this** graph rather than against a copy of it.
 * A test that re-declares the edges it is checking proves only that the test author
 * and the screen author agree; the Android Maestro runner is not stood up yet, so
 * until it is, running the shipping graph is the closest thing to running the flow.
 *
 * @param deviceViewModel how Device details gets its `ViewModel`. Defaults to Hilt,
 *   which is what the app uses. The test overrides it because a unit test has no
 *   Hilt graph — `:app` deliberately carries no `hilt-android-testing` dependency —
 *   and this is the only seam that needs one.
 */
internal fun NavGraphBuilder.settingsArea(
    navController: NavHostController,
    deviceViewModel: @Composable () -> DeviceViewModel = { hiltViewModel() },
) {
    composable(Routes.SETTINGS) {
        SettingsScreen(
            onDown = { navController.popBackStack() },
            onOpenWebsite = { navController.navigate(Routes.website(it)) },
            onOpenDevice = { navController.navigate(Routes.DEVICE) },
        )
    }

    composable(
        route = Routes.WEBSITE,
        arguments = listOf(navArgument(Routes.WEBSITE_ARG) { type = NavType.StringType }),
    ) { entry ->
        // The argument is produced by `Routes.website` from an enum constant, so
        // an unrecognised value means the route was hand-built. Falling back to
        // Support rather than throwing keeps a typo out of a crash log, and the
        // support page is the safest of the three to land on by accident.
        val page = entry.arguments
            ?.getString(Routes.WEBSITE_ARG)
            ?.let { name -> WebsitePage.entries.firstOrNull { it.name == name } }
            ?: WebsitePage.Support

        WebsiteScreen(page = page, onDown = { navController.popBackStack() })
    }

    composable(Routes.DEVICE) {
        DeviceScreen(
            onDown = { navController.popBackStack() },
            onOpenLightningQuestion = {
                navController.navigate(Routes.LIGHTNING_QUESTION)
            },
            viewModel = deviceViewModel(),
        )
    }

    composable(Routes.LIGHTNING_QUESTION) {
        LightningQuestionScreen(onDown = { navController.popBackStack() })
    }
}

/**
 * "That screen is not built yet."
 *
 * **Scaffolding, and it is meant to be deleted.** Every control it sits behind is one
 * the port has reached the *entry point* of but not the destination — the map and
 * price screens (Wave 1, other issues), Send, Receive and the balance detail (Wave 2,
 * BIT-6), Buy and the academy (Wave 3).
 *
 * The alternative was leaving those buttons silently inert, which is worse in both
 * directions: a user cannot tell a not-yet-built screen from a broken one, and a
 * reviewer cannot tell a deliberate gap from a forgotten `TODO`. The copy is in the
 * same voice as the rest of the honest-placeholder text this port has used since
 * BIT-93, and it promises nothing.
 *
 * It carries `alert.button.0` because it is a one-button alert and the Maestro suite
 * indexes alert buttons by position — but no flow taps it, because no flow reaches a
 * screen that does not exist.
 */
@Composable
private fun NotPortedDialog(screen: String, onDismiss: () -> Unit) {
    BittrAlertDialog(
        title = "Not on Android yet",
        message = "$screen is still being built for Android. It's in the iOS app today.",
        confirmLabel = "Okay",
        onConfirm = onDismiss,
        confirmTestTag = TestID.Alert.buttonAt(0),
    )
}
