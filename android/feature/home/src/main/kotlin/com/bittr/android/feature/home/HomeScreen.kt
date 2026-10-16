package com.bittr.android.feature.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrAppBarLogoHeight
import com.bittr.android.core.designsystem.BittrBottomNavBar
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrLogo
import com.bittr.android.core.designsystem.BittrNavTab
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.LocalAppBarLogoVisible
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.rememberStrokeIcon
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.BittrMark
import com.bittr.android.core.designsystem.AboveChrome
import kotlin.math.abs

/**
 * Home — `ios/bittr/Home/HomeViewController` — **in its no-funds state**.
 *
 * This is the navigational skeleton the rest of the port hangs off: the yellow header
 * with the wallet card, the three entry points on it, the Send / Receive / Buy row,
 * the empty-transactions message and the bottom bar. Built to `design/screens.jsx`
 * artboard 18 and dressed in the BIT-63 tokens.
 *
 * ### What is deliberately not drawn, and why it is not a placeholder
 *
 * The balance, the fiat conversion, the profit pill, the transaction list and the
 * sync overlay are all wallet-backed, and there is no wallet engine on Android yet —
 * BIT-6 owns it. Drawing them empty would mean a `₿ 0.00` and a live Receive button
 * on a build that cannot receive, which is the failure mode BIT-93's first constraint
 * names: it invites a deposit the app would lose.
 *
 * So the *shape* is the mock's and the *content* is honest. Every control that needs
 * the node is present, carries its Maestro id, and takes **iOS's own guard**:
 * `HomeViewController` wraps Send, Receive and the balance card in
 * `if !coreVC.walletHasSynced { showAlert(syncingwallet) }`, and
 * [HomeUiState.walletHasSynced] is false here because the claim it makes is false
 * here. When BIT-6 lands, the guard starts passing and the header
 * grows a balance block — no control on this screen moves.
 *
 * `home.headerSpinner` is the one id in `TestID.Home` with nothing behind it. It is
 * the sync spinner, and `features/settings.yaml` waits for it to *disappear*
 * (`extendedWaitUntil: notVisible`), which an absent node satisfies vacuously and
 * correctly. Composing a spinner that never spins would be worse than composing
 * nothing.
 *
 * ### The callbacks
 *
 * Destinations that exist are navigated to; destinations that are still someone
 * else's Wave 1, 2 or 3 issue are reported through the caller's callback rather than
 * being silently dead. See `BittrNavHost` for which is which.
 */
@Composable
fun HomeScreen(
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
    onMap: () -> Unit = {},
    onCurrency: () -> Unit = {},
    onSend: () -> Unit = {},
    onReceive: () -> Unit = {},
    onBuy: () -> Unit = {},
    onBalanceDetails: () -> Unit = {},
    onAcademy: () -> Unit = {},
    onTransaction: (String) -> Unit = {},
    profitPill: ProfitPill? = null,
    onProfit: () -> Unit = {},
    /** The week's prices for the value card, oldest first — `graphPoints`. Null until loaded. */
    valueWeek: List<Double>? = null,
    /** Draw the menu bar. False where a host draws one bar over Home and Academy both. */
    navBar: Boolean = true,
    /** Room left at the end of the list for a menu bar drawn over it by the host. */
    contentBottomPadding: Dp = 0.dp,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val alert by viewModel.currentAlert.collectAsState()

    HomeScreen(
        state = state,
        alert = alert,
        onDismissAlert = viewModel::dismissAlert,
        onSyncingWallet = { viewModel.showAlert(SYNCING_ALERT) },
        onConversionFailed = { viewModel.showAlert(CONVERSION_ALERT) },
        onSettings = onSettings,
        onMap = onMap,
        onCurrency = onCurrency,
        onSend = onSend,
        onReceive = onReceive,
        onBuy = onBuy,
        onBalanceDetails = onBalanceDetails,
        onAcademy = onAcademy,
        onTransaction = onTransaction,
        profitPill = profitPill,
        onProfit = onProfit,
        valueWeek = valueWeek,
        navBar = navBar,
        contentBottomPadding = contentBottomPadding,
        onRefresh = viewModel::refresh,
        modifier = modifier,
    )
}

/**
 * The stateless half, so previews and the screenshot test can render Home without a
 * Hilt graph — and so the synced state is one argument away rather than a refactor.
 *
 * @param onSyncingWallet raise the `syncingwallet` alert. Reached whenever the user
 *   taps a control iOS gates on `walletHasSynced` while the wallet has not synced,
 *   which today is always.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeScreen(
    state: HomeUiState,
    alert: HomeAlert?,
    onDismissAlert: () -> Unit,
    onSyncingWallet: () -> Unit,
    onSettings: () -> Unit,
    onMap: () -> Unit,
    onCurrency: () -> Unit,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onBuy: () -> Unit,
    onBalanceDetails: () -> Unit,
    onAcademy: () -> Unit,
    modifier: Modifier = Modifier,
    onTransaction: (String) -> Unit = {},
    profitPill: ProfitPill? = null,
    onProfit: () -> Unit = {},
    valueWeek: List<Double>? = null,
    navBar: Boolean = true,
    contentBottomPadding: Dp = 0.dp,
    onRefresh: () -> Unit = {},
    /** Raise the `conversionfail` alert, when the sync status is tapped after a failed rate fetch. */
    onConversionFailed: () -> Unit = {},
) {
    alert?.let {
        BittrAlertDialog(
            title = it.title,
            message = it.message,
            confirmLabel = HomeStrings.OKAY,
            onConfirm = onDismissAlert,
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }

    // The iOS guard, in one place: `if !coreVC.walletHasSynced { showAlert(...);
    // return }`. Wrapping the actions here rather than inside each button is what
    // makes BIT-6's change to `walletHasSynced` enough on its own — no button has to
    // be revisited.
    fun guarded(action: () -> Unit): () -> Unit =
        { if (state.walletHasSynced) action() else onSyncingWallet() }

    // `syncingStatusTapped`: the balance screen once synced — or why the rates may be out of date,
    // after a failed fetch — and the sync overlay before.
    var syncStatusVisible by remember { mutableStateOf(false) }

    // `ReloadWallet.swift`: pulling Home down past a threshold resyncs the wallet. Everything
    // above the tab bar is one list — the header, then the history — so the pull works from the
    // header as well as from the rows, as `remove_wallet.yaml`'s swipe from 30% to 90% needs.
    val pullState = rememberPullToRefreshState()

    Box(modifier = modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BittrTheme.colors.homeBackground),
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .pullToRefresh(
                    state = pullState,
                    // `home.headerSpinner` is the refresh indicator, as on iOS; the pull
                    // indicator only follows the finger and goes away on release.
                    isRefreshing = false,
                    enabled = state.canRefresh,
                    threshold = PULL_THRESHOLD,
                    onRefresh = onRefresh,
                ),
        ) {
            LazyColumn(
                contentPadding = PaddingValues(bottom = contentBottomPadding),
                modifier = Modifier.fillMaxSize(),
            ) {
                item {
                    HomeHeader(
                        showSyncSpinner = state.showSyncSpinner,
                        showConversionProblem = state.conversionFailed,
                        balanceSats = state.balanceSats,
                        balanceFiat = state.balanceFiat,
                        onMap = onMap,
                        onCurrency = onCurrency,
                        onSend = guarded(onSend),
                        onReceive = guarded(onReceive),
                        onBuy = onBuy,
                        onSyncStatus = {
                            when {
                                !state.walletHasSynced -> syncStatusVisible = true
                                state.conversionFailed -> onConversionFailed()
                                else -> onBalanceDetails()
                            }
                        },
                        onBalanceCard = guarded(onBalanceDetails),
                        profitPill = profitPill,
                        onProfit = onProfit,
                        valueWeek = valueWeek,
                    )
                }

                if (state.history.isNotEmpty()) {
                    historyItems(rows = state.history, onTransaction = onTransaction)
                } else {
                    item {
                        Box(
                            // `noTransactionsLabel`, which iOS shows when the history is empty: 30
                            // under the curve and 30 from the sides, Gilroy Regular 16 at 1.2.
                            contentAlignment = Alignment.TopCenter,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 30.dp),
                        ) {
                            Text(
                                text = buildAnnotatedString {
                                    append(HomeStrings.NO_TRANSACTIONS_1)
                                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                                        append(HomeStrings.BUY)
                                    }
                                    append(HomeStrings.NO_TRANSACTIONS_2)
                                },
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 19.2.sp),
                                color = BittrTheme.colors.noTransactions,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }

            PullToRefreshDefaults.Indicator(
                state = pullState,
                isRefreshing = false,
                maxDistance = PULL_THRESHOLD,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding(),
            )
        }

        if (navBar) BittrBottomNavBar(
            // Already here. iOS's wallet button re-selects Home rather than pushing
            // another copy of it, so this is a no-op rather than a navigation.
            onWallet = {},
            onAcademy = onAcademy,
            onSettings = onSettings,
            selected = BittrNavTab.Wallet,
            walletTestTag = TestID.Nav.walletButton,
            academyTestTag = TestID.Nav.academyButton,
            settingsTestTag = TestID.Nav.settingsButton,
            // Clear of the system's navigation bar by more than the plates' shadow, which the bar's
            // scrim would otherwise cover.
            modifier = Modifier
                .navigationBarsPadding()
                .padding(bottom = 20.dp),
        )
    }
    // Over the menu bar, which the screen around Home draws after it — as iOS draws the sync view.
    if (syncStatusVisible) AboveChrome { SyncStatusSheet(syncProgress(state), onClose = { syncStatusVisible = false }) }
    }
}

/**
 * The yellow block — `HomeHeaderTableViewCell` — as its storyboard lays it out.
 *
 * Under the logo's 50 and 25 more (`balanceCardTop`, the safe area plus 75), `balanceCard`: 15 from
 * the screen's sides, 320 tall whatever the balance, 13 pt corners and `setShadow()`. Then, 12
 * below, the value and map cards side by side, 120 tall and 12 apart; 25 below those the block
 * ends, and `bottomCurve` hangs 10 under it.
 *
 * The canvas colour is drawn under the status bar and the content inset below it — the same rule
 * [com.bittr.android.core.designsystem.BittrCanvas] follows.
 */
@Composable
private fun HomeHeader(
    showSyncSpinner: Boolean,
    balanceSats: Long?,
    showConversionProblem: Boolean = false,
    balanceFiat: String? = null,
    onMap: () -> Unit,
    onCurrency: () -> Unit,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onBuy: () -> Unit,
    onSyncStatus: () -> Unit,
    onBalanceCard: () -> Unit = onSyncStatus,
    profitPill: ProfitPill? = null,
    onProfit: () -> Unit = {},
    valueWeek: List<Double>? = null,
) {
    val colors = BittrTheme.colors
    CompositionLocalProvider(LocalContentColor provides colors.onCanvas) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.homeHeader)
                    .statusBarsPadding()
                    .padding(start = 15.dp, end = 15.dp, bottom = 25.dp),
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                ) {
                    BittrLogo(
                        height = BittrAppBarLogoHeight,
                        modifier = Modifier.alpha(if (LocalAppBarLogoVisible.current) 1f else 0f),
                    )
                }
                CanvasSpacer(25.dp)
                BalanceCard(
                    showSyncSpinner = showSyncSpinner,
                    showConversionProblem = showConversionProblem,
                    // iOS shows the cached balance, or 0, until the first reading replaces it; the
                    // card is never without one.
                    balanceSats = balanceSats ?: 0L,
                    balanceFiat = balanceFiat,
                    onSend = onSend,
                    onReceive = onReceive,
                    onBuy = onBuy,
                    onSyncStatus = onSyncStatus,
                    onBalanceCard = onBalanceCard,
                    profitPill = profitPill ?: ProfitPill(text = "0 %", isLoss = false),
                    onProfit = onProfit,
                )
                CanvasSpacer(12.dp)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(SmallCardHeight),
                ) {
                    ValueCard(week = valueWeek, onClick = onCurrency, modifier = Modifier.weight(1f))
                    MapCard(onClick = onMap, modifier = Modifier.weight(1f))
                }
            }
            HeaderCurve(color = colors.homeHeader)
        }
    }
}

/**
 * `balanceCard`: the header row, the balance centred 31 above the card's middle with its fiat
 * conversion and profit pill 18 under it, and the Send / Receive / Buy row 10 from its bottom.
 *
 * `balanceCardButton` covers the whole card and `syncButton` the header row, as on iOS. Both are
 * transparent layers drawn under the labels rather than over them: a sibling that covers a node
 * entirely takes it out of the accessibility tree, which is how `home.balanceCardButton` once
 * went missing. The labels take no touches, so taps reach the layers through them.
 */
@Composable
private fun BalanceCard(
    showSyncSpinner: Boolean,
    showConversionProblem: Boolean,
    balanceSats: Long,
    balanceFiat: String?,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onBuy: () -> Unit,
    onSyncStatus: () -> Unit,
    onBalanceCard: () -> Unit,
    profitPill: ProfitPill,
    onProfit: () -> Unit,
) {
    val colors = BittrTheme.colors
    val dark = BittrTheme.isDark
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(320.dp)
            .iosShadow(IosCardShape)
            .clip(IosCardShape)
            .background(colors.homeHeader),
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable(onClick = onBalanceCard)
                .testTag(TestID.Home.balanceCardButton),
        )

        // `Header View`, 20 from the card's top and leading edge, and `syncButton` 10 around it.
        Box(modifier = Modifier.padding(start = 10.dp, top = 10.dp)) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable(onClick = onSyncStatus)
                    .testTag(TestID.Home.syncStatusButton),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(10.dp),
            ) {
                Image(
                    painter = painterResource(if (dark) R.drawable.home_piggy_yellow else R.drawable.home_piggy_white),
                    contentDescription = null,
                    modifier = Modifier
                        .offset(y = (-0.5).dp)
                        .size(18.dp),
                )
                Text(
                    text = HomeStrings.YOUR_WALLET,
                    style = CardTitle,
                    color = colors.homeCardTitle,
                    modifier = Modifier
                        .padding(start = 10.dp)
                        .testTag(TestID.Home.headerLabel),
                )
                // `headerSpinner` — spinning until `finalizeSync()`, 12 after the label. Composed only
                // while it spins, so a flow waiting for it to be not visible is waiting for the sync,
                // not for an animation to be hidden.
                if (showSyncSpinner) {
                    BittrSpinner(
                        color = colors.homeCardTitle,
                        strokeWidth = 2.dp,
                        modifier = Modifier
                            .padding(start = 12.dp)
                            .size(18.dp)
                            .testTag(TestID.Home.headerSpinner),
                    )
                } else if (showConversionProblem) {
                    // `headerProblemImage`, where the spinner was: the conversion rates could not be fetched.
                    ConversionProblemIcon(
                        modifier = Modifier
                            .padding(start = 12.dp)
                            .size(18.dp),
                    )
                }
            }
        }
        // `headerDetailsImage`, 20 from the card's trailing edge, level with the piggy.
        Image(
            painter = painterResource(if (dark) R.drawable.home_details_yellow else R.drawable.home_details_white),
            contentDescription = null,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 19.5.dp, end = 20.dp)
                .size(18.dp),
        )

        // `balanceView`, 40 tall and centred 31 above the card's middle (2 left of it), and the
        // conversion row 18 under it.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 320.dp / 2 - 31.dp - 20.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(40.dp)
                    .offset(x = (-2).dp),
            ) {
                BalanceLabel(balance = balanceText(balanceSats), dimmedColor = colors.balanceDimmed)
            }
            // 18 on iOS to the 20 pt conversion row; here the row is the 26 dp pill's height, which
            // overhangs that by 3 each way, and `profitButton`'s 10 around it.
            CanvasSpacer(18.dp - 3.dp - 10.dp)
            ConversionRow(fiat = balanceFiat, pill = profitPill, onProfit = onProfit)
        }

        // `Buttons View`: 10 from the card's sides and bottom, 48 tall, the plates 10 apart — Send
        // 0.32 and Buy 0.3 of the row less 7, Receive the rest.
        BoxWithConstraints(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(10.dp)
                .fillMaxWidth()
                .height(48.dp),
        ) {
            val sendWidth = maxWidth * 0.32f - 7.dp
            val buyWidth = maxWidth * 0.3f - 7.dp
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
                ActionButton(
                    label = HomeStrings.SEND,
                    icon = ActionIcon.Send,
                    onClick = onSend,
                    testTag = TestID.Home.sendButton,
                    modifier = Modifier.width(sendWidth),
                )
                ActionButton(
                    label = HomeStrings.RECEIVE,
                    icon = ActionIcon.Receive,
                    onClick = onReceive,
                    testTag = TestID.Home.receiveButton,
                    modifier = Modifier.weight(1f),
                )
                // Buy is the one action iOS does *not* gate on the sync — it segues straight to
                // BuyViewController.
                ActionButton(
                    label = HomeStrings.BUY,
                    icon = ActionIcon.Buy,
                    onClick = onBuy,
                    testTag = TestID.Home.buyButton,
                    modifier = Modifier.width(buyWidth),
                )
            }
        }
    }
}

/**
 * `Conversion Box`: the balance in the display currency in Gilroy Bold 22, the balance's dimmed
 * colour, and 12 after it the profit pill — `profitView`, 26 tall with 13 pt corners, the arrow 13
 * in and the percentage in Gilroy Regular 14 5 after it, 13 from the end. `profitButton` reaches
 * 10 past the row on every side.
 */
@Composable
private fun ConversionRow(fiat: String?, pill: ProfitPill, onProfit: () -> Unit) {
    val colors = BittrTheme.colors
    Box {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable(onClick = onProfit)
                .testTag(TestID.Home.profitButton),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(10.dp),
        ) {
            if (fiat != null) {
                Text(
                    text = fiat,
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 22.sp, lineHeight = 22.sp),
                    color = colors.balanceDimmed,
                    modifier = Modifier.padding(end = 12.dp),
                )
            }
            ChangePill(
                text = pill.text,
                isLoss = pill.isLoss,
                height = 26.dp,
                inset = 13.dp,
                gap = 5.dp,
                fontSize = 14.sp,
                textTag = TestID.Home.profitLabel,
                modifier = Modifier.offset(y = (-1.5).dp),
            )
        }
    }
}

/**
 * The green (or red) pill with its arrow — `profitView` on the balance card and
 * `conversionProfitView` on the value card, which differ only in size. `profitbackground0.8` and
 * `profittext`, or the loss pair.
 */
@Composable
private fun ChangePill(
    text: String,
    isLoss: Boolean,
    height: Dp,
    inset: Dp,
    gap: Dp,
    fontSize: TextUnit,
    modifier: Modifier = Modifier,
    textTag: String? = null,
) {
    val colors = BittrTheme.colors
    val foreground = if (isLoss) colors.loss else colors.profit
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .height(height)
            .background(if (isLoss) colors.lossBgMuted else colors.profitBgMuted, RoundedCornerShape(height / 2))
            .padding(horizontal = inset),
    ) {
        Text(
            text = if (isLoss) "↓" else "↑",
            color = foreground,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize, lineHeight = fontSize),
        )
        Text(
            text = text,
            color = foreground,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize, lineHeight = fontSize),
            modifier = Modifier
                .padding(start = gap)
                .offset(y = 1.dp)
                .then(textTag?.let { Modifier.testTag(it) } ?: Modifier),
        )
    }
}

/** The title on the balance, value and map cards: Gilroy Bold 18. */
private val CardTitle: TextStyle
    @Composable get() = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp, lineHeight = 18.sp)

/** `conversionCard` and `mapCard`'s height. */
private val SmallCardHeight = 120.dp

/**
 * `conversionCard` — "value": the exchange icon and title, the week's change in a pill 13 from the
 * trailing edge, and under the title the week's price as a white line, 27 in from the sides, 16
 * below the title and 21 above the card's bottom, 4 pt wide. Tapping it opens the value screen.
 */
@Composable
private fun ValueCard(week: List<Double>?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = BittrTheme.colors
    val dark = BittrTheme.isDark
    SmallCard(onClick = onClick, testTag = TestID.Home.currencyButton, modifier = modifier) {
        SmallCardTitle(
            icon = if (dark) R.drawable.home_value_yellow else R.drawable.home_value_white,
            title = HomeStrings.VALUE,
        )
        weekChange(week)?.let { (text, isLoss) ->
            ChangePill(
                text = text,
                isLoss = isLoss,
                height = 22.dp,
                inset = 10.dp,
                gap = 4.dp,
                fontSize = 12.sp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 10.dp, end = 13.dp),
            )
        }
        if (week != null && week.size >= 2) {
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 27.dp, end = 27.dp, top = 30.dp + 16.dp, bottom = 21.dp),
            ) {
                val low = week.min()
                val high = week.max()
                val span = (high - low).takeIf { it > 0 } ?: 1.0
                val stepX = size.width / (week.size - 1)
                val points = week.mapIndexed { index, price ->
                    Offset(index * stepX, (size.height * (1 - (price - low) / span)).toFloat())
                }
                // Smooth through the midpoints, as the value screen's graph is drawn.
                val path = Path().apply {
                    moveTo(points.first().x, points.first().y)
                    for (index in 1 until points.size) {
                        val previous = points[index - 1]
                        val current = points[index]
                        val mid = Offset((previous.x + current.x) / 2, (previous.y + current.y) / 2)
                        quadraticTo(previous.x, previous.y, mid.x, mid.y)
                    }
                    lineTo(points.last().x, points.last().y)
                }
                // GraphView's shadow: black under the line, 9 down and blurred. Lighter than a straight
                // port of iOS's 40 % reads here (Tom, 2026-09-29), so a quarter.
                drawIntoCanvas { canvas ->
                    val shadow = android.graphics.Paint().apply {
                        isAntiAlias = true
                        style = android.graphics.Paint.Style.STROKE
                        strokeWidth = 4.dp.toPx()
                        strokeCap = android.graphics.Paint.Cap.ROUND
                        strokeJoin = android.graphics.Paint.Join.ROUND
                        color = android.graphics.Color.BLACK
                        alpha = (GraphShadowAlpha * 255).toInt()
                        maskFilter = android.graphics.BlurMaskFilter(12.dp.toPx(), android.graphics.BlurMaskFilter.Blur.NORMAL)
                    }
                    canvas.save()
                    canvas.translate(0f, 9.dp.toPx())
                    canvas.nativeCanvas.drawPath(path.asAndroidPath(), shadow)
                    canvas.restore()
                }
                drawPath(
                    path = path,
                    color = Color.White,
                    style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                )
            }
        }
    }
}

/** How dark the value line's shadow is. */
private const val GraphShadowAlpha = 0.25f

/**
 * The week's change as `updateGraphProfit` writes it — `Int(profit)`, so truncated — and whether it
 * is a loss.
 */
private fun weekChange(week: List<Double>?): Pair<String, Boolean>? {
    val first = week?.firstOrNull()?.takeIf { it > 0 } ?: return null
    val profit = ((week.last() - first) / first * 100).toInt()
    return "${kotlin.math.abs(profit)} %" to (week.last() < first && profit != 0)
}

/**
 * `mapCard` — "map": the map icon and title, iOS's static map of Zürich 41 from the top and 12 in
 * from the other sides with 8 pt corners (at 60 % in dark, on its dark variant), and the bitcoin
 * pin over it, 36 pt, 30 from the top and 40 from the trailing edge, with its own shadow. Tapping
 * it opens the map.
 */
@Composable
private fun MapCard(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val dark = BittrTheme.isDark
    SmallCard(onClick = onClick, testTag = TestID.Home.mapButton, modifier = modifier) {
        SmallCardTitle(
            icon = if (dark) R.drawable.home_map_yellow else R.drawable.home_map_white,
            title = HomeStrings.MAP,
        )
        Image(
            painter = painterResource(if (dark) R.drawable.home_map_zurich_dark else R.drawable.home_map_zurich),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            alpha = if (dark) 0.6f else 1f,
            modifier = Modifier
                .fillMaxSize()
                .padding(start = 12.dp, end = 12.dp, top = 41.dp, bottom = 12.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        // The pin's shadow: black at 30 %, 5 down, radius 3 — its own silhouette, blurred.
        Image(
            painter = painterResource(R.drawable.home_map_pin),
            contentDescription = null,
            colorFilter = ColorFilter.tint(Color.Black),
            alpha = 0.3f,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 30.dp + 5.dp, end = 40.dp)
                .size(36.dp)
                .blur(3.dp, BlurredEdgeTreatment.Unbounded),
        )
        Image(
            painter = painterResource(R.drawable.home_map_pin),
            contentDescription = null,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 30.dp, end = 40.dp)
                .size(36.dp),
        )
    }
}

/** A value or map card: 120 tall, `yelloworblue3` with 13 pt corners and `setShadow()`. */
@Composable
private fun SmallCard(
    onClick: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxHeight()
            .iosShadow(IosCardShape)
            .clip(IosCardShape)
            .background(BittrTheme.colors.homeHeader)
            .clickable(onClick = onClick)
            .testTag(testTag),
        content = content,
    )
}

/** The 15 pt icon 15 in and 13 down, and the title in Gilroy Bold 18 10 after it. */
@Composable
private fun SmallCardTitle(icon: Int, title: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(start = 15.dp, top = 13.dp),
    ) {
        Image(painter = painterResource(icon), contentDescription = null, modifier = Modifier.size(15.dp))
        Text(
            text = title,
            style = CardTitle,
            color = BittrTheme.colors.homeCardTitle,
            modifier = Modifier
                .padding(start = 10.dp)
                .offset(y = 0.5.dp),
        )
    }
}

/**
 * `bottomCurve`: the yellow block's edge, 10 tall — iOS's `BottomCurveView`, its sides 0.15 of the
 * height down and its middle sagging towards a control point 1.2 of it down.
 */
@Composable
private fun HeaderCurve(color: Color) {
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(10.dp),
    ) {
        val edge = size.height * 0.15f
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width, edge)
            quadraticTo(size.width / 2, size.height * 1.2f, 0f, edge)
            close()
        }
        drawPath(path, color)
    }
}

/**
 * The balance — `updateBalanceLabel`: iOS's bitcoin sign as an image, 0.8 of the label's height —
 * the attributed text's ascender to descender, which for Gilroy is the font size — and 6 before it (at 18 % below one bitcoin, 47 % in dark), then the figure in Gilroy Bold up to 40,
 * shrunk to fit a width of the screen less 150, never under 16.
 */
@Composable
private fun BalanceLabel(balance: BalanceText, dimmedColor: Color) {
    val dark = BittrTheme.isDark
    val maxWidth = LocalConfiguration.current.screenWidthDp.dp - 150.dp
    var fontSize by remember(balance) { mutableStateOf(BALANCE_FONT_SIZE) }
    val wholeBitcoin = balance.dimmed.isEmpty()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(
            painter = painterResource(if (dark) R.drawable.home_bitcoin_sign_white else R.drawable.home_bitcoin_sign),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            alpha = if (wholeBitcoin) 1f else if (dark) 0.47f else 0.18f,
            modifier = Modifier
                .offset(y = (-2.5).dp)
                .size(with(LocalDensity.current) { fontSize.toDp() } * 0.8f),
        )
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = dimmedColor)) { append(balance.dimmed.removePrefix(BITCOIN_SIGN)) }
                append(balance.filled.removePrefix(BITCOIN_SIGN))
            },
            style = MaterialTheme.typography.titleMedium.copy(
                fontSize = fontSize,
                lineHeight = fontSize * LINE_HEIGHT_RATIO,
            ),
            color = BittrTheme.colors.onCanvas,
            maxLines = 1,
            softWrap = false,
            onTextLayout = { layout ->
                if (layout.didOverflowWidth && fontSize > BALANCE_MIN_FONT_SIZE) {
                    fontSize = maxOf(BALANCE_MIN_FONT_SIZE.value, fontSize.value - 2f).sp
                }
            },
            modifier = Modifier
                .padding(start = 6.dp)
                .widthIn(max = maxWidth)
                .testTag(TestID.Home.balanceLabel),
        )
    }
}

private const val BITCOIN_SIGN = "₿ "
private val BALANCE_FONT_SIZE = 40.sp
private val BALANCE_MIN_FONT_SIZE = 16.sp

/** How far Home is pulled before it refreshes — iOS reacts past 200 pt of overscroll. */
private val PULL_THRESHOLD = 120.dp
private const val LINE_HEIGHT_RATIO = 1.2f

/** The three SF Symbols on the action plates. */
private enum class ActionIcon { Send, Receive, Buy }

/**
 * One of the three plates in the card — `sendView` / `receiveView` / `buyView`: `white0.7orblue2`
 * with 8 pt corners and `setShadow()`; the brand-yellow symbol, 20 pt, and 9 after it the label in
 * Gilroy Bold 15, together centred 1 left of the plate's middle.
 */
@Composable
private fun ActionButton(
    label: String,
    icon: ActionIcon,
    onClick: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally),
        modifier = modifier
            .fillMaxHeight()
            .iosShadow(ActionShape)
            .clip(ActionShape)
            .background(colors.homeAction)
            .clickable(onClick = onClick)
            .testTag(testTag)
            .offset(x = (-1).dp),
    ) {
        ActionSymbol(icon = icon, color = colors.brandFixed)
        Text(
            text = label,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp, lineHeight = 15.sp),
            color = colors.onCanvas,
            modifier = Modifier.offset(y = 1.dp),
        )
    }
}

private val ActionShape = RoundedCornerShape(8.dp)

/**
 * `arrow.up.square.fill`, `arrow.down.square.fill` and `creditcard.fill`, drawn: a filled shape
 * in [color] with its arrow or stripe cut out of it, showing the plate beneath.
 */
@Composable
private fun ActionSymbol(icon: ActionIcon, color: Color) {
    Canvas(
        modifier = Modifier
            .size(20.dp)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        val u = size.width / 20f
        when (icon) {
            ActionIcon.Send, ActionIcon.Receive -> {
                // A 17 pt rounded square, as the symbol renders at this size.
                val side = 17f * u
                val topLeft = Offset((size.width - side) / 2, (size.height - side) / 2)
                drawRoundRect(color, topLeft, Size(side, side), CornerRadius(3.5f * u))
                val cx = size.width / 2
                val top = topLeft.y + 4f * u
                val bottom = topLeft.y + side - 4f * u
                val stroke = Stroke(width = 1.8f * u, cap = StrokeCap.Round, join = StrokeJoin.Round)
                val arrow = Path().apply {
                    if (icon == ActionIcon.Send) {
                        moveTo(cx, bottom); lineTo(cx, top)
                        moveTo(cx - 4f * u, top + 4f * u); lineTo(cx, top); lineTo(cx + 4f * u, top + 4f * u)
                    } else {
                        moveTo(cx, top); lineTo(cx, bottom)
                        moveTo(cx - 4f * u, bottom - 4f * u); lineTo(cx, bottom); lineTo(cx + 4f * u, bottom - 4f * u)
                    }
                }
                drawPath(arrow, Color.Black, style = stroke, blendMode = BlendMode.Clear)
            }
            ActionIcon.Buy -> {
                // A 20 × 16 card with its magnetic stripe and a short line cut out.
                val cardHeight = 15f * u
                val topLeft = Offset(0f, (size.height - cardHeight) / 2)
                drawRoundRect(color, topLeft, Size(size.width, cardHeight), CornerRadius(2.5f * u))
                drawRect(
                    Color.Black,
                    topLeft = Offset(0f, topLeft.y + 3.5f * u),
                    size = Size(size.width, 2.5f * u),
                    blendMode = BlendMode.Clear,
                )
                drawRoundRect(
                    Color.Black,
                    topLeft = Offset(3f * u, topLeft.y + 10f * u),
                    size = Size(5f * u, 1.8f * u),
                    cornerRadius = CornerRadius(0.9f * u),
                    blendMode = BlendMode.Clear,
                )
            }
        }
    }
}

/**
 * The history table — `HistoryTable.swift`. Each row is a card with the day in a chip,
 * the bolt for Lightning, and the sats and fiat figures on the right; the year sits above
 * the first row of a new year.
 *
 * The tap target is a transparent layer over the card rather than a clickable card, the
 * same arrangement iOS has (`transactionButton` over the cell). A clickable parent merges
 * its children's semantics, which would swallow `history.transactionAmountN` — the label
 * the flows copy the top row's amount from.
 */
private fun LazyListScope.historyItems(rows: List<HistoryRow>, onTransaction: (String) -> Unit) {
    // `HistoryCell`: 75 tall, the 60 pt card 15 in and 7.5 from the row's top and bottom; a row that
    // starts a new year is 102, the year 13 above its card.
    itemsIndexed(rows) { position, row ->
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(
                start = 15.dp,
                end = 15.dp,
                top = if (position == 0) BittrTokens.Spacing.md else 7.5.dp,
                bottom = if (position == rows.lastIndex) BittrTokens.Spacing.md else 7.5.dp,
            ),
        ) {
            row.year?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 14.sp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = 6.dp, bottom = 13.dp),
                )
            }
            HistoryCard(row = row, position = position, onClick = { onTransaction(row.id) })
        }
    }
}

/**
 * `HistoryTableViewCell`'s card: 60 tall, `whiteorblue2` with 13 corners and its own soft shadow
 * (black at 5 %, 8 down, 12 blur). `dateView` 10 in — `grey1orblue3`, 7 corners, 40 tall, the
 * Gilroy-Regular 14 day 10 in from its sides — and 15 after it the amount in Gilroy-Bold 16 over its
 * fiat value in Regular 14, 5 apart. At the end, 10 in: the swap or bolt icon in its 23 pt slot, and
 * for a bittr purchase the bittr mark and, 10 after it, the gain in its 40 pt chip.
 *
 * The tap target is a transparent layer under the content rather than a clickable card, as iOS has
 * `transactionButton` over the cell: a clickable parent merges its children's semantics, which
 * would swallow `history.transactionAmountN`, the label the flows copy the top row's amount from.
 */
@Composable
private fun HistoryCard(row: HistoryRow, position: Int, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    val ink = MaterialTheme.colorScheme.onSurface
    val figureColor = if (row.unconfirmed) colors.unconfirmed else ink
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(60.dp)
            .dropShadow(
                HistoryCardShape,
                Shadow(radius = 20.dp, color = Color.Black, offset = DpOffset(0.dp, 8.dp), alpha = 0.05f),
            )
            .background(MaterialTheme.colorScheme.surfaceContainer, HistoryCardShape),
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(HistoryCardShape)
                .clickable(onClick = onClick)
                .testTag(TestID.History.transactionButtonAt(position)),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 10.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(40.dp)
                    .widthIn(min = 40.dp)
                    .background(colors.placeIconBox, RoundedCornerShape(7.dp))
                    .padding(horizontal = 10.dp),
            ) {
                Text(
                    text = row.day,
                    style = HistorySmall,
                    color = ink,
                    modifier = Modifier.offset(y = 1.dp),
                )
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 15.dp, end = 15.dp),
            ) {
                Text(
                    text = row.sats,
                    style = MaterialTheme.typography.labelLarge.copy(lineHeight = 16.sp),
                    color = figureColor,
                    maxLines = 1,
                    modifier = Modifier.testTag(TestID.History.transactionAmountAt(position)),
                )
                row.fiat?.let {
                    Text(
                        text = it,
                        style = HistorySmall,
                        color = figureColor,
                        maxLines = 1,
                        modifier = Modifier.padding(top = 5.dp),
                    )
                }
            }
            row.swap?.let { swap ->
                // `swapImage`: blue once complete, grey while pending, with a row-indexed id.
                val complete = swap == HistorySwap.Complete
                // iOS's own `iconswapblue` / `iconswapgrey`, the same in both schemes.
                Image(
                    painter = painterResource(if (complete) R.drawable.history_swap_complete else R.drawable.history_swap_pending),
                    contentDescription = if (complete) "Swap complete" else "Swap pending",
                    modifier = Modifier
                        .padding(end = 5.dp)
                        .size(18.dp)
                        .testTag(if (complete) TestID.History.swapCompleteAt(position) else TestID.History.swapPendingAt(position)),
                )
            }
            if (row.isLightning) {
                // `bolt.fill` in yellow, 5 from its slot's end.
                Image(
                    imageVector = rememberFillIcon(BittrIconPaths.BOLT, colors.brandFixed),
                    contentDescription = "Instant",
                    modifier = Modifier
                        .padding(end = 5.dp)
                        .size(18.dp),
                )
            }
            row.gainPercent?.let { gain ->
                val isLoss = gain < 0
                val foreground = if (isLoss) colors.loss else colors.profit
                BittrMark(
                    size = 18.dp,
                    ink = ink,
                    arc = colors.brandFixed,
                    modifier = Modifier.padding(start = 1.dp, end = 10.dp),
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .height(40.dp)
                        .widthIn(min = 40.dp)
                        .background(if (isLoss) colors.lossBg else colors.profitBg, RoundedCornerShape(7.dp))
                        .padding(horizontal = 12.dp),
                ) {
                    Text(if (isLoss) "↓" else "↑", style = HistorySmall, color = foreground)
                    Text(
                        "${abs(gain)} %".let { if (isLoss) "- $it" else it },
                        style = HistorySmall,
                        color = foreground,
                        modifier = Modifier
                            .padding(start = 7.dp)
                            .offset(y = 1.dp),
                    )
                }
            }
        }
    }
}

private val HistoryCardShape = RoundedCornerShape(13.dp)

/** Gilroy-Regular 14 at its own height, as the cell's small labels are. */
private val HistorySmall: TextStyle
    @Composable get() = MaterialTheme.typography.bodyMedium.copy(lineHeight = 14.sp)


private val SYNCING_ALERT = HomeAlert(
    title = HomeStrings.SYNCING_WALLET,
    message = HomeStrings.SYNCING_WALLET_2,
)

/** `syncingStatusTapped` after a failed conversion-rate fetch. */
private val CONVERSION_ALERT = HomeAlert(
    title = HomeStrings.OOPS,
    message = HomeStrings.CONVERSION_FAIL,
)

/**
 * iOS's `exclamationmark.circle` in system red: a ring with an exclamation mark, drawn rather
 * than shipped as a symbol Android does not have.
 */
@Composable
private fun ConversionProblemIcon(modifier: Modifier = Modifier) {
    // The theme's `error` is iOS's `systemRed` (`Red2`), the storyboard's tint for this image.
    val red = MaterialTheme.colorScheme.error
    Canvas(modifier = modifier) {
        val unit = size.minDimension / 18f
        val stroke = 1.6f * unit
        drawCircle(
            color = red,
            radius = (size.minDimension - stroke) / 2f,
            style = Stroke(width = stroke),
        )
        drawLine(
            color = red,
            start = Offset(center.x, 4.8f * unit),
            end = Offset(center.x, 10.4f * unit),
            strokeWidth = 1.8f * unit,
            cap = StrokeCap.Round,
        )
        drawCircle(color = red, radius = 1.15f * unit, center = Offset(center.x, 13.2f * unit))
    }
}


@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun HomeScreenPreview() {
    BittrTheme {
        HomeNoFunds()
    }
}

/**
 * Home exactly as this build renders it: no funds, no alert, nothing wired.
 *
 * Shared by the preview, the screenshot test and `Wave1ReachabilityTest` so the three
 * cannot drift into disagreeing about what "the no-funds state" is.
 *
 * The three Wave 1 entry points are parameters because a test that taps them has to
 * see *which* one it hit — wiring two identifiers to one callback compiles, looks
 * right, and sends a flow to the wrong screen. The rest stay stubbed: they either
 * raise the sync alert or report as not-yet-ported, and neither leaves this screen.
 */
@Composable
fun HomeNoFunds(
    modifier: Modifier = Modifier,
    onMap: () -> Unit = {},
    onCurrency: () -> Unit = {},
    onAcademy: () -> Unit = {},
) {
    HomeScreen(
        state = HomeUiState(),
        alert = null,
        onDismissAlert = {},
        onSyncingWallet = {},
        onSettings = {},
        onMap = onMap,
        onCurrency = onCurrency,
        onSend = {},
        onReceive = {},
        onBuy = {},
        onBalanceDetails = {},
        onAcademy = onAcademy,
        modifier = modifier,
    )
}
