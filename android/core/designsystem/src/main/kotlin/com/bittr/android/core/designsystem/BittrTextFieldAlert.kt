package com.bittr.android.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
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
        containerColor = MaterialTheme.colorScheme.surface,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        textContentColor = MaterialTheme.colorScheme.onSurface,
        title = {
            Text(
                text = title,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md)) {
                if (message != null) {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                        .padding(BittrTokens.Spacing.md),
                ) {
                    if (text.isEmpty()) {
                        Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    BasicTextField(
                        value = text,
                        onValueChange = { text = it },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
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
                        .testTag(TestID.Alert.buttonAt(1)),
                    arrow = false,
                    compact = true,
                )
            }
        },
        // A dialog is its own window: see exposeTestTags.
        modifier = tagged.exposeTestTags(),
    )
}
