package com.bittr.android.feature.signup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.seed.SeedWalletService
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

private class ArcStore : SecureStore {
    private val values = mutableMapOf<String, ByteArray>()
    override fun read(key: String): ByteArray? = values[key]
    override fun write(key: String, value: ByteArray) { values[key] = value }
    override fun contains(key: String): Boolean = key in values
    override fun remove(key: String) { values.remove(key) }
}

/**
 * Walks `shared/flows/onboarding/restore_wallet.yaml` on the JVM, selecting on the
 * same ids Maestro does.
 *
 * This is the fast half of that flow, and it is what closes BIT-96's "the flow's steps
 * are all reachable on Android": driving it under Maestro in CI stays with BIT-7, and
 * the Android runner is not stood up yet, so without this the claim would rest on
 * reading the code. Every `tapOn` / `assertVisible` id in the flow between the restore
 * button and Home appears below, in flow order.
 *
 * It does not replace the Maestro run and cannot. Robolectric reads the Compose
 * semantics tree directly, so it passes with or without `testTagsAsResourceId` — the
 * `MainActivity` setting that is what actually makes these tags visible to Maestro.
 * `TestTagsAsResourceIdGuardTest` covers that end; only the emulator proves both
 * together.
 *
 * Two steps of the flow are deliberately absent: `signup.create.start.restoreButton`,
 * which `SignupStartScreenTestIdsTest` already asserts, and `home.headerLabel`, which
 * is in `:app`. [restoresAndLandsOnTheHandOffToHome] asserts the hand-off itself —
 * the callback `BittrNavHost` turns into the navigate to Home.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class RestoreArcTestIdsTest {

    @get:Rule
    val composeRule = createComposeRule()

    /** The phrase the flow types, word by word, in field order. */
    private val flowWords = listOf(
        "attack", "urge", "across", "cupboard", "year", "armor",
        "list", "vital", "outer", "leader", "anxiety", "endorse",
    )

    private val fieldTags = listOf(
        TestID.Signup.Restore.field1,
        TestID.Signup.Restore.field2,
        TestID.Signup.Restore.field3,
        TestID.Signup.Restore.field4,
        TestID.Signup.Restore.field5,
        TestID.Signup.Restore.field6,
        TestID.Signup.Restore.field7,
        TestID.Signup.Restore.field8,
        TestID.Signup.Restore.field9,
        TestID.Signup.Restore.field10,
        TestID.Signup.Restore.field11,
        TestID.Signup.Restore.field12,
    )

    private val pinTags = listOf(
        TestID.Pin.button1,
        TestID.Pin.button2,
        TestID.Pin.button3,
        TestID.Pin.button4,
    )

    @Test
    fun restoresAndLandsOnTheHandOffToHome() {
        var finished = false
        val viewModel = RestoreWalletViewModel(SeedWalletService(ArcStore()))

        composeRule.setContent {
            BittrTheme {
                RestoreWalletScreen(
                    onFinished = { finished = true },
                    onCancelled = {},
                    viewModel = viewModel,
                )
            }
        }

        // --- RestoreViewController: the twelve fields ------------------------
        composeRule.onNodeWithTag(TestID.Signup.Restore.topLabel).assertIsDisplayed()
        fieldTags.forEachIndexed { index, tag ->
            composeRule.onNodeWithTag(tag).performScrollTo().performTextInput(flowWords[index])
        }
        composeRule.onNodeWithTag(TestID.Signup.Restore.nextButton).performScrollTo().performClick()

        // --- Restore2: set the PIN ------------------------------------------
        awaitTag(TestID.Signup.Restore.PinSet.topLabel)
        composeRule.onNodeWithTag(TestID.Signup.Restore.PinSet.topLabel).assertIsDisplayed()
        // 1234, matching helpers/unlock.yaml so later feature tests still unlock.
        pinTags.forEach { composeRule.onNodeWithTag(it).performClick() }
        composeRule.onNodeWithTag(TestID.Pin.confirmButton).performClick()

        // --- Restore3: confirm it -------------------------------------------
        awaitTag(TestID.Signup.Restore.PinConfirm.topLabel)
        composeRule.onNodeWithTag(TestID.Signup.Restore.PinConfirm.topLabel).assertIsDisplayed()
        pinTags.forEach { composeRule.onNodeWithTag(it).performClick() }
        composeRule.onNodeWithTag(TestID.Pin.confirmButton).performClick()

        composeRule.waitUntil(TIMEOUT_MS) { finished }
        assertTrue("Restore3 must hand off to Home", finished)
    }

    /** The rejection the user sees: the flow's screen, with one word mistyped. */
    @Test
    fun aBadWordKeepsTheUserOnTheFieldsWithTheAlertUp() {
        val viewModel = RestoreWalletViewModel(SeedWalletService(ArcStore()))

        composeRule.setContent {
            BittrTheme {
                RestoreWalletScreen(onFinished = {}, onCancelled = {}, viewModel = viewModel)
            }
        }

        fieldTags.forEachIndexed { index, tag ->
            val word = if (index == 0) "attck" else flowWords[index]
            composeRule.onNodeWithTag(tag).performScrollTo().performTextInput(word)
        }
        composeRule.onNodeWithTag(TestID.Signup.Restore.nextButton).performScrollTo().performClick()

        // The alert's dismiss button carries alert.button.0, which is what the iOS
        // flows tap — BIT-78 aligned those ids across the two platforms.
        awaitTag(TestID.Alert.buttonAt(0))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()

        // Dismissing leaves the user on the fields. `assertExists`, not
        // `assertIsDisplayed`: filling twelve fields scrolls the heading off the top,
        // and "you can still see the title" is not the claim — "you did not advance"
        // is. So assert the next step is absent as well, which is the failure that
        // would actually cost someone money: a rejected phrase walking on to the PIN.
        composeRule.onNodeWithTag(TestID.Signup.Restore.topLabel).assertExists()
        composeRule.onNodeWithTag(TestID.Signup.Restore.nextButton).assertExists()
        composeRule.onNodeWithTag(TestID.Signup.Restore.PinSet.topLabel).assertDoesNotExist()
    }

    private fun awaitTag(tag: String) = composeRule.waitUntil(TIMEOUT_MS) {
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private companion object {
        const val TIMEOUT_MS = 5_000L
    }
}
