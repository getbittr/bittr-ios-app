package com.bittr.android.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * iOS sheets close on a swipe down, and the shared flows rely on it (`buy_incoming.yaml` leaves Buy
 * with `swipe: DOWN`). Buy doesn't scroll, which is the case the first version missed.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PullDownDismissTest {

    @get:Rule
    val composeRule = createComposeRule()

    private var dismissed = 0

    @Test
    fun `a swipe down on a screen that doesn't scroll closes it once`() {
        composeRule.setContent {
            Box(Modifier.fillMaxSize().dismissOnPullDown({ dismissed++ }).testTag("screen")) {
                Text("Buy")
            }
        }
        composeRule.onNodeWithTag("screen").performTouchInput { swipeDown() }
        composeRule.waitForIdle()
        assertEquals(1, dismissed)
    }

    @Test
    fun `a swipe down on scrolling content at its top closes it once`() {
        composeRule.setContent {
            Column(
                Modifier.fillMaxSize().dismissOnPullDown({ dismissed++ })
                    .verticalScroll(rememberScrollState()).testTag("screen"),
            ) {
                Box(Modifier.height(3000.dp))
            }
        }
        composeRule.onNodeWithTag("screen").performTouchInput { swipeDown() }
        composeRule.waitForIdle()
        assertEquals(1, dismissed)
    }

    @Test
    fun `a swipe up doesn't close`() {
        composeRule.setContent {
            Box(Modifier.fillMaxSize().dismissOnPullDown({ dismissed++ }).testTag("screen")) {
                Text("Buy")
            }
        }
        composeRule.onNodeWithTag("screen").performTouchInput { swipeUp() }
        composeRule.waitForIdle()
        assertEquals(0, dismissed)
    }
}
