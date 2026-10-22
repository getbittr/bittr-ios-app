package com.bittr.android.feature.value

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrTheme
import java.time.LocalDate

/**
 * The Bitcoin value screen. Ported from `ValueViewController`.
 *
 * The ordering `bitcoin_value.yaml` depends on:
 *
 * 1. `value.graphView` exists from the moment the screen opens, empty, so the flow
 *    can assert it before the data lands.
 * 2. `value.valueSpinner` is up until both requests return; `value.profitLabel`
 *    appears at the same moment. The flow waits on the label and asserts the spinner
 *    is gone, so the two have to flip together — they are both derived from
 *    [ValueUiState.isFetchingData] here rather than set independently. Since the
 *    design review the id is on the chart's loading placeholder rather than a
 *    spinner (see [ValueChartCard]); it is still the loading indicator.
 * 3. Span taps are dropped while the fetch is in flight, which is why the wait has
 *    to come first. That guard lives in [ValueUiState.selectSpan] and is tested.
 */
/**
 * [history] is passed in rather than built here, and that is deliberate: this screen
 * used to build its own URL from a literal, so the regtest build read the production
 * price API (BIT-32, fixed in BIT-41 item 1). The app builds the one [PriceHistory]
 * from the environment `BuildConfig` names, which keeps the choice of backend out of
 * this feature module, and shares it with Home's value card.
 */
@Composable
fun ValueScreen(
    // The app's one price history, shared with Home's value card.
    history: PriceHistory,
    onBack: () -> Unit,
    // The chosen currency. No default: one let every caller draw the chart in euros.
    currency: PriceCurrency,
    modifier: Modifier = Modifier,
) = ValueScreen(
    onBack = onBack,
    modifier = modifier,
    currency = currency,
    repository = remember(history) {
        object : PriceRepository {
            override suspend fun load(currency: PriceCurrency, today: LocalDate) = history.load(currency, today)
        }
    },
)

/**
 * The same screen with its data source supplied — how the tests and the preview
 * drive it without a network. Internal because [PriceRepository] is: the payload
 * shape is a detail of this module and nothing outside it should be binding to it.
 *
 * [repository] is required rather than nullable-with-a-default. It was the latter
 * while the default could be `HttpPriceRepository()` — a no-argument constructor
 * that existed only because the backend URL was a constant in this module. It is
 * not, any more.
 */
@Composable
internal fun ValueScreen(
    onBack: () -> Unit,
    repository: PriceRepository,
    modifier: Modifier = Modifier,
    currency: PriceCurrency = PriceCurrency.EUR,
) {
    val prices = repository
    var state by remember { mutableStateOf(ValueUiState()) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(prices, currency, attempt) {
        state = ValueUiState()
        failed = false
        runCatching { prices.load(currency, LocalDate.now()) }.fold(
            onSuccess = { snapshot ->
                state = state.copy(
                    series = snapshot.series,
                    currentValue = "${currency.symbol} ${formatPrice(snapshot.currentPrice)}",
                    isFetchingData = false,
                )
            },
            onFailure = {
                // iOS stops the spinner, clears the fetching flag and offers a retry
                // (`ValueViewController.swift:276-286`). The screen stays up with an
                // empty chart rather than bouncing back, so a retry is one tap.
                state = state.copy(isFetchingData = false)
                failed = true
            },
        )
    }

    // `ValueViewController` in its page sheet: `addHeader`'s exchange icon and "bitcoin value", and
    // under it `centerCard`, 15 from the sides and centred in what is left.
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .navigationBarsPadding(),
    ) {
        BittrSheetHeader(
            icon = painterResource(R.drawable.value_header_icon),
            title = ValueCopy.TITLE,
            onDown = onBack,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
            Column(
                verticalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = maxHeight)
                    .padding(horizontal = 15.dp, vertical = 30.dp),
            ) {
                ValueChartCard(state = state, onSelect = { state = state.selectSpan(it) })
            }
        }
    }

    if (failed) {
        BittrAlertDialog(
            title = ValueCopy.OOPS,
            message = ValueCopy.HISTORICAL_DATA_ERROR,
            confirmLabel = ValueCopy.TRY_AGAIN,
            onConfirm = {
                failed = false
                attempt++
            },
            confirmTestTag = TestID.Alert.buttonAt(1),
            dismissLabel = ValueCopy.CANCEL,
            onDismiss = { failed = false },
            dismissTestTag = TestID.Alert.buttonAt(0),
        )
    }
}


@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun ValueScreenPreview() {
    BittrTheme {
        ValueScreen(
            onBack = {},
            repository = object : PriceRepository {
                override suspend fun load(currency: PriceCurrency, today: LocalDate) =
                    PriceSnapshot(series = emptyMap(), currentPrice = 98_450.0)
            },
        )
    }
}
