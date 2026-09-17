package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
    const val ACADEMY = "academy"

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
    http: HttpClient = remember { OkHttpBittrHttpClient() },
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

    // See [NotPortedDialog]. Held here rather than in a screen because it is
    // scaffolding for the port, not app behaviour, and keeping it out of the feature
    // modules is what makes it a single deletion when Wave 1 and Wave 3 finish.
    var notPorted by remember { mutableStateOf<String?>(null) }
    notPorted?.let { NotPortedDialog(screen = it, onDismiss = { notPorted = null }) }

    // `checkWalletRemoval`: a lockout to resume, or a removal left half-done.
    LaunchedEffect(Unit) { removal.checkOnLaunch() }

    WalletRemovalHost(
        coordinator = removal,
        // The erase already swaps the start destination to signup; this clears whatever
        // back stack was above it so Back cannot return to a screen of the old wallet.
        onWalletRemoved = {
            navController.navigate(Routes.SIGNUP_START) {
                popUpTo(navController.graph.id) { inclusive = true }
                launchSingleTop = true
            }
        },
    ) {
    // Read once, at launch. A start destination that followed the state would rebuild the graph
    // on every change and pop the back stack with it — creating a wallet unlocks it on the
    // Ready page, which would throw the user out of onboarding before the bittr signup. Every
    // later transition navigates explicitly: unlock, the end of onboarding or restore, removal.
    val startDestination = remember {
        when (walletState) {
            WalletState.Uninitialized -> Routes.SIGNUP_START
            WalletState.Locked -> Routes.PIN_UNLOCK
            WalletState.Ready -> Routes.HOME
        }
    }
    NavHost(
        navController = navController,
        startDestination = startDestination,
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
                onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
                onContinueToSignup = {
                    navController.navigate(Routes.SIGNUP_BITTR) {
                        popUpTo(Routes.SIGNUP_START) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.SIGNUP_BITTR) {
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
        composable(Routes.SIGNUP_RESTORE) {
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

        composable(Routes.PIN_UNLOCK) {
            UnlockScreen(
                onUnlocked = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.PIN_UNLOCK) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.HOME) {
            val profits: ProfitsViewModel = hiltViewModel()
            val profit by profits.summary.collectAsState()
            HomeScreen(
                onSettings = { navController.navigate(Routes.SETTINGS) },
                // Wave 1, landed by BIT-99. These three are the entry points
                // `bitcoin_map.yaml`, `bitcoin_value.yaml` and `academy.yaml` tap
                // from Home, and every screen behind them needs an unlocked wallet
                // and nothing else — no funds, no node — so they are live today.
                onMap = { navController.navigate(Routes.MAP) },
                onCurrency = { navController.navigate(Routes.VALUE) },
                onAcademy = { navController.navigate(Routes.ACADEMY) },
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
            )
        }

        composable(Routes.BUY) {
            val buy: BuyViewModel = hiltViewModel()
            BuyRoute(
                source = buy.source,
                onDown = { navController.popBackStack() },
                onOpenArticle = { slug -> navController.navigate(Routes.article(slug)) },
            )
        }

        composable(Routes.PROFITS) {
            val profits: ProfitsViewModel = hiltViewModel()
            val summary by profits.summary.collectAsState()
            ProfitsScreen(
                summary = summary ?: ProfitSummary(0, 0, 0, "€"),
                onDown = { navController.popBackStack() },
            )
        }

        composable(Routes.VALUE) {
            ValueScreen(
                environment = environment,
                http = http,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.MAP) {
            MapScreen(onBack = { navController.popBackStack() })
        }

        composable(Routes.ACADEMY) {
            AcademyScreen(onBack = { navController.popBackStack() })
        }

        composable(
            route = Routes.ARTICLE,
            arguments = listOf(navArgument(Routes.ARTICLE_ARG) { type = NavType.StringType }),
        ) { entry ->
            ArticleScreen(
                slug = entry.arguments?.getString(Routes.ARTICLE_ARG).orEmpty(),
                onDown = { navController.popBackStack() },
            )
        }

        composable(Routes.RECEIVE) {
            val receive: ReceiveViewModel = hiltViewModel()
            ReceiveRoute(source = receive.source, onDown = { navController.popBackStack() })
        }

        composable(Routes.SEND) { entry ->
            val send: SendViewModel = hiltViewModel()
            // Taken once, when Send opens: reopening Send must not replay a page's LNURL.
            val lnurlRequest = remember { webLnurl.take() }
            // What the scanner put on this entry's saved state on its way out.
            val scanned by entry.savedStateHandle.getStateFlow<Destination?>(ScannerResult.KEY, null).collectAsState()
            SendRoute(
                source = send.source,
                onDown = { navController.popBackStack() },
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

        composable(Routes.MOVE) {
            MoveScreen(
                onDown = { navController.popBackStack() },
                onSend = { navController.navigate(Routes.SEND) },
                onReceive = { navController.navigate(Routes.RECEIVE) },
                // The same lightning-connections card Device details opens.
                onLightningQuestion = { navController.navigate(Routes.LIGHTNING_QUESTION) },
                onSwap = { navController.navigate(SwapRoutes.swap()) },
            )
        }

        swapArea(navController)

        composable(Routes.SEND_QUESTION) {
            // `lightningsendable`: the channel chart when there is an active channel.
            LightningSendableQuestionScreen(
                onDown = { navController.popBackStack() },
                channel = hiltViewModel<LightningQuestionViewModel>().channel.collectAsState().value,
            )
        }

        composable(Routes.CHANNEL_CLOSED) {
            QuestionScreen(
                title = ChannelClosedCard.TITLE,
                answer = channelClosedAnswer,
                onDown = { navController.popBackStack() },
            )
        }

        composable(
            route = Routes.TRANSACTION,
            arguments = listOf(
                navArgument(TransactionViewModel.ID_ARG) { type = NavType.StringType },
                navArgument(TransactionViewModel.CONFETTI_ARG) {
                    type = NavType.BoolType
                    defaultValue = false
                },
            ),
        ) {
            TransactionScreen(
                onDown = { navController.popBackStack() },
                onOpenExplorer = { txId -> navController.navigate(Routes.explorer(txId)) },
                onOpenSwapStatus = { boltzId -> navController.navigate(SwapRoutes.status(boltzId)) },
            )
        }

        composable(
            route = Routes.EXPLORER,
            arguments = listOf(navArgument(Routes.EXPLORER_ARG) { type = NavType.StringType }),
        ) { entry ->
            val txId = entry.arguments?.getString(Routes.EXPLORER_ARG).orEmpty()
            WebsiteScreen(url = explorerUrl(txId), onClose = { navController.popBackStack() })
        }

        composable(Routes.SCANNER) {
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
                onClose = { navController.popBackStack() },
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
    onRemoveWallet: (() -> Unit)? = null,
    onWebsiteLnurl: (raw: String, source: LnurlSource.FirstPartyWeb) -> Unit = { _, _ -> },
    lightningChannel: @Composable () -> ChannelSummary? = {
        hiltViewModel<LightningQuestionViewModel>().channel.collectAsState().value
    },
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

        // `:feature:website`'s screen, not a settings-local one. The three pages
        // here are three URLs; everything else about showing a URL — the R-11
        // hardening baseline, the navigation policy, the trust derivation — is
        // the in-app browser's job and belongs in one module (BIT-112).
        WebsiteScreen(url = page.url, onClose = { navController.popBackStack() }, onLnurl = onWebsiteLnurl)
    }

    composable(Routes.DEVICE) {
        val device = deviceViewModel()
        DeviceScreen(
            onDown = { navController.popBackStack() },
            onOpenLightningQuestion = {
                navController.navigate(Routes.LIGHTNING_QUESTION)
            },
            viewModel = device,
            onRemoveWallet = onRemoveWallet ?: device::nodeBackedRowTapped,
        )
    }

    composable(Routes.LIGHTNING_QUESTION) {
        LightningQuestionScreen(onDown = { navController.popBackStack() }, channel = lightningChannel())
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
