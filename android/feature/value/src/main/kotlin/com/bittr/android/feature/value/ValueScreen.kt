package com.bittr.android.feature.value

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import java.time.LocalDate

/**
 * The Bitcoin value screen. Ported from `ValueViewController`.
 *
 * The ordering `bitcoin_value.yaml` depends on:
 *
 * 1. `value.graphView` exists from the moment the screen opens, empty, so the flow
 *    can assert it before the data lands.
 * 2. `value.valueSpinner` spins until both requests return; `value.profitLabel`
 *    appears at the same moment. The flow waits on the label and asserts the spinner
 *    is gone, so the two have to flip together — they are both derived from
 *    [ValueUiState.isFetchingData] here rather than set independently.
 * 3. Span taps are dropped while the fetch is in flight, which is why the wait has
 *    to come first. That guard lives in [ValueUiState.selectSpan] and is tested.
 */
@Composable
fun ValueScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    currency: PriceCurrency = PriceCurrency.EUR,
) = ValueScreen(onBack = onBack, modifier = modifier, currency = currency, repository = null)

/**
 * The same screen with its data source supplied — how the tests and the preview
 * drive it without a network. Internal because [PriceRepository] is: the payload
 * shape is a detail of this module and nothing outside it should be binding to it.
 */
@Composable
internal fun ValueScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    currency: PriceCurrency = PriceCurrency.EUR,
    repository: PriceRepository? = null,
) {
    val prices = remember(repository) { repository ?: HttpPriceRepository() }
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
        Text(
            text = ValueCopy.TITLE,
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = BittrTokens.Spacing.gutter),
        )
        CanvasSpacer(BittrTokens.Spacing.sm)

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.gutter),
        ) {
            Text(
                text = state.currentValue.orEmpty(),
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier
                    .weight(1f)
                    .testTag(TestID.Value.currentValueLabel),
            )
            ProfitBadge(state)
        }

        CanvasSpacer(BittrTokens.Spacing.md)

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp)
                .padding(horizontal = BittrTokens.Spacing.gutter),
        ) {
            // Tagged and present from the first frame — the flow asserts it before
            // the data arrives, so it must not be gated on having points.
            GraphView(
                points = state.visiblePoints,
                currencySymbol = ValueCopy.currencySymbol(state),
                modifier = Modifier
                    .fillMaxSize()
                    .testTag(TestID.Value.graphView),
            )

            if (state.isFetchingData) {
                CircularProgressIndicator(
                    color = BittrTheme.colors.onCanvas,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Value.valueSpinner),
                )
            } else if (!state.hasData) {
                // `noDataLabel` — a span with no points is a displayable state, not
                // a failure (`ValueViewController.swift:366-372`).
                Text(
                    text = ValueCopy.NO_DATA,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.Center),
                )
            }
        }

        CanvasSpacer(BittrTokens.Spacing.md)
        SpanButtons(state = state, onSelect = { state = state.selectSpan(it) })
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

/**
 * The percentage badge.
 *
 * Its visibility is the flow's "data loaded" signal: `profitView` starts at alpha 0
 * and is faded in by `drawGraph` (`ValueViewController.swift:388-405`), so
 * `value.profitLabel` appearing means the series is parsed and drawn. Keeping it out
 * of the tree until then is what makes `extendedWaitUntil` return at the right
 * moment rather than immediately.
 */
@Composable
private fun ProfitBadge(state: ValueUiState) {
    if (state.isFetchingData || !state.hasData) return
    val percentage = profitPercentage(state.visiblePoints.map { it.price }) ?: return
    val colors = BittrTheme.colors
    val loss = percentage.startsWith("-")

    Text(
        text = percentage,
        style = MaterialTheme.typography.labelLarge,
        color = if (loss) colors.loss else colors.profit,
        modifier = Modifier
            .background(
                if (loss) colors.lossBg else colors.profitBg,
                BittrCanvasShapes.pill,
            )
            .padding(horizontal = BittrTokens.Spacing.sm, vertical = BittrTokens.Spacing.xs)
            .testTag(TestID.Value.profitLabel),
    )
}

/**
 * The four span buttons.
 *
 * The selected one shows the long title and the rest the short one
 * (`showSelectedSpan`), which is why the flow taps `value.monthButton` and then
 * looks for the graph rather than for the label "m" — the label it just tapped has
 * changed to "1 month".
 */
@Composable
private fun SpanButtons(state: ValueUiState, onSelect: (GraphSpan) -> Unit) {
    val colors = BittrTheme.colors
    Row(
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = BittrTokens.Spacing.gutter),
    ) {
        GraphSpan.entries.forEach { span ->
            val selected = span == state.selectedSpan
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(BittrTokens.Size.minTouchTarget)
                    .background(
                        if (selected) colors.scrim1 else colors.scrim2,
                        BittrCanvasShapes.wordRow,
                    )
                    .clickable(role = Role.Button) { onSelect(span) }
                    .testTag(span.testTag),
            ) {
                Text(state.titleFor(span), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** The id each span button carries, so the flow can tap m, y and 5y by name. */
private val GraphSpan.testTag: String
    get() = when (this) {
        GraphSpan.WEEK -> TestID.Value.weekButton
        GraphSpan.MONTH -> TestID.Value.monthButton
        GraphSpan.YEAR -> TestID.Value.yearButton
        GraphSpan.FIVE_YEARS -> TestID.Value.fiveYearsButton
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
