package com.bittr.android.feature.signup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The consent gate, asserted rather than assumed.
 *
 * "I understand" being *shown* while both switches are off is not the same as it being
 * disabled, and the difference is whether a user can generate a wallet without having
 * been told that losing the backup loses the coins. That is the one screen in the arc
 * where the enabled state carries the meaning.
 *
 * It also pins the four ids the flows select on — see `SignupStartScreenTestIdsTest`
 * for why a JVM test and a Maestro flow are not duplicates here.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class ConfirmScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private fun setContent(onUnderstood: () -> Unit = {}) {
        composeRule.setContent {
            BittrTheme {
                ConfirmScreen(onUnderstood = onUnderstood, onBack = {})
            }
        }
    }

    @Test
    fun `exposes the ids the flows select on`() {
        setContent()

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.topLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchTwo).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.nextButton).assertIsDisplayed()
    }

    @Test
    fun `I understand is disabled until both statements are confirmed`() {
        setContent()
        val next = composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.nextButton)

        next.assertIsNotEnabled()

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).performClick()
        next.assertIsNotEnabled()

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchTwo).performClick()
        next.assertIsEnabled()
    }

    @Test
    fun `a disabled I understand does not generate a wallet when tapped`() {
        var understood = 0
        setContent(onUnderstood = { understood++ })

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.nextButton).performClick()

        assertEquals(0, understood)
    }

    @Test
    fun `turning a statement back off closes the gate again`() {
        setContent()
        val next = composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.nextButton)

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).performClick()
        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchTwo).performClick()
        next.assertIsEnabled()

        composeRule.onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).performClick()
        next.assertIsNotEnabled()
    }
}
