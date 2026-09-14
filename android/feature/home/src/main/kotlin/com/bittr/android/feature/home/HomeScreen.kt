package com.bittr.android.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrBottomNavBar
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrLogo
import com.bittr.android.core.designsystem.BittrNavTab
import com.bittr.android.core.designsystem.BittrPiggy
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon

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
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val alert by viewModel.currentAlert.collectAsState()

    HomeScreen(
        state = state,
        alert = alert,
        onDismissAlert = viewModel::dismissAlert,
        onSyncingWallet = { viewModel.showAlert(SYNCING_ALERT) },
        onSettings = onSettings,
        onMap = onMap,
        onCurrency = onCurrency,
        onSend = onSend,
        onReceive = onReceive,
        onBuy = onBuy,
        onBalanceDetails = onBalanceDetails,
        onAcademy = onAcademy,
        onTransaction = onTransaction,
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

    // `syncingStatusTapped`: the balance screen once synced, the sync overlay before.
    var syncStatusVisible by remember { mutableStateOf(false) }

    Box(modifier = modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceBright),
    ) {
        HomeHeader(
            showSyncSpinner = state.showSyncSpinner,
            balanceSats = state.balanceSats,
            onMap = onMap,
            onCurrency = onCurrency,
            onSend = guarded(onSend),
            onReceive = guarded(onReceive),
            onBuy = onBuy,
            onSyncStatus = { if (state.walletHasSynced) onBalanceDetails() else syncStatusVisible = true },
            onBalanceCard = guarded(onBalanceDetails),
        )

        if (state.history.isNotEmpty()) {
            HistoryList(
                rows = state.history,
                onTransaction = onTransaction,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            )
        } else Box(
            // `noTransactionsLabel`, which iOS shows when the history is empty.
            contentAlignment = Alignment.TopCenter,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.xxl, vertical = 46.dp),
        ) {
            Text(
                text = buildAnnotatedString {
                    append(HomeStrings.NO_TRANSACTIONS_1)
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(HomeStrings.BUY)
                    }
                    append(HomeStrings.NO_TRANSACTIONS_2)
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        BittrBottomNavBar(
            // Already here. iOS's wallet button re-selects Home rather than pushing
            // another copy of it, so this is a no-op rather than a navigation.
            onWallet = {},
            onAcademy = onAcademy,
            onSettings = onSettings,
            selected = BittrNavTab.Wallet,
            walletTestTag = TestID.Nav.walletButton,
            academyTestTag = TestID.Nav.academyButton,
            settingsTestTag = TestID.Nav.settingsButton,
            modifier = Modifier.navigationBarsPadding(),
        )
    }
    if (syncStatusVisible) SyncStatusSheet(syncProgress(state), onClose = { syncStatusVisible = false })
    }
}

/**
 * The yellow block: logo, wallet card, actions.
 *
 * The canvas colour is drawn under the status bar and the content inset below it —
 * the same rule [com.bittr.android.core.designsystem.BittrCanvas] follows, and the
 * reason the background modifier comes before `statusBarsPadding()`.
 */
@Composable
private fun HomeHeader(
    showSyncSpinner: Boolean,
    balanceSats: Long?,
    onMap: () -> Unit,
    onCurrency: () -> Unit,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onBuy: () -> Unit,
    onSyncStatus: () -> Unit,
    onBalanceCard: () -> Unit = onSyncStatus,
) {
    val colors = BittrTheme.colors
    CompositionLocalProvider(LocalContentColor provides colors.onCanvas) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.canvas, HeaderShape)
                .statusBarsPadding()
                .padding(
                    start = BittrTokens.Spacing.md,
                    end = BittrTokens.Spacing.md,
                    top = BittrTokens.Spacing.sm,
                    bottom = BittrTokens.Spacing.xl,
                ),
        ) {
            Row(
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                BittrLogo(height = 19.dp)
            }
            CanvasSpacer(BittrTokens.Spacing.md)

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.cardWash, RoundedCornerShape(26.dp))
                    .padding(BittrTokens.Spacing.md),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    BittrPiggy()
                    Text(
                        text = HomeStrings.YOUR_WALLET,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier
                            .padding(start = BittrTokens.Spacing.sm)
                            .weight(1f)
                            .testTag(TestID.Home.headerLabel),
                    )
                    // `headerSpinner` — spinning until `finalizeSync()`. Composed only while
                    // it spins, so a flow waiting for it to be not visible is waiting for
                    // the sync, not for an animation to be hidden.
                    if (showSyncSpinner) {
                        CircularProgressIndicator(
                            color = LocalContentColor.current,
                            strokeWidth = 2.dp,
                            modifier = Modifier
                                .size(18.dp)
                                .testTag(TestID.Home.headerSpinner),
                        )
                    }
                    HeaderIcon(
                        path = BittrIconPaths.MAP,
                        label = "Bitcoin map",
                        onClick = onMap,
                        testTag = TestID.Home.mapButton,
                    )
                    HeaderIcon(
                        path = BittrIconPaths.CURRENCY,
                        label = "Bitcoin value",
                        onClick = onCurrency,
                        testTag = TestID.Home.currencyButton,
                    )
                    // `headerViewButton` — iOS's whole-header tap target. Synced, it
                    // opens the balance detail; not synced, it opens the sync overlay,
                    // which is BIT-6's. Until then the guard answers the question the
                    // overlay would have answered, in iOS's own words.
                    HeaderIcon(
                        path = BittrIconPaths.DETAILS,
                        label = "Sync status",
                        onClick = onSyncStatus,
                        testTag = TestID.Home.syncStatusButton,
                        filled = true,
                    )
                }

                // The balance, once the wallet has read one. The fiat conversion and the
                // profit pill follow it on iOS and are still to be ported.
                if (balanceSats != null) {
                    CanvasSpacer(BittrTokens.Spacing.xl)
                    // `balanceCardButton` — a transparent layer under the balance, so the
                    // label keeps its own `home.balanceLabel` id (see HistoryCard on why
                    // under and not over). Opens the balance screen.
                    Box {
                        Box(
                            modifier = Modifier
                                .matchParentSize()
                                .clickable(onClick = onBalanceCard)
                                .testTag(TestID.Home.balanceCardButton),
                        )
                        BalanceLabel(balance = balanceText(balanceSats), dimmedColor = colors.balanceDimmed)
                    }
                }

                CanvasSpacer(BittrTokens.Spacing.xxl)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    // `sendButtonTapped` / `receiveButtonTapped`: the syncing guard,
                    // then the segue. Both arrive here already wrapped in the guard;
                    // the screens behind them are Wave 2, behind the same node.
                    ActionButton(
                        label = HomeStrings.SEND,
                        path = BittrIconPaths.SEND,
                        onClick = onSend,
                        testTag = TestID.Home.sendButton,
                        modifier = Modifier.weight(1f),
                    )
                    ActionButton(
                        label = HomeStrings.RECEIVE,
                        path = BittrIconPaths.RECEIVE,
                        onClick = onReceive,
                        testTag = TestID.Home.receiveButton,
                        modifier = Modifier.weight(1f),
                    )
                    ActionButton(
                        label = HomeStrings.BUY,
                        path = BittrIconPaths.BUY,
                        // Buy is the one action iOS does *not* gate on the sync — it
                        // segues straight to BuyViewController. The screen is Wave 3,
                        // so this reports "not ported" rather than borrowing a guard
                        // iOS does not apply here.
                        onClick = onBuy,
                        testTag = TestID.Home.buyButton,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

/**
 * The balance, in `displayMedium` — the slot the scale keeps for it — shrinking a step at a
 * time until it fits one line, with a 20sp floor (`loadBalanceLabel`'s
 * `adjustsFontSizeToFitWidth`, DEV-23).
 */
@Composable
private fun BalanceLabel(balance: BalanceText, dimmedColor: androidx.compose.ui.graphics.Color) {
    val base = MaterialTheme.typography.displayMedium
    var fontSize by remember(balance) { mutableStateOf(base.fontSize) }
    Text(
        text = buildAnnotatedString {
            withStyle(SpanStyle(color = dimmedColor)) { append(balance.dimmed) }
            append(balance.filled)
        },
        style = base.copy(fontSize = fontSize, lineHeight = fontSize * LINE_HEIGHT_RATIO),
        textAlign = TextAlign.Center,
        maxLines = 1,
        softWrap = false,
        onTextLayout = { layout ->
            if (layout.didOverflowWidth && fontSize > BALANCE_MIN_FONT_SIZE) {
                fontSize = maxOf(BALANCE_MIN_FONT_SIZE.value, fontSize.value - 2f).sp
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .testTag(TestID.Home.balanceLabel),
    )
}

private val BALANCE_MIN_FONT_SIZE = 20.sp
private const val LINE_HEIGHT_RATIO = 1.2f

@Composable
private fun HeaderIcon(
    path: String,
    label: String,
    onClick: () -> Unit,
    testTag: String,
    filled: Boolean = false,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(BittrTokens.Size.minTouchTarget)
            .clickable(onClick = onClick)
            .testTag(testTag)
            .semantics { contentDescription = label },
    ) {
        Image(
            imageVector = if (filled) {
                rememberFillIcon(path, LocalContentColor.current)
            } else {
                rememberStrokeIcon(path, LocalContentColor.current, strokeWidth = 2f)
            },
            contentDescription = null,
            modifier = Modifier.size(22.dp),
        )
    }
}

/** One of the three cream actions in the card — the mock's 56 dp pill with a glyph. */
@Composable
private fun ActionButton(
    label: String,
    path: String,
    onClick: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(
            BittrTokens.Spacing.xs,
            Alignment.CenterHorizontally,
        ),
        modifier = modifier
            .height(56.dp)
            .background(colors.tonalFill, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .testTag(testTag),
    ) {
        Image(
            imageVector = rememberStrokeIcon(path, colors.onTonalFill, strokeWidth = 2.2f),
            contentDescription = null,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = colors.onTonalFill,
        )
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
@Composable
private fun HistoryList(rows: List<HistoryRow>, onTransaction: (String) -> Unit, modifier: Modifier = Modifier) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
    ) {
        itemsIndexed(rows) { position, row ->
            row.year?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = BittrTokens.Spacing.xs, start = BittrTokens.Spacing.xs),
                )
            }
            HistoryCard(row = row, position = position, onClick = { onTransaction(row.id) })
        }
    }
}

@Composable
private fun HistoryCard(row: HistoryRow, position: Int, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    val figureColor = if (row.unconfirmed) colors.unconfirmed else MaterialTheme.colorScheme.onSurface
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(13.dp)),
    ) {
        // Drawn first, under the content. A later sibling that covers a node entirely
        // removes that node from the accessibility tree, so a tap layer on top would take
        // `history.transactionAmountN` out of reach of the flows; the labels handle no
        // touches, so taps still reach this layer through them.
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable(onClick = onClick)
                .testTag(TestID.History.transactionButtonAt(position)),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        ) {
            Text(
                text = row.day,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(7.dp))
                    .padding(horizontal = BittrTokens.Spacing.sm, vertical = BittrTokens.Spacing.xs),
            )
            if (row.isLightning) {
                Image(
                    imageVector = rememberStrokeIcon(BittrIconPaths.BOLT, colors.emphasis, strokeWidth = 2f),
                    contentDescription = "Instant",
                    modifier = Modifier
                        .padding(start = BittrTokens.Spacing.sm)
                        .size(18.dp),
                )
            }
            Column(horizontalAlignment = Alignment.End, modifier = Modifier.weight(1f)) {
                Text(
                    text = row.sats,
                    style = MaterialTheme.typography.titleMedium,
                    color = figureColor,
                    modifier = Modifier.testTag(TestID.History.transactionAmountAt(position)),
                )
                row.fiat?.let {
                    Text(text = it, style = MaterialTheme.typography.bodyMedium, color = figureColor)
                }
            }
        }
    }
}

/** The mock's 34 dp sweep under the yellow block. */
private val HeaderShape = RoundedCornerShape(bottomStart = 34.dp, bottomEnd = 34.dp)

private val SYNCING_ALERT = HomeAlert(
    title = HomeStrings.SYNCING_WALLET,
    message = HomeStrings.SYNCING_WALLET_2,
)

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
