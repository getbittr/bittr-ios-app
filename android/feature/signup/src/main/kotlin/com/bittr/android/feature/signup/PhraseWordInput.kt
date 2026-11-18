package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.BittrTheme

/**
 * The word in a recovery phrase field on Restore and Verify: Gilroy Regular 18 with a gray
 * placeholder, and the keyboard settings every phrase field needs. The screens wrap it in
 * `NoKeyboardLearning`.
 *
 * No autocorrect and no capitalisation: the keyboard "helpfully" turning `abandon` into `Abandon`
 * or into a different word is the single most common way these screens fail for a user who did
 * write the phrase down correctly.
 */
@Composable
internal fun PhraseWordInput(
    value: String,
    onValueChange: (String) -> Unit,
    last: Boolean,
    onNext: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    fieldModifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    val wordStyle = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 22.sp)
    Box(contentAlignment = Alignment.CenterStart, modifier = modifier) {
        if (value.isEmpty()) {
            Text(
                text = SignupStrings.ENTER_WORD,
                style = wordStyle,
                color = colors.phrasePlaceholder,
                maxLines = 1,
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = wordStyle.copy(color = colors.onPhraseCard),
            cursorBrush = SolidColor(colors.onPhraseCard),
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                imeAction = if (last) ImeAction.Done else ImeAction.Next,
            ),
            keyboardActions = KeyboardActions(
                onNext = { onNext() },
                onDone = { onDone() },
            ),
            modifier = Modifier.fillMaxWidth().then(fieldModifier),
        )
    }
}
