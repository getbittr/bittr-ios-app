package com.bittr.android.core.designsystem

import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** [ScreenshotProtection]: `FLAG_SECURE` while a protected screen is up, and only then. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class ScreenshotProtectionTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val secure: Boolean
        get() = (composeRule.activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0

    @Test
    fun `the window is secure while a protected screen is up, and not after`() {
        var shown by mutableStateOf(true)
        composeRule.setContent { if (shown) ScreenshotProtection() }
        composeRule.waitForIdle()
        assertTrue(secure)

        shown = false
        composeRule.waitForIdle()
        assertFalse("Left set, every later screen would capture black", secure)
    }

    @Test
    fun `a protected page sliding out does not clear it under the one sliding in`() {
        var outgoing by mutableStateOf(true)
        var incoming by mutableStateOf(false)
        composeRule.setContent {
            if (outgoing) ScreenshotProtection()
            if (incoming) ScreenshotProtection()
        }
        composeRule.waitForIdle()

        incoming = true
        composeRule.waitForIdle()
        outgoing = false
        composeRule.waitForIdle()
        assertTrue("The incoming page is still up", secure)

        incoming = false
        composeRule.waitForIdle()
        assertFalse(secure)
    }
}
