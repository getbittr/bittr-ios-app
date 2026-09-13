package com.bittr.android.feature.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens

/**
 * The explanation card behind Device details → Lightning connections —
 * `ios/bittr/Question/QuestionViewController` in its `lightningexplanation` role.
 *
 * `DeviceViewController.checkChannels()` launches it with the `lightningchannels`
 * header and the `lightningexplanation1` body. That view controller has two shapes: a
 * channel chart plus balance figures when `getActiveChannel()` returns something, and
 * this — the plain card — when it does not.
 *
 * **This build is always in the second shape**, because a device with no node has no
 * channels, so what is ported is the whole of what is reachable rather than a subset
 * of it. `question.channelView` and the balance bar arrive with BIT-6, at which point
 * this screen grows the chart above the text.
 */
@Composable
fun LightningQuestionScreen(
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = SettingsStrings.LIGHTNING_CONNECTIONS_TITLE,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            BittrCard(modifier = Modifier.testTag(TestID.Question.yellowCard)) {
                BittrBody(
                    text = SettingsStrings.LIGHTNING_EXPLANATION,
                    textAlign = TextAlign.Start,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Question.answerLabel),
                )
            }
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun LightningQuestionScreenPreview() {
    BittrTheme {
        LightningQuestionScreen(onDown = {})
    }
}
