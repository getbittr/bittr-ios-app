package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bittr.android.feature.scanner.ScannerScreen
import com.bittr.android.feature.signup.SignupStartScreen

/**
 * Route constants. Kept as plain strings rather than type-safe routes so that the
 * set of destinations stays greppable against the iOS screen inventory while the
 * port is in flight.
 */
object Routes {
    const val SIGNUP_START = "signup/start"

    /**
     * The QR scanner (iOS S-16). Reached from Send, and it returns there — on iOS
     * it is a modal the Send screen presents and dismisses, which is why the flow
     * expects `send.regularButton` to be back on screen after the scanner closes
     * (`shared/flows/features/send_onchain.yaml:83-85`).
     */
    const val SCANNER = "scanner"
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

        composable(Routes.SCANNER) {
            // The scanned string goes nowhere yet, because Send does not exist yet
            // (BIT-7). When it does, this hands the code to the same entry point the
            // paste control feeds — one route for both, as on iOS
            // (`AddressParsing.swift:15`). The scanner itself is complete: routing
            // the result is Send's half of the seam, not the scanner's.
            ScannerScreen(
                onScanned = { navController.popBackStack() },
                onClose = { navController.popBackStack() },
            )
        }
    }
}
