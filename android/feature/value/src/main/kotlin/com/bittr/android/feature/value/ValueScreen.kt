package com.bittr.android.feature.value

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
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
 * [environment] and [http] are passed in rather than defaulted, and that is
 * deliberate: this screen used to build its own URL from a literal, so the regtest
 * build read the production price API (BIT-32, fixed in BIT-41 item 1). A default
 * here would put the choice of backend back inside a feature module, where
 * `ApiBaseUrlGuardTest` would have to allow a second hostname. `BittrNavHost` reads
 * it once out of `BuildConfig` and hands it down, the same way it does
 * `BitcoinNetwork`.
 */
@Composable
fun ValueScreen(
    environment: BittrEnvironment,
    http: HttpClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    currency: PriceCurrency = PriceCurrency.EUR,
) = ValueScreen(
    onBack = onBack,
    modifier = modifier,
    currency = currency,
    repository = remember(environment, http) { HttpPriceRepository(environment, http) },
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

    LaunchedEffect(prices, attempt) {
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

    BittrCanvas(modifier = modifier, onBack = onBack) {
        // The design review's content column (2026-09-18, S13): 24 dp in from the
        // sides and 24 dp down from the app bar, which the title used to sit flush
        // against. The chart card shares the 24 dp side margin, so title and card
        // align on one edge.
        Column(
            Modifier
                .fillMaxWidth()
                .padding(start = ContentGutter, end = ContentGutter, top = ContentGutter),
        ) {
            // `headlineSmall` is the scale's screen-title slot (Gilroy-Bold 26/32), and
            // it stays that: the review's 28/34 would make this title a size larger
            // than every other screen title in the app. If titles should be 28, that is
            // the slot's change to make, in `Type.kt`.
            Text(
                text = ValueCopy.TITLE,
                style = MaterialTheme.typography.headlineSmall,
            )
            Spacer(Modifier.height(16.dp))
            ValueChartCard(state = state, onSelect = { state = state.selectSpan(it) })
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

/** The review's content-column gutter, top and sides. */
private val ContentGutter = 24.dp

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
