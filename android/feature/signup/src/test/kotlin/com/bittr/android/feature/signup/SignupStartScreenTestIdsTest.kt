package com.bittr.android.feature.signup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Asserts that the screen exposes exactly the test IDs
 * `shared/flows/android/scaffold_smoke.yaml` selects on.
 *
 * This is not a duplicate of the Maestro flow — it is the fast half of it. Deleting
 * or renaming a `testTag` is a one-character change that Maestro only catches after
 * a full emulator boot, and the failure it reports ("element not found") looks
 * identical to a broken emulator. This runs on the JVM in seconds and names the
 * exact tag that went missing.
 *
 * What it deliberately does NOT cover: `testTagsAsResourceId`, which lives on the
 * root in `MainActivity` and is what makes these tags visible to Maestro at all.
 * Robolectric reads the Compose semantics tree directly and so passes with or
 * without it. Only the emulator run proves that end of it.
 *
 * If you add a `testTag` to this screen, add it here too.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class SignupStartScreenTestIdsTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `exposes the test IDs the smoke flow asserts on`() {
        composeRule.setContent {
            BittrTheme {
                SignupStartScreen()
            }
        }

        composeRule.onNodeWithTag(TestID.Signup.Create.Start.headerLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.createWalletButton).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Create.Start.restoreButton).assertIsDisplayed()
    }
}
