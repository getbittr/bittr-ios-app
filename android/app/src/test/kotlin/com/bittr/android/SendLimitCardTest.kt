package com.bittr.android

import androidx.activity.compose.setContent
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.ChannelSummary
import com.bittr.android.feature.settings.LightningSendableQuestionScreen
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Send's "why a limit for instant payments?" card, in iOS's two `lightningsendable` shapes. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class SendLimitCardTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private fun show(channel: ChannelSummary?) {
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                BittrTheme { LightningSendableQuestionScreen(onDown = {}, channel = channel) }
            }
        }
        composeRule.waitForIdle()
    }

    @Test
    fun `with an active channel the card shows the chart and the send limit`() {
        show(ChannelSummary(valueSats = 200_000, outboundSats = 48_000, reserveSats = 2_000))

        composeRule.onNodeWithTag(TestID.Question.channelView).assertExists()
        composeRule.onNodeWithTag(TestID.Header.titleLabel).assert(hasText("why a limit for instant payments?"))
        composeRule.onNodeWithTag(TestID.Question.answerLabel)
            .assert(hasText("so you can send up to 48 000 sats", substring = true))
    }

    @Test
    fun `without a channel the card says there is no lightning connection`() {
        show(null)

        composeRule.onNodeWithTag(TestID.Question.channelView).assertDoesNotExist()
        composeRule.onNodeWithTag(TestID.Header.titleLabel).assert(hasText("why can't i receive instant payments?"))
        composeRule.onNodeWithTag(TestID.Question.answerLabel)
            .assert(hasText("You don't currently have a lightning connection.", substring = true))
    }
}
