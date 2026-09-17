package com.bittr.android.push

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.activity.compose.setContent
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import com.bittr.android.MainActivity
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * iOS adds push alerts to `CoreViewController`, under a modal transaction screen. buy_incoming.yaml's
 * first deposit gets bittr's "Payment amount mismatch" answer while the purchase summary is up, and
 * on Android it covered the summary.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PushAlertOverlayTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private fun composeContent(content: @androidx.compose.runtime.Composable () -> Unit) {
        composeRule.runOnUiThread { composeRule.activity.setContent { content() } }
    }

    private val mismatch = PushAlert(null, "Bittr payout", "Payment amount mismatch.", listOf(PushAlertButton("Close", dismisses = true)))
    private val question = PushAlert(null, "Bittr payout", "You're receiving a payment.", listOf(PushAlertButton("Okay", dismisses = true)))

    private fun shownCount(message: String) = composeRule.onAllNodesWithText(message).fetchSemanticsNodes().size

    @Test
    fun `an alert raised while a transaction is open waits until it closes`() {
        var transactionOpen by mutableStateOf(true)
        composeContent { PushAlertOverlay(mismatch, transactionOpen) {} }
        assertEquals(0, shownCount("Payment amount mismatch."))

        transactionOpen = false
        composeRule.waitForIdle()
        assertEquals(1, shownCount("Payment amount mismatch."))
    }

    @Test
    fun `an alert already showing stays when a transaction opens`() {
        var transactionOpen by mutableStateOf(false)
        composeContent { PushAlertOverlay(question, transactionOpen) {} }
        composeRule.waitForIdle()
        assertEquals(1, shownCount("You're receiving a payment."))

        transactionOpen = true
        composeRule.waitForIdle()
        assertEquals(1, shownCount("You're receiving a payment."))
    }
}
