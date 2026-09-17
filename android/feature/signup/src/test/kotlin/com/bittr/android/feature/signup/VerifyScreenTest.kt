package com.bittr.android.feature.signup

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.seed.SeedChallenge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The keyboard must never leave Confirm unreachable: `seed_gate_rejects_wrong_words.yaml`
 * failed on the emulator because the button sat behind the keyboard after the third word.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class VerifyScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val submitted = mutableListOf<List<String>>()

    private fun setContent() {
        composeRule.setContent {
            BittrTheme {
                VerifyScreen(
                    challenge = SeedChallenge(
                        Mnemonic(
                            listOf(
                                "abandon", "ability", "able", "about", "above", "absent",
                                "absorb", "abstract", "absurd", "abuse", "access", "accident",
                            ),
                        ),
                        listOf(0, 5, 11),
                    ),
                    onSubmit = { submitted += it },
                    onBack = {},
                )
            }
        }
    }

    @Test
    fun `Next moves to the next word and Done on the last word submits`() {
        setContent()
        val field1 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field1)
        field1.performClick()
        field1.performTextInput("abandon")
        field1.performImeAction()
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).assertIsFocused()

        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).performTextInput("absent")
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).performImeAction()
        val field3 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field3)
        field3.assertIsFocused()
        field3.performTextInput("accident")
        field3.performImeAction()

        assertEquals(listOf(listOf("abandon", "absent", "accident")), submitted)
    }

    @Test
    fun `Done with an empty word only closes the keyboard`() {
        setContent()
        val field3 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field3)
        field3.performClick()
        field3.performTextInput("accident")
        field3.performImeAction()

        assertTrue(submitted.isEmpty())
        field3.assertIsNotFocused()
    }

    /**
     * `seed_gate_rejects_wrong_words.yaml` presses Confirm with a field empty and expects
     * `alert.missingWords`. That alert is the view model's; the screen's part is to let
     * the press through rather than dim the button and swallow it.
     */
    @Test
    fun `Confirm with an empty field still submits so the missing-words alert can fire`() {
        setContent()
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).performTextInput("absent")

        val confirm = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.nextButton)
        confirm.assertIsEnabled()
        confirm.performClick()

        assertEquals(listOf(listOf("", "absent", "")), submitted)
    }

    /**
     * `Signup4ViewController.textFieldDidEndEditing`: the third field losing focus with all
     * three words right submits. `happy_path_wallet.yaml` and the seed-gate flow both rely
     * on it — they tap the heading after the third word and expect the PIN screen.
     */
    @Test
    fun `the third field losing focus with the right words submits once`() {
        setContent()
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field1).performTextInput("abandon")
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).performTextInput("absent")
        val field3 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field3)
        field3.performClick()
        field3.performTextInput("accident")

        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.topLabel).performClick()

        assertEquals(listOf(listOf("abandon", "absent", "accident")), submitted)
    }

    /** The blur alone must not advance — only a match does; wrong words stay put. */
    @Test
    fun `the third field losing focus with wrong words does not submit`() {
        setContent()
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field1).performTextInput("abandon")
        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field2).performTextInput("zoo")
        val field3 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field3)
        field3.performClick()
        field3.performTextInput("accident")

        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.topLabel).performClick()

        assertTrue(submitted.isEmpty())
        field3.assertIsNotFocused()
    }

    @Test
    fun `tapping the heading closes the keyboard`() {
        setContent()
        val field1 = composeRule.onNodeWithTag(TestID.Signup.Create.Verify.field1)
        field1.performClick()
        field1.assertIsFocused()

        composeRule.onNodeWithTag(TestID.Signup.Create.Verify.topLabel).performClick()
        field1.assertIsNotFocused()
    }
}
