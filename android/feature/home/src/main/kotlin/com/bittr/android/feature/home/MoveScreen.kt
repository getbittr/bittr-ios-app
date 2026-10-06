package com.bittr.android.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.roundToLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** The wallet overview and a price, for [MoveScreen]. */
@HiltViewModel
class MoveViewModel @Inject constructor(
    overview: WalletOverviewSource,
    prices: FiatPriceSource,
) : ViewModel() {

    private val price = MutableStateFlow<FiatPrice?>(null)

    init {
        viewModelScope.launch { price.value = prices.current() }
    }

    internal val balances: StateFlow<MoveBalances> = combine(overview.overview, price) { wallet, price ->
        moveBalances(wallet, price)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, moveBalances(overview.overview.value, null))
}

/**
 * `MoveViewController.updateLabels()`: regular is the on-chain balance, instant is Lightning
 * plus what is still sweeping back from a closed channel, total is both. Fiat is
 * "symbol amount", rounded to whole units.
 */
internal data class MoveBalances(
    val total: String,
    val regular: String,
    val instant: String,
    val totalFiat: String?,
    val regularFiat: String?,
    val instantFiat: String?,
    val pendingClosureSats: Long,
    val lightningSats: Long,
    val channelCount: Int,
)

internal fun moveBalances(wallet: WalletOverview, price: FiatPrice?): MoveBalances {
    val instant = wallet.satoshisLightning + wallet.pendingClosureSatoshis
    val regular = wallet.satoshisOnchain
    fun fiat(sats: Long) = price?.let { "${it.symbol} ${groupThousands((sats / 100_000_000.0 * it.pricePerBitcoin).roundToLong())}" }
    return MoveBalances(
        total = "${groupThousands(regular + instant)} sats",
        regular = "${groupThousands(regular)} sats",
        instant = "${groupThousands(instant)} sats",
        totalFiat = fiat(regular + instant),
        regularFiat = fiat(regular),
        instantFiat = fiat(instant),
        pendingClosureSats = wallet.pendingClosureSatoshis,
        lightningSats = wallet.satoshisLightning,
        channelCount = wallet.channelCount,
    )
}

/**
 * The balance screen — `MoveViewController`, opened from Home's balance card: the total,
 * regular and instant balances, Send and Receive, the lightning-connection question and
 * the swap button.
 *
 * As the storyboard lays it out: `addHeader` with the piggy over a block centred in the whole
 * sheet — the subtitle 40 in, and 30 under it `yellowCard`, 30 in, `yelloworblue2` with 20
 * corners and the iOS shadow. In it, 10 in, the total on its own `whiteorblue3` card and Regular
 * and Instant as two halves under it, 10 apart, with the swap circle over the seam. Send and
 * Receive sit 35 under the card, centred.
 */
@Composable
fun MoveScreen(
    onDown: () -> Unit,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onLightningQuestion: () -> Unit,
    modifier: Modifier = Modifier,
    // `MoveToSwap`, once there is a channel to swap with.
    onSwap: () -> Unit = {},
    viewModel: MoveViewModel = hiltViewModel(),
) {
    val balances by viewModel.balances.collectAsState()
    val colors = BittrTheme.colors
    var alert by remember { mutableStateOf<Pair<Pair<String, String>, List<BittrAlertButton>>?>(null) }
    fun okay(title: String, message: String) {
        alert = (title to message) to listOf(BittrAlertButton(HomeStrings.OKAY, dismissesAlert = true) { alert = null })
    }

    alert?.let { (text, buttons) -> BittrAlert(title = text.first, message = text.second, buttons = buttons) }

    // `channelButtonTapped`.
    val onChannel: () -> Unit = {
        when {
            balances.pendingClosureSats > 0 -> {
                val message = HomeStrings.PENDING_CLOSURE.replace("<pendingfunds>", groupThousands(balances.pendingClosureSats))
                if (balances.lightningSats == 0L) {
                    okay(HomeStrings.CONNECTION_CLOSED, message)
                } else {
                    alert = (HomeStrings.CONNECTION_CLOSED to message) to listOf(
                        BittrAlertButton(HomeStrings.CLOSE, dismissesAlert = true) { alert = null },
                        BittrAlertButton(HomeStrings.VIEW_ACTIVE_CONNECTION) {
                            alert = null
                            onLightningQuestion()
                        },
                    )
                }
            }
            balances.channelCount == 0 -> okay(HomeStrings.LIGHTNING_CONNECTIONS, HomeStrings.LIGHTNING_EXPLANATION_1)
            else -> onLightningQuestion()
        }
    }
    // `swapButtonTapped`.
    val onSwapTapped: () -> Unit = {
        if (balances.channelCount == 0) okay(HomeStrings.INSTANT_PAYMENTS, HomeStrings.QUESTION_VC_13) else onSwap()
    }

    // Pulled down, the sheet closes — the swipe the swap flows use to leave it.
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvas)
            .dismissOnPullDown(onDown),
    ) {
        val sheetHeight = maxHeight
        Column(
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = sheetHeight)
                .padding(vertical = 58.dp),
        ) {
            Text(
                text = HomeStrings.WALLET_SUBTITLE,
                style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.1.sp),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .testTag(TestID.Move.subtitleLabel),
            )
            CanvasSpacer(30.dp)
            Column(
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier
                    .padding(horizontal = 30.dp)
                    .fillMaxWidth()
                    .iosShadow(YellowCardShape)
                    .background(colors.levelCard, YellowCardShape)
                    .padding(10.dp),
            ) {
                TotalView(balances.total, balances.totalFiat)
                // The halves and, over the 10 between them, the swap circle — centred on the card
                // and level with the halves' middle.
                Box(contentAlignment = Alignment.Center) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.height(IntrinsicSize.Min),
                    ) {
                        HalfView(
                            title = HomeStrings.REGULAR,
                            sats = balances.regular,
                            fiat = balances.regularFiat,
                            satsTag = TestID.Move.satsRegular,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        HalfView(
                            title = HomeStrings.INSTANT,
                            sats = balances.instant,
                            fiat = balances.instantFiat,
                            satsTag = TestID.Move.satsInstant,
                            // Greyed while part of it is still sweeping back from a closed channel.
                            figureColor = if (balances.pendingClosureSats > 0) colors.unconfirmed else MaterialTheme.colorScheme.onSurface,
                            instant = true,
                            onClick = onChannel,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                    }
                    SwapCircle(onClick = onSwapTapped)
                }
            }
            CanvasSpacer(35.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ActionPlate(HomeStrings.SEND, up = true, onClick = onSend)
                ActionPlate(HomeStrings.RECEIVE, up = false, onClick = onReceive)
            }
        }

        BittrSheetHeader(
            icon = painterResource(R.drawable.home_piggy_white),
            title = HomeStrings.BALANCE,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

private val YellowCardShape = RoundedCornerShape(20.dp)
private val BalanceViewShape = RoundedCornerShape(13.dp)
private val ActionPlateShape = RoundedCornerShape(8.dp)

/** Gilroy-Bold 17 for a figure and Regular 14 for its conversion, each line as tall as its type. */
private val FigureStyle @Composable get() = MaterialTheme.typography.labelLarge.copy(fontSize = 17.sp, lineHeight = 17.sp)
private val ConversionStyle @Composable get() = MaterialTheme.typography.bodyMedium.copy(lineHeight = 14.sp)

/** `viewTotal`: the figure 20 from the top, its conversion 5 under it and 16 from the bottom. */
@Composable
private fun TotalView(sats: String, fiat: String?) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, BalanceViewShape)
            .padding(start = 10.dp, end = 10.dp, top = 20.dp, bottom = 16.dp),
    ) {
        Text(sats, style = FigureStyle, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, modifier = Modifier.testTag(TestID.Move.satsTotal))
        CanvasSpacer(5.dp)
        Text(fiat ?: " ", style = ConversionStyle, color = MaterialTheme.colorScheme.onSurface, maxLines = 1)
    }
}

/**
 * `viewRegular` / `viewInstant`: the yellow Gilroy-Bold 14 title 15 from the top, the figure 8
 * under it, the conversion 5 under that and 13 from the bottom, all centred. Instant's title has
 * the 12 pt `bolt.fill` 4 before it (the pair sits 6 right of centre on iOS, the title centred
 * on its own), `questionmark.circle` 8 from the top and trailing edge at half opacity, and the
 * whole card is `channelButton`.
 */
@Composable
private fun HalfView(
    title: String,
    sats: String,
    fiat: String?,
    satsTag: String,
    modifier: Modifier = Modifier,
    figureColor: Color = MaterialTheme.colorScheme.onSurface,
    instant: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val colors = BittrTheme.colors
    Box(
        modifier = modifier
            .clip(BalanceViewShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .then(
                if (onClick != null) {
                    Modifier
                        .clickable(onClick = onClick)
                        .testTag(TestID.Move.channelButton)
                } else {
                    Modifier
                },
            ),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 10.dp, end = 10.dp, top = 15.dp, bottom = 13.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = if (instant) Modifier.offset(x = (-2).dp) else Modifier,
            ) {
                if (instant) {
                    Image(
                        rememberFillIcon(BittrIconPaths.BOLT, colors.brandFixed),
                        contentDescription = null,
                        modifier = Modifier
                            .padding(end = 4.dp)
                            .offset(y = (-1).dp)
                            .size(13.dp),
                    )
                }
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp),
                    color = colors.brandFixed,
                    maxLines = 1,
                )
            }
            CanvasSpacer(8.dp)
            Text(sats, style = FigureStyle, color = figureColor, maxLines = 1, modifier = Modifier.testTag(satsTag))
            CanvasSpacer(5.dp)
            Text(fiat ?: " ", style = ConversionStyle, color = figureColor, maxLines = 1)
        }
        if (instant) {
            Image(
                rememberFillIcon(BittrIconPaths.HELP, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)),
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 8.dp, end = 8.dp)
                    .size(16.dp),
            )
        }
    }
}

/**
 * `swapView`: a 36 pt `yelloworblue2` circle with the iOS shadow, `iconswapwhite` (yellow
 * `iconswap` in dark) 18 pt inside it, and `swapButton` 40 around it.
 */
@Composable
private fun SwapCircle(onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .testTag(TestID.Move.swapButton),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(36.dp)
                .iosShadow(CircleShape)
                .background(BittrTheme.colors.levelCard, CircleShape),
        ) {
            Image(
                painter = painterResource(if (BittrTheme.isDark) R.drawable.move_swap_yellow else R.drawable.move_swap_white),
                contentDescription = HomeStrings.SWAP,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/**
 * `leftCard` / `rightCard`: 48 tall, `white0.7orblue2` with 8 corners and the iOS shadow; the
 * yellow `arrow.up.square` / `arrow.down.square` 17 in, the Gilroy-Bold 15 label 9 after it and
 * 20 from the end.
 */
@Composable
private fun ActionPlate(label: String, up: Boolean, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .height(48.dp)
            .iosShadow(ActionPlateShape)
            .clip(ActionPlateShape)
            .background(colors.scrim2)
            .clickable(onClick = onClick)
            .padding(start = 17.dp, end = 20.dp),
    ) {
        Image(
            rememberStrokeIcon(if (up) SQUARE_ARROW_UP else SQUARE_ARROW_DOWN, colors.brandFixed, strokeWidth = 1.5f),
            contentDescription = null,
            modifier = Modifier.size(24.dp),
        )
        Text(
            label,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp, lineHeight = 15.sp),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .padding(start = 9.dp)
                .offset(y = 1.dp),
        )
    }
}

/** `arrow.up.square` / `arrow.down.square` in a 24 viewport: a rounded square with the arrow in it. */
private const val SQUARE = "M5.5 3.5h13a2 2 0 012 2v13a2 2 0 01-2 2h-13a2 2 0 01-2-2v-13a2 2 0 012-2z"
private const val SQUARE_ARROW_UP = "$SQUARE M12 16.5V7.5M8 11.5l4-4 4 4"
private const val SQUARE_ARROW_DOWN = "$SQUARE M12 7.5v9M8 12.5l4 4 4-4"
