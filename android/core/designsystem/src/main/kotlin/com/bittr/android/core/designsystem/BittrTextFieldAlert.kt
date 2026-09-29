package com.bittr.android.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.bittr.android.core.common.TestID
import kotlinx.coroutines.flow.first

/**
 * An alert with one text field — iOS's `showTextFieldAlert(id:title:message:initialText:placeholder:…)`
 * in `AlertManager`, used for "Add a note" and the LNURL withdraw amount. [BittrAlert]'s card: the
 * header, the message when there is one, the white 45 pt field 25 under it and 20 in, and Cancel
 * and Save side by side 20 under the field. The field takes focus once the card is up, and the
 * card rides up with the keyboard.
 *
 * The same ids iOS gives it: the card carries [testTag] (`alert.addNote`, `alert.withdrawRequest`),
 * the field `alert.textField`, and the buttons `alert.button.0` (cancel) and `alert.button.1`
 * (save), in that order.
 */
@Composable
fun BittrTextFieldAlert(
    title: String,
    initialText: String,
    placeholder: String,
    cancelLabel: String,
    saveLabel: String,
    onCancel: () -> Unit,
    onSave: (String) -> Unit,
    modifier: Modifier = Modifier,
    message: String? = null,
    testTag: String? = null,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    var text by remember(initialText) { mutableStateOf(initialText) }
    val motion = rememberAlertMotion(title, initialText)
    if (motion.gone) return
    val focus = LocalFocusManager.current
    val field = remember { FocusRequester() }
    // `becomeFirstResponder` once the card has slid up.
    LaunchedEffect(motion) {
        snapshotFlow { motion.progress.value >= 0.99f }.first { it }
        runCatching { field.requestFocus() }
    }
    val buttons = listOf(
        BittrAlertButton(label = cancelLabel, dismissesAlert = true, onClick = onCancel),
        BittrAlertButton(label = saveLabel, onClick = { onSave(text) }),
    )

    Dialog(onDismissRequest = {}, properties = AlertDialogProperties) {
        AlertWindowSetup()
        AlertOverlay(
            motion = motion,
            onBack = onCancel,
            // On the keyboard while typing, as iOS lifts it; on the safe area otherwise.
            bottomInsets = WindowInsets.ime.union(WindowInsets.navigationBars),
            cardModifier = if (testTag != null) modifier.testTag(testTag) else modifier,
        ) {
            AlertCardContent(
                title = title,
                message = if (message.isNullOrEmpty()) null else {
                    {
                        Text(
                            text = bittrMarkup(message),
                            style = AlertMessageStyle,
                            color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                },
                buttons = buttons,
                motion = motion,
                field = {
                    // White, 45 tall at 8 corners; the text Gilroy-Regular 16 in black, 15 in.
                    Box(
                        contentAlignment = Alignment.CenterStart,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(45.dp)
                            .background(Color.White, RoundedCornerShape(8.dp))
                            .padding(horizontal = 15.dp),
                    ) {
                        if (text.isEmpty()) {
                            Text(placeholder, style = AlertMessageStyle, color = Color.Black.copy(alpha = 0.3f))
                        }
                        BasicTextField(
                            value = text,
                            onValueChange = { text = it },
                            singleLine = true,
                            textStyle = AlertMessageStyle.copy(color = Color.Black),
                            cursorBrush = SolidColor(Color.Black),
                            keyboardOptions = KeyboardOptions(
                                keyboardType = keyboardType,
                                capitalization = if (keyboardType == KeyboardType.Text) KeyboardCapitalization.Sentences else KeyboardCapitalization.None,
                                imeAction = ImeAction.Done,
                            ),
                            keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(field)
                                .testTag(TestID.Alert.textField),
                        )
                    }
                },
            )
        }
    }
}
