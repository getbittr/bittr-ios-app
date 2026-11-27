package com.bittr.android

import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.feature.receive.FiatCurrency
import com.bittr.android.feature.receive.ReceiveRoute
import com.bittr.android.feature.receive.ReceiveSource
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** iOS's `textFieldDidEndEditing` makes no code for a screen that is going away. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class ReceiveLeavingTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun `closing Receive with an amount typed makes no invoice`() {
        val source = Source()
        var shown by mutableStateOf(true)
        composeRule.runOnUiThread {
            composeRule.activity.setContent { BittrTheme { if (shown) ReceiveRoute(source, onDown = { shown = false }) } }
        }
        composeRule.waitForIdle()
        val made = source.invoices

        composeRule.onNodeWithTag(TestID.Receive.editButton).performClick()
        composeRule.onNodeWithTag(TestID.Receive.amountTextField).performClick().performTextInput("5000")
        composeRule.onNodeWithTag(TestID.Header.downButton).performClick()
        composeRule.waitForIdle()

        assertEquals(made, source.invoices)
    }

    private class Source : ReceiveSource {
        var invoices = 0
        override val addressesVerified = MutableStateFlow(true)
        override fun stopWaitingForAddresses() = Unit
        override fun lightningAvailable() = true
        override fun lightningAddress(): String? = null
        override fun currentOnchainAddress() = "bcrt1qyrwfhwsea2pexmp8qeg3y703kn4ky4xxk5e50e"
        override fun nextOnchainAddress(): String? = null
        override suspend fun zeroAmountInvoice(description: String) = "lnbcrt-zero".also { invoices++ }
        override suspend fun invoice(amountSats: Long, description: String) = "lnbcrt-$amountSats".also { invoices++ }
        override fun fiatCurrency() = FiatCurrency("CHF", "CHF")
        override suspend fun fiatPricePerBitcoin() = 50_000.0
    }
}
