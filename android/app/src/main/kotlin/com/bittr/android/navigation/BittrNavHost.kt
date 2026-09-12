package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.wallet.WalletState
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
 * navigation arguments. Destinations for the rest of the port (buy, receive, map,
 * settings) are added here as BIT-7 reaches them.
 */
@Composable
fun BittrNavHost(
    navController: NavHostController = rememberNavController(),
    viewModel: WalletGateViewModel = hiltViewModel(),
) {
    val walletState by viewModel.walletState.collectAsState()

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
            HomePlaceholderScreen()
        }
    }
}
