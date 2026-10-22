package com.bittr.android.core.designsystem

import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The loading card cannot be dismissed, as on iOS. Back once slid it away and left its dim
 * behind, which swallowed every tap until loading ended: a frozen app with nothing on it.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class LoadingCardBackTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `back leaves the loading card up and does not reach the screen underneath`() {
        var screenBacks = 0
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            BittrTheme {
                BackHandler { screenBacks++ }
                BittrLoadingCard(message = "receiving payment")
            }
        }
        composeRule.mainClock.advanceTimeBy(2_000)

        composeRule.runOnUiThread { composeRule.activity.onBackPressedDispatcher.onBackPressed() }
        composeRule.mainClock.advanceTimeBy(2_000)

        composeRule.onNodeWithText("receiving payment").assertIsDisplayed()
        assertEquals(0, screenBacks)
    }
}
