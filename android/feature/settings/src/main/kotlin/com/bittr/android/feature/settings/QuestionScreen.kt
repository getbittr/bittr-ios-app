package com.bittr.android.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.wallet.ChannelSummary
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/** The active channel, for the chart on [LightningQuestionScreen]. */
@HiltViewModel
class LightningQuestionViewModel @Inject constructor(overview: WalletOverviewSource) : ViewModel() {

    val channel: StateFlow<ChannelSummary?> = overview.overview
        .map { it.activeChannel }
        .stateIn(viewModelScope, SharingStarted.Eagerly, overview.overview.value.activeChannel)
}

/**
 * The explanation card behind Device details → Lightning connections and Move's channel button —
 * `ios/bittr/Question/QuestionViewController` in its `lightningexplanation` role.
 *
 * Two shapes, as on iOS: with an active channel, the channel chart (`question.channelView`) above
 * `questionvc7`'s figures; without one, the plain `lightningexplanation1` card.
 */
@Composable
fun LightningQuestionScreen(
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    channel: ChannelSummary? = null,
) {
    QuestionScreen(
        title = SettingsStrings.LIGHTNING_CONNECTIONS_TITLE,
        answer = if (channel == null) {
            SettingsStrings.LIGHTNING_EXPLANATION
        } else {
            SettingsStrings.QUESTION_VC_7
                .replace("<channelbalance>", group(channel.balanceSats))
                .replace("<channelreserve>", group(channel.reserveSats))
                .replace("<sendlimit>", group(channel.outboundSats))
        },
        onDown = onDown,
        modifier = modifier,
        channel = channel,
    )
}

/**
 * `QuestionViewController`: a lower-case header, the yellow card with the answer, and the channel
 * chart above it when [channel] is given. `<b>` in [answer] is drawn bold, as iOS's `attributed()`.
 */
@Composable
fun QuestionScreen(
    title: String,
    answer: String,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    channel: ChannelSummary? = null,
) {
    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = title.lowercase(),
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            if (channel != null) ChannelChart(channel)
            BittrCard(modifier = Modifier.testTag(TestID.Question.yellowCard)) {
                Text(
                    text = boldTagged(answer),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Question.answerLabel),
                )
            }
        }
    }
}

/** `setChannelChart(forChannel:)`: balance and receive limit, the bar, and the total and reserve. */
@Composable
private fun ChannelChart(channel: ChannelSummary) {
    Column(
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
            .padding(BittrTokens.Spacing.md)
            .testTag(TestID.Question.channelView),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.weight(1f)) {
                Text(SettingsStrings.YOUR_BALANCE, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
                Text(group(channel.balanceSats), style = MaterialTheme.typography.titleMedium)
            }
            Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                Text(SettingsStrings.RECEIVE_LIMIT, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
                Text(group(channel.receiveLimitSats), style = MaterialTheme.typography.titleMedium)
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .background(MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(2.dp)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(channel.balanceFraction)
                    .background(BittrTheme.colors.canvas, RoundedCornerShape(2.dp)),
            )
        }
        Text(
            text = "${group(channel.valueSats)} ${SettingsStrings.TOTAL}, ${group(channel.reserveSats)} ${SettingsStrings.RESERVE}",
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

/** `addSpaces()`. */
private fun group(value: Long): String = value.toString().reversed().chunked(3).joinToString(" ").reversed()

/** iOS's `attributed()`: `<b>…</b>` bold, the tags removed. */
internal fun boldTagged(text: String): AnnotatedString = buildAnnotatedString {
    var rest = text
    while (true) {
        val open = rest.indexOf("<b>")
        val close = if (open >= 0) rest.indexOf("</b>", open) else -1
        if (open < 0 || close < 0) {
            append(rest.replace("<b>", "").replace("</b>", ""))
            break
        }
        append(rest.substring(0, open))
        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(rest.substring(open + 3, close)) }
        rest = rest.substring(close + 4)
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun LightningQuestionScreenPreview() {
    BittrTheme {
        LightningQuestionScreen(onDown = {}, channel = ChannelSummary(valueSats = 200_000, outboundSats = 48_000, reserveSats = 2_000))
    }
}
