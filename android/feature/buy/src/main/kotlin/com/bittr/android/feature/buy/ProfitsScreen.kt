package com.bittr.android.feature.buy

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

/**
 * `ProfitViewController` — total investment, current value and total profit of the bittr
 * purchases in this wallet, from Home's profit pill.
 *
 * @param summary null until prices and purchases have been read; the labels then show `"<symbol> 0"`
 *   the way iOS's zeroed `totalInvestments` etc. would.
 */
@Composable
fun ProfitsScreen(
    summary: ProfitSummary,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = BuyStrings.YOUR_PROFITS,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            BittrBody(
                BuyStrings.PROFIT_SUBTITLE,
                modifier = Modifier.testTag(TestID.Profits.subtitleLabel),
            )
            CanvasSpacer(BittrTokens.Spacing.lg)
            BittrCard(horizontalAlignment = Alignment.Start) {
                ProfitRow(BuyStrings.TOTAL_INVESTMENT, summary.investmentText, TestID.Profits.totalInvestmentLabel)
                ProfitRow(BuyStrings.CURRENT_VALUE, summary.valueText, TestID.Profits.totalValueLabel)
                ProfitRow(BuyStrings.TOTAL_PROFIT, summary.profitText, TestID.Profits.totalProfitLabel)
            }
        }
    }
}

@Composable
private fun ProfitRow(label: String, value: String, tag: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = BittrTokens.Spacing.sm)) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Text(value, style = MaterialTheme.typography.titleLarge, modifier = Modifier.testTag(tag))
    }
}
