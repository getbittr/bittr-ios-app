package com.bittr.android.core.designsystem

import android.view.View
import android.view.inputmethod.EditorInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** [NoKeyboardLearning]: the flag reaches the keyboard for a field inside it, and only there. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class NoKeyboardLearningTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private lateinit var view: View

    /** What the keyboard is told once the field is tapped. */
    private fun editorInfoFor(field: @Composable () -> Unit): EditorInfo {
        composeRule.setContent {
            view = LocalView.current
            field()
        }
        composeRule.onNodeWithTag(FIELD).performClick()
        composeRule.waitForIdle()
        val info = EditorInfo()
        composeRule.runOnUiThread { view.onCreateInputConnection(info) }
        return info
    }

    private val EditorInfo.learns: Boolean
        get() = imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING == 0

    @Test
    fun `a field inside asks the keyboard not to learn`() {
        val info = editorInfoFor {
            NoKeyboardLearning { BasicTextField(value = "", onValueChange = {}, modifier = Modifier.testTag(FIELD)) }
        }
        assertFalse("imeOptions=0x%08X".format(info.imeOptions), info.learns)
    }

    @Test
    fun `a field outside is left as it was`() {
        val info = editorInfoFor {
            BasicTextField(value = "", onValueChange = {}, modifier = Modifier.testTag(FIELD))
        }
        assertTrue("imeOptions=0x%08X".format(info.imeOptions), info.learns)
    }

    private companion object {
        const val FIELD = "field"
    }
}
