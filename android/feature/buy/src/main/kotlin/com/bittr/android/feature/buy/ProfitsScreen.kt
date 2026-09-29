package com.bittr.android.feature.buy

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.dismissOnPullDown

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
    // `addHeader` with the piggy over a block centred in the whole sheet: the subtitle 40 in, and
    // 30 under it the card, 15 in, `yelloworblue2` with 13 corners and the iOS shadow.
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
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
            // Gilroy-Regular 16 at the 16.1 pitch the iOS screenshot shows.
            Text(
                text = BuyStrings.PROFIT_SUBTITLE,
                style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.1.sp),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .testTag(TestID.Profits.subtitleLabel),
            )
            CanvasSpacer(30.dp)
            BittrCard(
                fill = BittrTheme.colors.levelCard,
                contentPadding = PaddingValues(10.dp),
                modifier = Modifier.padding(horizontal = 15.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ProfitRow(BuyStrings.TOTAL_INVESTMENT, summary.investmentText, TestID.Profits.totalInvestmentLabel)
                    ProfitRow(BuyStrings.CURRENT_VALUE, summary.valueText, TestID.Profits.totalValueLabel)
                    ProfitRow(BuyStrings.TOTAL_PROFIT, summary.profitText, TestID.Profits.totalProfitLabel)
                }
            }
        }

        BittrSheetHeader(
            icon = painterResource(R.drawable.buy_header_piggy),
            title = BuyStrings.YOUR_PROFITS,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

/**
 * `investedView` and its siblings: `whiteorblue3`, 45 tall with 8 corners; the title in yellow
 * and the value in black/white, both Gilroy-Bold 16, 15 from the row's ends and 1 and 2 below
 * its middle.
 */
@Composable
private fun ProfitRow(label: String, value: String, tag: String) {
    val style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(45.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(8.dp))
            .padding(horizontal = 15.dp),
    ) {
        Text(
            text = label,
            style = style,
            color = BittrTheme.colors.brandFixed,
            maxLines = 1,
            modifier = Modifier
                .weight(1f)
                .offset(y = 1.dp),
        )
        Text(
            text = value,
            style = style,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            modifier = Modifier
                .offset(y = 2.dp)
                .testTag(tag),
        )
    }
}
