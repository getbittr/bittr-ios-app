package com.bittr.android.navigation

import com.bittr.android.core.designsystem.BittrPopup
import com.bittr.android.core.designsystem.BittrSheet
import com.bittr.android.home.HomeValueViewModel
import com.bittr.android.core.designsystem.BittrTheme
import androidx.compose.ui.window.DialogProperties
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.navigation.compose.dialog
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.navigation.NamedNavArgument
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraph
import com.bittr.android.core.designsystem.BittrAppBarLogoOverlay
import com.bittr.android.core.designsystem.LocalAppBarBackgroundVisible
import com.bittr.android.core.designsystem.LocalAppBarLogoVisible
import com.bittr.android.core.designsystem.pageSlideIn
import com.bittr.android.core.designsystem.pageSlideOut
import com.bittr.android.core.designsystem.stackSlideIn
import com.bittr.android.core.designsystem.stackSlideOut
import com.bittr.android.feature.signup.SignupPage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bittr.android.BuildConfig
import com.bittr.android.core.common.TestID
import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.okhttp.OkHttpBittrHttpClient
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.feature.academy.AcademyScreen
import com.bittr.android.feature.academy.ArticleScreen
import com.bittr.android.receive.ReceiveViewModel
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.feature.send.SendLnurlRequest
import com.bittr.android.feature.send.SendRoute
import com.bittr.android.send.SendViewModel
import com.bittr.android.buy.BuyViewModel
import com.bittr.android.buy.ProfitsViewModel
import com.bittr.android.feature.buy.BuyRoute
import com.bittr.android.feature.buy.ProfitSummary
import com.bittr.android.feature.buy.ProfitsScreen
import com.bittr.android.feature.home.HomeScreen
import com.bittr.android.feature.home.ProfitPill
import com.bittr.android.feature.home.MoveScreen
import com.bittr.android.feature.home.TransactionScreen
import com.bittr.android.feature.home.TransactionViewModel
import com.bittr.android.feature.map.MapScreen
import com.bittr.android.feature.scanner.ScannerScreen
import com.bittr.android.feature.settings.DeviceScreen
import com.bittr.android.feature.settings.DeviceViewModel
import com.bittr.android.core.wallet.ChannelSummary
import com.bittr.android.core.wallet.ldk.lightning.NodeEvent
import com.bittr.android.events.ChannelClosedCard
import com.bittr.android.events.NodeEventsViewModel
import com.bittr.android.feature.settings.LightningQuestionScreen
import com.bittr.android.feature.settings.LightningQuestionViewModel
import com.bittr.android.feature.settings.LightningSendableQuestionScreen
import com.bittr.android.core.lnurl.LnurlSource
import com.bittr.android.send.WebLnurlViewModel
import com.bittr.android.feature.settings.QuestionScreen
import com.bittr.android.feature.settings.SettingsScreen
import com.bittr.android.feature.settings.WebsitePage
import com.bittr.android.feature.receive.ReceiveRoute
import com.bittr.android.feature.value.ValueScreen
import com.bittr.android.feature.website.WebsiteScreen
import com.bittr.android.feature.signup.CreateWalletScreen
import com.bittr.android.feature.signup.RestoreWalletScreen
import com.bittr.android.removal.RemovalOrigin
import com.bittr.android.removal.WalletRemovalHost
import com.bittr.android.removal.WalletRemovalViewModel

/**
 * Route constants. Kept as plain strings rather than type-safe routes so that the
 * set of destinations stays greppable against the iOS screen inventory while the
 * port is in flight.
 */
object Routes {
    const val SIGNUP_START = "signup/start"

    /** The bittr signup at the end of onboarding (`Signup7` → `Transfer1`). */
    const val SIGNUP_BITTR = "signup/bittr"
    const val SIGNUP_RESTORE = "signup/restore"
    const val PIN_UNLOCK = "pin/unlock"
    const val HOME = "home"
    const val SETTINGS = "settings"
    const val DEVICE = "settings/device"
    const val LIGHTNING_QUESTION = "settings/device/lightning"

    /** The "closed lightning connection" card, raised by the node's `channelClosed` event. */
    const val CHANNEL_CLOSED = "question/channel-closed"

    /** The three `getbittr.com` pages, keyed by [WebsitePage] name. */
    const val WEBSITE_ARG = "page"
    const val WEBSITE = "settings/website/{$WEBSITE_ARG}"

    fun website(page: WebsitePage) = "settings/website/${page.name}"

    /**
     * The QR scanner (iOS S-16). Reached from Send, and it returns there — on iOS
     * it is a modal the Send screen presents and dismisses, which is why the flow
     * expects `send.regularButton` to be back on screen after the scanner closes
     * (`shared/flows/features/send_onchain.yaml:83-85`).
     */
    const val SCANNER = "scanner"

    /**
     * The three Wave 1 read-only screens (BIT-99). Each needs an unlocked wallet and
     * nothing else — no funds, no node — which is why they are reachable before the
     * wallet engine lands, and each is one destination rather than several: the
     * Academy holds its open lesson as state and the map holds its open place the
     * same way, matching the modals iOS presents over them.
     */
    const val VALUE = "value"
    const val MAP = "map"

    /** An article (`CoreToArticle`), by slug — from the signup pages' article cards. */
    const val ARTICLE_ARG = "slug"
    const val ARTICLE = "article/{$ARTICLE_ARG}"

    fun article(slug: String) = "article/$slug"

    /** Receive (`HomeToReceive`). Reached from Home once the wallet has synced. */
    const val RECEIVE = "receive"

    /** Send (`HomeToSend`), and the "why a limit for instant payments?" card behind it. */
    const val SEND = "send"
    const val SEND_QUESTION = "send/question"

    /** The balance screen (`MoveViewController`), from Home's balance card. */
    const val MOVE = "move"

    /** Buy (`HomeToBuy`), with the bittr signup it opens, and Profits (`profitButtonTapped`). */
    const val BUY = "buy"
    const val PROFITS = "profits"

    /** A transaction (`TransactionViewController`), by id — from Home's history and after a send. */
    const val TRANSACTION =
        "transaction/{${TransactionViewModel.ID_ARG}}?${TransactionViewModel.CONFETTI_ARG}={${TransactionViewModel.CONFETTI_ARG}}"

    /** [confetti] opens the bittr payout summary (`showConfetti`). */
    fun transaction(id: String, confetti: Boolean = false) =
        "transaction/$id" + if (confetti) "?${TransactionViewModel.CONFETTI_ARG}=true" else ""

    /** The block explorer page for an on-chain transaction (`TransactionToWebsite`). */
    const val EXPLORER_ARG = "txid"
    const val EXPLORER = "explorer/{$EXPLORER_ARG}"

    fun explorer(txId: String) = "explorer/$txId"
}

/**
 * `EnvironmentConfig.explorerURL`: the regtest Esplora in development, mempool.space in
 * production. The development host is the node's own chain source without its `/api`, so
 * it is not written down twice.
 */
private fun explorerUrl(txId: String): String {
    val base = if (BuildConfig.DEBUG) BuildConfig.LDK_CHAIN_SOURCE_URL.removeSuffix("/api") else "https://mempool.space"
    return "$base/tx/$txId?mode=details"
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
 * navigation arguments. Destinations for the rest of the port (buy, receive, send)
 * are added here as BIT-7 reaches them.
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
    // Which chain a scanned address has to be on. Debug is regtest, release is
    // mainnet, mirroring iOS's `EnvironmentConfig.bitcoinDevKitNetwork`. Injected
    // rather than read inside the parser because `:core:common` cannot see `:app`'s
    // BuildConfig — the same reason AuthCapabilities is injected.
    network: BitcoinNetwork = BitcoinNetwork.fromBuildConfig(BuildConfig.BITCOIN_NETWORK),
    // Which backend this build talks to, read here for the same reason and handed
    // down the same way (BIT-41 item 1). Unlike `network` above there is no lenient
    // fallback on an unrecognised name: see BittrEnvironment.fromBuildConfig on why
    // neither direction is the safe one.
    environment: BittrEnvironment = BittrEnvironment.fromBuildConfig(BuildConfig.BITTR_ENVIRONMENT),
    // The single HTTP client for the process. One instance, because OkHttp's
    // connection and thread pools live on it — a per-screen client is a per-screen
    // pool, which is the standard way to turn one app into several from the
    // backend's point of view.
    http: HttpClient = remember {
        // Logged in debug builds, like the injected client in PushModule: the buy signup's calls
        // are the ones the regtest suite fails on, and they left no trace.
        OkHttpBittrHttpClient(log = { line -> if (BuildConfig.DEBUG) android.util.Log.i("BittrHttp", line) })
    },
) {
    val walletState by viewModel.walletState.collectAsState()
    val removal = hiltViewModel<WalletRemovalViewModel>().coordinator
    // A first-party page's Lightning link, on its way to Send.
    val webLnurl = hiltViewModel<WebLnurlViewModel>().handoff

    // The node's `channelClosed` event opens the "closed lightning connection" card over
    // whatever is on screen, as iOS's `launchQuestion` does.
    val nodeEvents = hiltViewModel<NodeEventsViewModel>()
    var channelClosedAnswer by remember { mutableStateOf("") }
    LaunchedEffect(nodeEvents) {
        nodeEvents.events.collect { event ->
            // Not during the 10-wrong-PIN removal: iOS suppresses it there, and the close is the
            // removal's own.
            if (event is NodeEvent.ChannelClosed && !removal.isLockoutRemoval) {
                channelClosedAnswer = ChannelClosedCard.answer(event)
                navController.navigate(Routes.CHANNEL_CLOSED)
            }
        }
    }

    // "Swap & Instant Receive" on a channel-full payout push opens a pre-filled swap, and a swap
    // push opens the latest swap's status.
    val swapLaunches = hiltViewModel<com.bittr.android.swap.SwapLaunchViewModel>().requests
    LaunchedEffect(swapLaunches) {
        swapLaunches.requests.collect { request ->
            when (request) {
                is com.bittr.android.swap.SwapLaunchRequest.PayoutSwap ->
                    navController.navigate(SwapRoutes.payoutSwap(request.suggestedSats))
                is com.bittr.android.swap.SwapLaunchRequest.Status ->
                    navController.navigate(SwapRoutes.status(request.boltzId))
            }
        }
    }

    // A completed payment or swap opens its transaction over whatever is showing, as iOS's
    // `launchTransactionVC`, `addNewPaymentToTable` and `openCompletedSwapTransaction` do.
    val confirmations = hiltViewModel<com.bittr.android.events.TransactionConfirmationsViewModel>().confirmations
    // `.paymentFailed`: iOS's `paymentfailed` alert, over whatever is on screen.
    val paymentFailure by confirmations.paymentFailure.collectAsState()
    paymentFailure?.let { failure ->
        BittrAlertDialog(
            title = failure.title,
            message = failure.message,
            confirmLabel = "Okay",
            onConfirm = confirmations::dismissPaymentFailure,
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }
    LaunchedEffect(confirmations) {
        confirmations.requests.collect { request -> navController.openTransaction(request.id, request.confetti) }
    }
    LaunchedEffect(navController) {
        navController.currentBackStackEntryFlow.collect { entry ->
            confirmations.onTransactionScreen(entry.destination.route == Routes.TRANSACTION)
        }
    }

    // See [NotPortedDialog]. Held here rather than in a screen because it is
    // scaffolding for the port, not app behaviour, and keeping it out of the feature
    // modules is what makes it a single deletion when Wave 1 and Wave 3 finish.
    var notPorted by remember { mutableStateOf<String?>(null) }
    notPorted?.let { NotPortedDialog(screen = it, onDismiss = { notPorted = null }) }

    // `checkWalletRemoval`: a lockout to resume, or a removal left half-done.
    LaunchedEffect(Unit) { removal.checkOnLaunch() }
    // A removal from Device details, waiting for Settings to finish closing onto Home.
    var removedToSignup by remember { mutableStateOf(false) }

    WalletRemovalHost(
        coordinator = removal,
        // The erase already swaps the start destination to signup; this clears whatever
        // back stack was above it so Back cannot return to a screen of the old wallet.
        onWalletRemoved = {
            // iOS's `performWalletReset` closes Settings first (`hideSettings`) and then slides from
            // Home to Signup (`showSignup`). Removal from Device details does the same here: back
            // to Home the way Settings closes, and the slide once Home is alone on screen — see
            // [removedToSignup] below. From the PIN or a signup page there is nothing to close.
            val closing = stackLevel(navController.currentDestination?.route) == null &&
                navController.popBackStack(Routes.HOME, inclusive = false)
            if (closing) {
                removedToSignup = true
            } else {
                navController.navigate(Routes.SIGNUP_START) {
                    popUpTo(navController.graph.id) { inclusive = true }
                    launchSingleTop = true
                }
            }
        },
    ) {
    // Read once, at launch. A start destination that followed the state would rebuild the graph
    // on every change and pop the back stack with it — creating a wallet unlocks it on the
    // Ready page, which would throw the user out of onboarding before the bittr signup. Every
    // later transition navigates explicitly: unlock, the end of onboarding or restore, removal.
    // The screen lock, from anywhere. `MainActivity` puts the wallet back to Locked when the
    // task is swiped away or after long enough in the background, and the user lands on the PIN
    // screen with the back stack cleared rather than inside the wallet they just locked.
    //
    // Only from Ready. Finishing signup or restore goes Uninitialized → Locked → Ready — `setPin`
    // stores the PIN, then `unlock` with it takes a key derivation's time — and following that
    // passing Locked threw the user out of onboarding onto the PIN pad before the Ready page.
    //
    // The jump itself is instant, as iOS's `lockForReauthentication` shows the PIN inside
    // `performWithoutAnimation`: the lock mostly lands while the app is in the background, and a
    // slide would play out in front of the user as they come back to it. [lockJump] holds until
    // the PIN pad is alone on screen.
    var previousWalletState by remember { mutableStateOf(walletState) }
    var lockJump by remember { mutableStateOf(false) }
    LaunchedEffect(walletState) {
        val wasReady = previousWalletState == WalletState.Ready
        previousWalletState = walletState
        if (wasReady && walletState == WalletState.Locked &&
            navController.currentDestination?.route != Routes.PIN_UNLOCK
        ) {
            lockJump = true
            navController.navigate(Routes.PIN_UNLOCK) {
                popUpTo(navController.graph.id) { inclusive = true }
                launchSingleTop = true
            }
        }
    }

    val startDestination = remember {
        when (walletState) {
            WalletState.Uninitialized -> Routes.SIGNUP_START
            WalletState.Locked -> Routes.PIN_UNLOCK
            WalletState.Ready -> Routes.HOME
        }
    }
    // One top bar over the signup pages while they slide — see BittrAppBarLogoOverlay. It is pinned
    // while everything on screen is a page with the logo in the same place and at least one of them
    // is a signup page; the pages' own logos and bar fills hide meanwhile, so there is one, and it
    // stays put.
    val launchLogoVisible = LocalAppBarLogoVisible.current
    val visibleEntries by navController.visibleEntries.collectAsState()
    val visibleRoutes = visibleEntries.map { it.destination }.filter { it !is NavGraph }.map { it.route }
    // The bittr signup on its own is left to draw its own bar: its pages slide inside it, under that
    // bar, and its alerts are drawn in the page, where the overlay would sit on top of their scrim.
    // Two of these pages on screen at once are sliding between each other — across the signup
    // strip, or up and down the PIN / Signup / Home stack — and the logo stays put over them, as
    // it does on iOS, where it belongs to CoreViewController's top bar. Home's header is its own
    // and has no translucent bar, so with Home in the slide the overlay is the logo alone and each
    // page keeps its own fill.
    val logoPinned = visibleRoutes.all { it in LogoBarRoutes } && (
        visibleRoutes.size > 1 ||
            (visibleRoutes.any { signupPage(it) != null } && visibleRoutes != listOf(Routes.SIGNUP_BITTR))
        )
    val barPinned = logoPinned && Routes.HOME !in visibleRoutes
    LaunchedEffect(visibleRoutes) {
        if (lockJump && visibleRoutes == listOf(Routes.PIN_UNLOCK)) lockJump = false
    }
    // The second half of a removal from Device details: Settings has closed onto Home, and the
    // wallet leaves for signup the way iOS's `showSignup` takes it, Home dropping away below.
    LaunchedEffect(removedToSignup, visibleRoutes) {
        if (removedToSignup && visibleRoutes == listOf(Routes.HOME)) {
            removedToSignup = false
            navController.navigate(Routes.SIGNUP_START) {
                popUpTo(navController.graph.id) { inclusive = true }
                launchSingleTop = true
            }
        }
    }
    // The canvas behind every destination. The signup pages' slide overshoots — iOS's spring at
    // damping 0.65 — and for that moment the edge the page has pulled away from shows whatever is
    // behind it; on iOS that is SignupViewController's own yellow, here it was the white window.
    Box(
        Modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas),
    ) {
        CompositionLocalProvider(
            LocalAppBarLogoVisible provides (launchLogoVisible && !logoPinned),
            LocalAppBarBackgroundVisible provides !barPinned,
        ) {
            NavHost(
                navController = navController,
                startDestination = startDestination,
            ) {
                composable(
                    Routes.SIGNUP_START,
                    enterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    exitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                    popEnterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    popExitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                ) {
                    CreateWalletScreen(
                        onFinished = {
                            navController.navigate(Routes.HOME) {
                                // The arc is finished; Back must not walk into a signup flow
                                // for a wallet that now exists.
                                popUpTo(Routes.SIGNUP_START) { inclusive = true }
                            }
                        },
                        onRestoreWallet = { navController.navigate(Routes.SIGNUP_RESTORE) },
                        onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                        onContinueToSignup = {
                            navController.navigate(Routes.SIGNUP_BITTR) {
                                popUpTo(Routes.SIGNUP_START) { inclusive = true }
                            }
                        },
                    )
                }

                // Signup7's Next: the bittr signup slides in as the next page of the strip, under
                // the same top bar, rather than opening as the Buy section's sheet.
                composable(
                    Routes.SIGNUP_BITTR,
                    enterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    exitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                    popEnterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    popExitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                ) {
                    val buy: BuyViewModel = hiltViewModel()
                    BuyRoute(
                        source = buy.source,
                        onboarding = true,
                        onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                        onDown = {
                            navController.navigate(Routes.HOME) {
                                popUpTo(Routes.SIGNUP_BITTR) { inclusive = true }
                            }
                        },
                    )
                }

                // Restore *is* a separate destination, where the create arc's seven steps are
                // one — the two are not inconsistent. What must not cross a destination
                // boundary is the phrase, and here it never leaves RestoreWalletViewModel.
                // Signup1 → Restore is a real back-stack edge on iOS too (`moveToPage(3)`
                // returns), so making it one here is what gives the user a working Back.
                composable(
                    Routes.SIGNUP_RESTORE,
                    enterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    exitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                    popEnterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    popExitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                ) {
                    RestoreWalletScreen(
                        onFinished = {
                            navController.navigate(Routes.HOME) {
                                popUpTo(Routes.SIGNUP_START) { inclusive = true }
                            }
                        },
                        onCancelled = { navController.popBackStack() },
                        onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                    )
                }

                composable(
                    Routes.PIN_UNLOCK,
                    enterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    exitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                    popEnterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    popExitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                ) {
                    UnlockScreen(
                        onUnlocked = {
                            navController.navigate(Routes.HOME) {
                                popUpTo(Routes.PIN_UNLOCK) { inclusive = true }
                            }
                        },
                        onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                    )
                }

                composable(
                    Routes.HOME,
                    enterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    exitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                    popEnterTransition = { if (lockJump) EnterTransition.None else coreSlideIn() },
                    popExitTransition = { if (lockJump) ExitTransition.None else coreSlideOut() },
                ) {
                    val profits: ProfitsViewModel = hiltViewModel()
                    val profit by profits.summary.collectAsState()
                    // The value card's week of prices, held for as long as Home is on the stack.
                    val homeValue: HomeValueViewModel = hiltViewModel()
                    val valueWeek by homeValue.week.collectAsState()
                    // Wallet and Academy side by side under one menu bar, as iOS's CoreViewController
                    // holds them: the bar's Academy slides across to it rather than opening a page.
                    WalletTabs(
                        onSettings = { navController.navigate(Routes.SETTINGS) },
                        wallet = { pageModifier, bottomSpace ->
                            HomeScreen(
                                onSettings = { navController.navigate(Routes.SETTINGS) },
                                // Wave 1, landed by BIT-99. These are the entry points
                                // `bitcoin_map.yaml` and `bitcoin_value.yaml` tap from Home, and every
                                // screen behind them needs an unlocked wallet and nothing else — no
                                // funds, no node — so they are live today.
                                onMap = { navController.navigate(Routes.MAP) },
                                onCurrency = { navController.navigate(Routes.VALUE) },
                                onTransaction = { id -> navController.navigate(Routes.transaction(id)) },
                                // Wave 2, behind BIT-6. Reached only once `walletHasSynced` is true,
                                // so today Home's own guard answers first and these are unreachable —
                                // they are wired anyway so that flipping that flag does not leave a
                                // dead button behind it.
                                onSend = { navController.navigate(Routes.SEND) },
                                onReceive = { navController.navigate(Routes.RECEIVE) },
                                onBalanceDetails = { navController.navigate(Routes.MOVE) },
                                // Wave 3. Not guarded by the sync on iOS either — see HomeScreen.
                                onBuy = { navController.navigate(Routes.BUY) },
                                profitPill = profit?.let { ProfitPill(it.percentText, it.isLoss) },
                                onProfit = { navController.navigate(Routes.PROFITS) },
                                valueWeek = valueWeek,
                                navBar = false,
                                contentBottomPadding = bottomSpace,
                                modifier = pageModifier,
                            )
                        },
                        academy = { pageModifier, bottomSpace ->
                            AcademyScreen(onBack = null, modifier = pageModifier, contentBottomPadding = bottomSpace)
                        },
                    )
                }

                // Home's destinations are page sheets over it, as iOS presents them from HomeViewController —
                // and so is everything they open in turn, so a sheet is never popped from under the one
                // it opened (navigating to an ordinary destination closes every dialog above it).
                sheet(navController, Routes.BUY) { _, dismiss ->
                    val buy: BuyViewModel = hiltViewModel()
                    BuyRoute(
                        source = buy.source,
                        onDown = dismiss,
                        onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                    )
                }

                sheet(navController, Routes.PROFITS) { _, dismiss ->
                    val profits: ProfitsViewModel = hiltViewModel()
                    val summary by profits.summary.collectAsState()
                    ProfitsScreen(
                        summary = summary ?: ProfitSummary(0, 0, 0, "€"),
                        onDown = dismiss,
                    )
                }

                sheet(navController, Routes.VALUE) { _, dismiss ->
                    ValueScreen(
                        environment = environment,
                        http = http,
                        onBack = dismiss,
                    )
                }

                sheet(navController, Routes.MAP) { _, dismiss ->
                    MapScreen(onBack = dismiss)
                }

                // iOS presents the article as a page sheet (`CoreToArticle`): a dialog destination,
                // so the screen it came from stays underneath, dimmed. BittrSheet does the rest.
                dialog(
                    route = Routes.ARTICLE,
                    arguments = listOf(navArgument(Routes.ARTICLE_ARG) { type = NavType.StringType }),
                    dialogProperties = OverlayDialog,
                ) { entry ->
                    BittrSheet(onDismissed = { navController.popBackStack() }) { dismiss ->
                        ArticleScreen(
                            slug = entry.arguments?.getString(Routes.ARTICLE_ARG).orEmpty(),
                            onDown = dismiss,
                        )
                    }
                }

                sheet(navController, Routes.RECEIVE) { _, dismiss ->
                    val receive: ReceiveViewModel = hiltViewModel()
                    ReceiveRoute(source = receive.source, onDown = dismiss)
                }

                sheet(navController, Routes.SEND) { entry, dismiss ->
                    val send: SendViewModel = hiltViewModel()
                    // Taken once, when Send opens: reopening Send must not replay a page's LNURL.
                    val lnurlRequest = remember { webLnurl.take() }
                    // What the scanner put on this entry's saved state on its way out.
                    val scanned by entry.savedStateHandle.getStateFlow<Destination?>(ScannerResult.KEY, null).collectAsState()
                    SendRoute(
                        source = send.source,
                        onDown = dismiss,
                        onOpenScanner = { navController.navigate(Routes.SCANNER) },
                        onOpenTransaction = { id -> navController.openTransaction(id) },
                        onOpenLightningQuestion = { navController.navigate(Routes.SEND_QUESTION) },
                        // iOS closes Send before opening the swap for an invoice (`swapAndPayLightning`), and
                        // pushes the swap over Send for an on-chain payment (`SendToSwap`).
                        onSwapAndPayInvoice = { invoice, amount ->
                            navController.navigate(SwapRoutes.payInvoice(invoice, amount)) { popUpTo(Routes.SEND) { inclusive = true } }
                        },
                        onSwapAndPayAddress = { address, amount -> navController.navigate(SwapRoutes.payAddress(address, amount)) },
                        scanned = scanned,
                        onScannedConsumed = { ScannerResult.consume(entry.savedStateHandle) },
                        lnurlRequest = lnurlRequest,
                    )
                }

                sheet(navController, Routes.MOVE) { _, dismiss ->
                    MoveScreen(
                        onDown = dismiss,
                        onSend = { navController.navigate(Routes.SEND) },
                        onReceive = { navController.navigate(Routes.RECEIVE) },
                        // The same lightning-connections card Device details opens.
                        onLightningQuestion = { navController.navigate(Routes.LIGHTNING_QUESTION) },
                        onSwap = { navController.navigate(SwapRoutes.swap()) },
                    )
                }

                swapArea(navController)

                sheet(navController, Routes.SEND_QUESTION) { _, dismiss ->
                    // `lightningsendable`: the channel chart when there is an active channel.
                    LightningSendableQuestionScreen(
                        onDown = dismiss,
                        channel = hiltViewModel<LightningQuestionViewModel>().channel.collectAsState().value,
                    )
                }

                sheet(navController, Routes.CHANNEL_CLOSED) { _, dismiss ->
                    QuestionScreen(
                        title = ChannelClosedCard.TITLE,
                        answer = channelClosedAnswer,
                        onDown = dismiss,
                    )
                }

                sheet(
                    navController,
                    Routes.TRANSACTION,
                    arguments = listOf(
                        navArgument(TransactionViewModel.ID_ARG) { type = NavType.StringType },
                        navArgument(TransactionViewModel.CONFETTI_ARG) {
                            type = NavType.BoolType
                            defaultValue = false
                        },
                    ),
                ) { _, dismiss ->
                    TransactionScreen(
                        onDown = dismiss,
                        onOpenExplorer = { txId -> navController.navigate(Routes.explorer(txId)) },
                        onOpenSwapStatus = { boltzId -> navController.navigate(SwapRoutes.status(boltzId)) },
                    )
                }

                sheet(
                    navController,
                    Routes.EXPLORER,
                    arguments = listOf(navArgument(Routes.EXPLORER_ARG) { type = NavType.StringType }),
                ) { entry, dismiss ->
                    val txId = entry.arguments?.getString(Routes.EXPLORER_ARG).orEmpty()
                    WebsiteScreen(url = explorerUrl(txId), onClose = dismiss)
                }

                sheet(navController, Routes.SCANNER) { _, dismiss ->
                    // What the camera read is parsed here, by the same entry point the paste
                    // control will feed — one parser for both, as on iOS
                    // (`AddressParsing.swift:15`) — and handed back to whoever opened the
                    // scanner via `ScannerResult`.
                    //
                    // Nothing opens the scanner yet: Send arrives with the engine (BIT-6).
                    // But the result no longer evaporates on the way out, which is the half
                    // of the seam BIT-72 deliberately left for BIT-100.
                    ScannerScreen(
                        onScanned = { scanned -> ScannerResult.handleScan(navController, scanned, network) },
                        onClose = dismiss,
                    )
                }

                settingsArea(
                    navController = navController,
                    onRemoveWallet = { removal.removeWalletTapped(RemovalOrigin.Settings) },
                    // iOS handles a first-party page's Lightning link over the browser; here Send handles it.
                    onWebsiteLnurl = { raw, source ->
                        webLnurl.post(SendLnurlRequest(raw, source))
                        navController.navigate(Routes.SEND)
                    },
                )
            }
        }
        if (logoPinned) BittrAppBarLogoOverlay(background = barPinned)
    }
    }
}

/** iOS's page number for a destination that is one of its signup pages, else null. */
private fun signupPage(route: String?): Int? = when (route) {
    Routes.SIGNUP_START -> SignupPage.START
    Routes.SIGNUP_RESTORE -> SignupPage.RESTORE
    Routes.SIGNUP_BITTR -> SignupPage.TRANSFER
    else -> null
}

/**
 * The destinations whose logo sits where the app bar's does: the signup pages, the bittr signup
 * that follows them in onboarding, Home and PIN.
 */
private val LogoBarRoutes = setOf(
    Routes.SIGNUP_START,
    Routes.SIGNUP_RESTORE,
    Routes.SIGNUP_BITTR,
    Routes.HOME,
    Routes.PIN_UNLOCK,
)

/**
 * The pages a slide between two signup destinations runs from and to, or null for any other pair.
 * The create arc is one destination on Signup1's page number; the only way from it to the bittr
 * signup is Signup7's Next, so that edge leaves from Signup7's page.
 */
private fun AnimatedContentTransitionScope<NavBackStackEntry>.signupPages(): Pair<Int, Int>? {
    val fromRoute = initialState.destination.route
    val toRoute = targetState.destination.route
    val to = signupPage(toRoute) ?: return null
    val from = when {
        fromRoute == Routes.SIGNUP_START && toRoute == Routes.SIGNUP_BITTR -> SignupPage.READY
        else -> signupPage(fromRoute) ?: return null
    }
    return from to to
}

/**
 * Where a destination sits in iOS's `CoreViewController` stack — PIN on top, Signup below it, Home
 * at the bottom — or null for one that is not in it. See [stackSlideIn].
 */
private fun stackLevel(route: String?): Int? = when (route) {
    Routes.PIN_UNLOCK -> 0
    Routes.SIGNUP_START, Routes.SIGNUP_RESTORE, Routes.SIGNUP_BITTR -> 1
    Routes.HOME -> 2
    else -> null
}

/** The stack levels a slide between two destinations runs from and to, when they differ. */
private fun AnimatedContentTransitionScope<NavBackStackEntry>.stackLevels(): Pair<Int, Int>? {
    val from = stackLevel(initialState.destination.route) ?: return null
    val to = stackLevel(targetState.destination.route) ?: return null
    return if (from == to) null else from to to
}

/**
 * iOS's page slides between the destinations it has as pages. Across the signup strip —
 * Signup1 and Restore (pages 3 and 2), Signup7 and Transfer1 (9 and 10) — sideways; up and down
 * the PIN / Signup / Home stack — unlocking, finishing onboarding, the screen lock, a wallet
 * removal — vertically, the page arriving below or above the one it replaces. Nothing, so the
 * NavHost's own transition, for any other pair.
 */
private fun AnimatedContentTransitionScope<NavBackStackEntry>.coreSlideIn(): EnterTransition? =
    signupPages()?.let { (from, to) -> pageSlideIn(from, to) }
        ?: stackLevels()?.let { (from, to) -> stackSlideIn(from, to) }

private fun AnimatedContentTransitionScope<NavBackStackEntry>.coreSlideOut(): ExitTransition? =
    signupPages()?.let { (from, to) -> pageSlideOut(from, to) }
        ?: stackLevels()?.let { (from, to) -> stackSlideOut(from, to) }

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
    onRemoveWallet: (() -> Unit)? = null,
    onWebsiteLnurl: (raw: String, source: LnurlSource.FirstPartyWeb) -> Unit = { _, _ -> },
    lightningChannel: @Composable () -> ChannelSummary? = {
        hiltViewModel<LightningQuestionViewModel>().channel.collectAsState().value
    },
    deviceViewModel: @Composable () -> DeviceViewModel = { hiltViewModel() },
) {
    // iOS's Settings pop-up (`showSettings`): a dialog destination, so Wallet or Academy stays drawn
    // underneath, dimmed, and BittrPopup springs the panel up over it. The pages it opens are page
    // sheets on top of it — `SettingsToWebsite` and `SettingsToDevice` are show segues from a view
    // controller outside any navigation stack — so closing one comes back to the pop-up, as on iOS.
    dialog(Routes.SETTINGS, dialogProperties = OverlayDialog) { entry ->
        CoveredByLaterSheets(navController, entry) {
            BittrPopup(onDismissed = { navController.popBackStack() }) { dismiss ->
                SettingsScreen(
                    onDown = dismiss,
                    onOpenWebsite = { navController.navigate(Routes.website(it)) },
                    onOpenDevice = { navController.navigate(Routes.DEVICE) },
                )
            }
        }
    }

    dialog(
        route = Routes.WEBSITE,
        arguments = listOf(navArgument(Routes.WEBSITE_ARG) { type = NavType.StringType }),
        dialogProperties = OverlayDialog,
    ) { entry ->
        // The argument is produced by `Routes.website` from an enum constant, so
        // an unrecognised value means the route was hand-built. Falling back to
        // Support rather than throwing keeps a typo out of a crash log, and the
        // support page is the safest of the three to land on by accident.
        val page = entry.arguments
            ?.getString(Routes.WEBSITE_ARG)
            ?.let { name -> WebsitePage.entries.firstOrNull { it.name == name } }
            ?: WebsitePage.Support

        // `:feature:website`'s screen, not a settings-local one. The three pages
        // here are three URLs; everything else about showing a URL — the R-11
        // hardening baseline, the navigation policy, the trust derivation — is
        // the in-app browser's job and belongs in one module (BIT-112).
        BittrSheet(onDismissed = { navController.popBackStack() }) { dismiss ->
            WebsiteScreen(url = page.url, onClose = dismiss, onLnurl = onWebsiteLnurl)
        }
    }

    dialog(Routes.DEVICE, dialogProperties = OverlayDialog) { entry ->
        val device = deviceViewModel()
        CoveredByLaterSheets(navController, entry) {
            BittrSheet(onDismissed = { navController.popBackStack() }) { dismiss ->
                DeviceScreen(
                    onDown = dismiss,
                    onOpenLightningQuestion = {
                        navController.navigate(Routes.LIGHTNING_QUESTION)
                    },
                    viewModel = device,
                    onRemoveWallet = onRemoveWallet ?: device::nodeBackedRowTapped,
                )
            }
        }
    }

    dialog(Routes.LIGHTNING_QUESTION, dialogProperties = OverlayDialog) {
        BittrSheet(onDismissed = { navController.popBackStack() }) { dismiss ->
            LightningQuestionScreen(onDown = dismiss, channel = lightningChannel())
        }
    }
}

/**
 * A pop-up or sheet that another has opened over: still drawn, as the screens under a sheet are, but
 * out of the accessibility tree until it is on top again. On iOS the presented sheet is the only
 * thing VoiceOver or a flow can reach; without this, the Settings pop-up's `header.downButton` sits
 * under Device details' own, and a flow tapping it finds two.
 */
@Composable
private fun CoveredByLaterSheets(
    navController: NavHostController,
    entry: NavBackStackEntry,
    content: @Composable () -> Unit,
) {
    val top by navController.currentBackStackEntryAsState()
    val covered = top != null && top?.id != entry.id
    Box(if (covered) Modifier.clearAndSetSemantics {} else Modifier) { content() }
}

/**
 * A destination presented as iOS's page sheet: a dialog destination, so the screen it opened over
 * stays drawn underneath, with [BittrSheet] sliding it up and, on [content]'s `dismiss`, back down
 * before the entry is popped. Covered by a later sheet, it leaves the semantics tree until it is
 * on top again.
 */
internal fun NavGraphBuilder.sheet(
    navController: NavHostController,
    route: String,
    arguments: List<NamedNavArgument> = emptyList(),
    content: @Composable (entry: NavBackStackEntry, dismiss: () -> Unit) -> Unit,
) {
    dialog(route = route, arguments = arguments, dialogProperties = OverlayDialog) { entry ->
        CoveredByLaterSheets(navController, entry) {
            BittrSheet(onDismissed = { navController.popBackStack() }) { dismiss -> content(entry, dismiss) }
        }
    }
}

/**
 * A dialog destination's window for the app's own sheets and pop-ups: full screen and edge to edge,
 * so [BittrSheet] and [BittrPopup] draw their own dim and motion over the screen underneath, and
 * with Back and outside taps left to them, so they can animate away before the entry is popped.
 */
private val OverlayDialog = DialogProperties(
    usePlatformDefaultWidth = false,
    decorFitsSystemWindows = false,
    dismissOnBackPress = false,
    dismissOnClickOutside = false,
)

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
