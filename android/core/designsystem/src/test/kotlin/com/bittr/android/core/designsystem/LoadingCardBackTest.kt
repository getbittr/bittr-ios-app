package com.bittr.android.core.designsystem

import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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

    private var screenBacks = 0
    private var screenTaps = 0

    private fun showOverScreen(overlay: @Composable () -> Unit) {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            BittrTheme {
                BackHandler { screenBacks++ }
                Box(Modifier.fillMaxSize().testTag(SCREEN).clickable { screenTaps++ })
                overlay()
            }
        }
        composeRule.mainClock.advanceTimeBy(2_000)
    }

    private fun pressBack() {
        composeRule.runOnUiThread { composeRule.activity.onBackPressedDispatcher.onBackPressed() }
        composeRule.mainClock.advanceTimeBy(2_000)
    }

    @Test
    fun `back leaves the loading card up and does not reach the screen underneath`() {
        showOverScreen { BittrLoadingCard(message = "receiving payment", testTag = CARD) }

        pressBack()
        composeRule.onNodeWithTag(SCREEN).performClick()

        composeRule.onNodeWithTag(CARD).assertExists()
        composeRule.onNodeWithText("receiving payment").assertIsDisplayed()
        assertEquals(0, screenBacks)
        assertEquals(0, screenTaps)
    }

    @Test
    fun `a card that has closed lets taps through to the screen underneath`() {
        showOverScreen {
            AlertOverlay(motion = rememberAlertMotion(), onBack = {}) { Text("closing") }
        }

        pressBack()
        composeRule.onNodeWithTag(SCREEN).performClick()

        assertEquals(1, screenTaps)
    }

    private companion object {
        const val SCREEN = "screen"
        const val CARD = "card"
    }
}
