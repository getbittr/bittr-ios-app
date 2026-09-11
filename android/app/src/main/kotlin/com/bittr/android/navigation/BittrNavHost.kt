package com.bittr.android.navigation

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bittr.android.feature.signup.SignupStartScreen
import com.bittr.android.feature.website.WebsiteScreen

/**
 * Route constants. Kept as plain strings rather than type-safe routes so that the
 * set of destinations stays greppable against the iOS screen inventory while the
 * port is in flight.
 */
object Routes {
    const val SIGNUP_START = "signup/start"

    /**
     * S-36 · Website — the in-app browser (BIT-33). One route for all five iOS
     * call sites: Settings' support / privacy / terms pages, the transaction
     * screen's block explorer link, and a map place's `website`.
     *
     * **It takes a URL and no trust level, and that is the security-relevant part
     * of the signature.** One of those call sites is handed its URL straight from
     * BTCMap place data, so trust is derived from the URL by
     * `FirstPartyOrigins.trustOf` and re-derived on every navigation — never
     * declared by whoever navigated here. A `trust` argument would be a caller's
     * claim about third-party data, which is the shape of the hole BIT-21 was
     * filed about. See `WebsiteScreen`.
     *
     * Build with [websiteRoute]; do not concatenate at the call site.
     */
    const val WEBSITE = "website?url={url}"

    /** [WEBSITE] with [url] encoded. Query-encoded, so a URL with `&` survives. */
    fun websiteRoute(url: String): String =
        "website?url=${Uri.encode(url)}"

    internal const val WEBSITE_ARG_URL = "url"
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

        // S-36. No call site reaches this yet — Settings, the transaction screen
        // and the map are all still to be ported (BIT-7) — so the destination is
        // registered ahead of them rather than the screen being ported again
        // alongside the first one that needs it. That ordering is deliberate:
        // BIT-33's requirements are about how this screen is *entered*, and they
        // are cheaper to satisfy once here than three times at three call sites.
        composable(
            route = Routes.WEBSITE,
            arguments = listOf(
                navArgument(Routes.WEBSITE_ARG_URL) {
                    type = NavType.StringType
                    nullable = false
                },
            ),
        ) { entry ->
            // Empty rather than a fallback URL if the argument is somehow missing:
            // WebsiteScreen classifies "" as third-party and loads nothing, which
            // is the right failure. A default would be a URL nobody asked for.
            val url = entry.arguments?.getString(Routes.WEBSITE_ARG_URL).orEmpty()
            WebsiteScreen(
                url = url,
                onClose = { navController.popBackStack() },
            )
        }
    }
}
