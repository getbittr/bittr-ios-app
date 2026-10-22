package com.bittr.android.core.designsystem

import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.PlatformTextInputInterceptor
import androidx.compose.ui.platform.PlatformTextInputMethodRequest
import androidx.compose.ui.platform.PlatformTextInputSession

/**
 * Asks the keyboard not to learn what is typed in the text fields inside [content] —
 * `IME_FLAG_NO_PERSONALIZED_LEARNING`. For the fields that take the recovery phrase: a keyboard
 * that learns its words keeps them in its dictionary, and Gboard can sync that dictionary off the
 * device.
 *
 * `KeyboardOptions` has no setting for it, so the flag is added to the `EditorInfo` Compose has
 * just filled in. It is a request: a keyboard that ignores it can still learn.
 */
@Composable
fun NoKeyboardLearning(content: @Composable () -> Unit) {
    InterceptPlatformTextInput(interceptor = NoLearningInterceptor, content = content)
}

private object NoLearningInterceptor : PlatformTextInputInterceptor {
    override suspend fun interceptStartInputMethod(
        request: PlatformTextInputMethodRequest,
        nextHandler: PlatformTextInputSession,
    ): Nothing {
        nextHandler.startInputMethod(
            object : PlatformTextInputMethodRequest {
                override fun createInputConnection(outAttributes: EditorInfo): InputConnection =
                    request.createInputConnection(outAttributes).also {
                        outAttributes.imeOptions =
                            outAttributes.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                    }
            },
        )
    }
}
