package com.bittr.android.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.dismissOnPullDown
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
 * the swap button. Swaps are not ported yet, and the swap button says so.
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
    var alert by remember { mutableStateOf<Pair<Pair<String, String>, List<BittrAlertButton>>?>(null) }
    fun okay(title: String, message: String) {
        alert = (title to message) to listOf(BittrAlertButton(HomeStrings.OKAY, dismissesAlert = true) { alert = null })
    }

    alert?.let { (text, buttons) -> BittrAlert(title = text.first, message = text.second, buttons = buttons) }

    // Pulled down, the sheet closes — the swipe the swap flows use to leave it.
    BittrCanvas(modifier = modifier.dismissOnPullDown(onDown), appBar = false) {
        BittrModalHeader(
            title = HomeStrings.BALANCE,
            onDown = onDown,
            icon = BittrIconPaths.PIGGY,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            Text(
                text = HomeStrings.WALLET_SUBTITLE,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = BittrTokens.Spacing.md)
                    .testTag(TestID.Move.subtitleLabel),
            )
            BittrCard {
                Column(verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
                    BalanceRow(HomeStrings.TOTAL, balances.total, balances.totalFiat, TestID.Move.satsTotal)
                    BalanceRow(HomeStrings.REGULAR, balances.regular, balances.regularFiat, TestID.Move.satsRegular)
                    BalanceRow(
                        title = HomeStrings.INSTANT,
                        sats = balances.instant,
                        fiat = balances.instantFiat,
                        satsTag = TestID.Move.satsInstant,
                        bolt = true,
                        onQuestion = {
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
                        },
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
                        MoveButton(HomeStrings.SEND, BittrIconPaths.SEND, null, Modifier.weight(1f), onSend)
                        MoveButton(HomeStrings.RECEIVE, BittrIconPaths.RECEIVE, null, Modifier.weight(1f), onReceive)
                        MoveButton(null, SWAP_PATH, TestID.Move.swapButton, Modifier) {
                            if (balances.channelCount == 0) {
                                okay(HomeStrings.INSTANT_PAYMENTS, HomeStrings.QUESTION_VC_13)
                            } else {
                                onSwap()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BalanceRow(
    title: String,
    sats: String,
    fiat: String?,
    satsTag: String,
    bolt: Boolean = false,
    onQuestion: (() -> Unit)? = null,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
            .padding(start = BittrTokens.Spacing.md, end = if (onQuestion == null) BittrTokens.Spacing.md else 0.dp)
            .height(64.dp),
    ) {
        if (bolt) {
            Image(
                rememberStrokeIcon(BittrIconPaths.BOLT, BittrTheme.colors.emphasis, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier
                    .padding(end = BittrTokens.Spacing.xs)
                    .size(16.dp),
            )
        }
        Text(title, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis, modifier = Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(sats, style = MaterialTheme.typography.titleMedium, modifier = Modifier.testTag(satsTag))
            fiat?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        }
        if (onQuestion != null) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(BittrTokens.Size.minTouchTarget)
                    .clickable(onClick = onQuestion)
                    .testTag(TestID.Move.channelButton),
            ) {
                Text("?", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

@Composable
private fun MoveButton(label: String?, path: String, testTag: String?, modifier: Modifier, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs, Alignment.CenterHorizontally),
        modifier = modifier
            .height(52.dp)
            .background(colors.tonalFill, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        Image(
            rememberStrokeIcon(path, colors.onTonalFill, strokeWidth = 2.2f),
            contentDescription = label ?: HomeStrings.SWAP,
            modifier = Modifier.size(18.dp),
        )
        if (label != null) Text(label, style = MaterialTheme.typography.labelLarge, color = colors.onTonalFill)
    }
}

private const val SWAP_PATH = "M7 4v16M3 8l4-4 4 4M17 20V4M13 16l4 4 4-4"
