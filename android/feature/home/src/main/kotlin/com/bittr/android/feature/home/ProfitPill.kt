package com.bittr.android.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme

/**
 * Home's profit pill — `balanceCardGainLabel` in `balanceCardProfitView`.
 *
 * @property text `"<n> %"`, unsigned, as `showProfitLabel` writes it.
 * @property isLoss loss colours and a down arrow.
 */
data class ProfitPill(val text: String, val isLoss: Boolean)

/**
 * The pill, tappable as `home.profitButton` with the percentage inside it as `home.profitLabel`.
 *
 * The tap is a pointer handler on the pill rather than `clickable`, because `clickable` merges its
 * children's semantics and the label would lose its own id.
 */
@Composable
internal fun ProfitPillView(pill: ProfitPill, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    val tap by rememberUpdatedState(onClick)
    val foreground = if (pill.isLoss) colors.loss else colors.profit
    Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .background(if (pill.isLoss) colors.lossBg else colors.profitBg, RoundedCornerShape(50))
                .pointerInput(Unit) { detectTapGestures { tap() } }
                .testTag(TestID.Home.profitButton)
                .padding(horizontal = 12.dp, vertical = 4.dp),
        ) {
            Text(if (pill.isLoss) "↓" else "↑", color = foreground, style = MaterialTheme.typography.labelLarge)
            Text(
                text = pill.text,
                color = foreground,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier
                    .padding(start = 4.dp)
                    .testTag(TestID.Home.profitLabel),
            )
        }
    }
}
