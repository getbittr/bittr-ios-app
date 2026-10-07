package com.bittr.android.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.ChannelSummary
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import androidx.compose.ui.draw.clip
import com.bittr.android.core.designsystem.iosShadow

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
        answer = if (channel == null) SettingsStrings.LIGHTNING_EXPLANATION else questionVc7(channel),
        onDown = onDown,
        modifier = modifier,
        channel = channel,
    )
}

/**
 * Send's "why a limit for instant payments?" card — `QuestionViewController` in its
 * `lightningsendable` role. With an active channel: the chart and `questionvc7`'s figures under
 * `limitlightning`. Without one, iOS replaces both the header and the text, with `questionvc12`
 * and `questionvc13`.
 */
@Composable
fun LightningSendableQuestionScreen(
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    channel: ChannelSummary? = null,
) {
    QuestionScreen(
        title = if (channel == null) SettingsStrings.QUESTION_VC_12 else SettingsStrings.LIMIT_LIGHTNING,
        answer = if (channel == null) SettingsStrings.QUESTION_VC_13 else questionVc7(channel),
        onDown = onDown,
        modifier = modifier,
        channel = channel,
    )
}

/** `questionvc7` with the channel's balance, reserve and send limit filled in. */
private fun questionVc7(channel: ChannelSummary): String =
    SettingsStrings.QUESTION_VC_7
        .replace("<channelbalance>", group(channel.balanceSats))
        .replace("<channelreserve>", group(channel.reserveSats))
        .replace("<sendlimit>", group(channel.outboundSats))

/**
 * `QuestionViewController`: `addHeader` with the piggy and the lower-case title, over the card
 * centred in the whole sheet — `yelloworblue2`, 13 corners and the iOS shadow, 15 from the
 * sheet's sides. The answer is Gilroy-Regular 16, centred, 25 in and 30 from the card's top, at
 * `attributed()`'s 1.28 line height; 30 of card under it, or the channel chart 20
 * under it and 15 in, when [channel] is given. iOS leaves only 10 under the text, which sits it
 * visibly high in the card; the 30 here centres it, a deliberate departure. `<b>` in [answer] is drawn bold, as iOS's
 * `attributed()`.
 */
@Composable
fun QuestionScreen(
    title: String,
    answer: String,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    channel: ChannelSummary? = null,
) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown),
    ) {
        val sheetHeight = maxHeight
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = sheetHeight)
                .padding(horizontal = 15.dp, vertical = 58.dp),
        ) {
            BittrCard(
                fill = BittrTheme.colors.levelCard,
                contentPadding = PaddingValues(
                    start = 25.dp,
                    end = 25.dp,
                    top = 30.dp,
                    bottom = if (channel == null) 30.dp else 0.dp,
                ),
                modifier = Modifier.testTag(TestID.Question.yellowCard),
            ) {
                Text(
                    text = boldTagged(answer),
                    // `attributed()`: Gilroy 16 at `line-height: 1.28`.
                    style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 20.48.sp),
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Question.answerLabel),
                )
                // The explanation first and the channel's figures under it, inside the same
                // card — the proposal's order (review, `send_lightning/01b`).
                if (channel != null) {
                    // 15 from the card's sides where the text is 25: 10 past the content on each.
                    Box(
                        Modifier
                            .padding(top = 30.dp, bottom = 15.dp)
                            .layout { measurable, constraints ->
                                val bleed = 10.dp.roundToPx()
                                val placeable = measurable.measure(
                                    constraints.copy(
                                        minWidth = constraints.minWidth + 2 * bleed,
                                        maxWidth = constraints.maxWidth + 2 * bleed,
                                    ),
                                )
                                layout(constraints.maxWidth, placeable.height) { placeable.place(-bleed, 0) }
                            },
                    ) {
                        ChannelChart(channel)
                    }
                }
            }
        }

        BittrSheetHeader(
            icon = painterResource(R.drawable.question_header_piggy),
            title = title.lowercase(),
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

/**
 * `channelView` with `setChannelChart(forChannel:)`'s figures: `whiteorblue3`, 8 corners and the iOS
 * shadow. "Your balance" and "Receive limit" in Gilroy-Bold 14 (`blackoryellow`) 17 from the top and
 * 15 from either side, each figure 5 under its title in Regular 13 at 90 %; 13 under those the 6 pt
 * bar — the balance in yellow over the darker gold track, 2 corners — and 13 under it the total and
 * reserve, centred, 15 from the bottom.
 */
@Composable
private fun ChannelChart(channel: ChannelSummary) {
    val colors = BittrTheme.colors
    val ink = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.9f)
    val title = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp)
    val figure = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp, lineHeight = 13.sp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .iosShadow(ChartShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, ChartShape)
            .padding(start = 15.dp, end = 15.dp, top = 17.dp, bottom = 15.dp)
            .testTag(TestID.Question.channelView),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.weight(1f)) {
                Text(SettingsStrings.YOUR_BALANCE, style = title, color = colors.emphasis)
                Text(group(channel.balanceSats), style = figure, color = ink, modifier = Modifier.padding(top = 5.dp))
            }
            Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                Text(SettingsStrings.RECEIVE_LIMIT, style = title, color = colors.emphasis)
                Text(group(channel.receiveLimitSats), style = figure, color = ink, modifier = Modifier.padding(top = 5.dp))
            }
        }
        Box(
            modifier = Modifier
                .padding(top = 13.dp)
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(colors.barTrack),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(channel.balanceFraction)
                    .background(colors.brandFixed),
            )
        }
        Text(
            text = "${group(channel.valueSats)} ${SettingsStrings.TOTAL}, ${group(channel.reserveSats)} ${SettingsStrings.RESERVE}",
            style = figure,
            color = ink,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = 13.dp)
                .fillMaxWidth(),
        )
    }
}

private val ChartShape = RoundedCornerShape(8.dp)

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
