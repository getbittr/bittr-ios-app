package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bittr.android.feature.signup.SignupStartScreen

/**
 * Route constants. Kept as plain strings rather than type-safe routes so that the
 * set of destinations stays greppable against the iOS screen inventory while the
 * port is in flight.
 */
object Routes {
    const val SIGNUP_START = "signup/start"
}

/**
 * Single-activity navigation graph.
 *
 * Only the signup entry point exists so far. Destinations are added here as the
 * port reaches them (BIT-7), each backed by its own `:feature:*` module — the app
 * module knows routes and nothing about a feature's internals.
 *
 * The start destination is hardcoded for now. Once BIT-6 lands a real
 * `WalletService`, this branches on `WalletState`: Uninitialized → signup,
 * Locked → PIN unlock, Ready → home. The stub reports Uninitialized, which is why
 * a fresh scaffold build lands here.
 */
@Composable
fun BittrNavHost(
    navController: NavHostController = rememberNavController(),
) {
    NavHost(
        navController = navController,
        startDestination = Routes.SIGNUP_START,
    ) {
        composable(Routes.SIGNUP_START) {
            SignupStartScreen()
        }
    }
}
