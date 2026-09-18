package com.bittr.android.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID

/**
 * An alert with one text field — iOS's `showTextFieldAlert(id:title:message:initialText:placeholder:…)`
 * in `AlertManager`, used for "Add a note" and the LNURL withdraw amount.
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
    val tagged = if (testTag != null) modifier.testTag(testTag) else modifier

    AlertDialog(
        onDismissRequest = onCancel,
        properties = DialogProperties(dismissOnClickOutside = false),
        containerColor = BittrTheme.colors.dialogContainer,
        titleContentColor = BittrTheme.colors.onDialogContainer,
        textContentColor = BittrTheme.colors.onDialogContainer,
        shape = BittrCanvasShapes.card,
        title = { BittrDialogTitle(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md)) {
                if (message != null) BittrDialogMessage(message)
                // A white 16 dp field, as every text field in the app — the note field was
                // Material's `surfaceContainerLowest` before, which the theme leaves unset.
                Box(
                    contentAlignment = Alignment.CenterStart,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .background(Color.White, BittrCanvasShapes.field)
                        .padding(horizontal = BittrTokens.Spacing.md),
                ) {
                    if (text.isEmpty()) {
                        Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = BittrTheme.colors.onCanvas.copy(alpha = 0.38f))
                    }
                    BasicTextField(
                        value = text,
                        onValueChange = { text = it },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = Color.Black),
                        cursorBrush = SolidColor(Color.Black),
                        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag(TestID.Alert.textField),
                    )
                }
            }
        },
        confirmButton = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs),
            ) {
                BittrTextButton(
                    text = cancelLabel,
                    onClick = onCancel,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Alert.buttonAt(0)),
                )
                BittrPrimaryButton(
                    text = saveLabel,
                    onClick = { onSave(text) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(BittrDialogButtonHeight)
                        .testTag(TestID.Alert.buttonAt(1)),
                    arrow = false,
                )
            }
        },
        // A dialog is its own window: see exposeTestTags.
        modifier = tagged.exposeTestTags(),
    )
}
