package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.bittrSwitchColors

/**
 * Android counterpart of iOS `Signup2ViewController` — the two things the user has to
 * say they understand before a seed is generated. Artboards 02 and 03.
 *
 * **This step was missing from the arc, not deliberately dropped.** The ids
 * (`signup.create.confirm.switchOne`, `switchTwo`, `nextButton`) have been in
 * `shared/test-ids/test-ids.json` since the extraction, and the copy is verbatim
 * `Language.swift` (`checkandconfirm`, `checkandconfirm1`, `checkandconfirm2`,
 * `iunderstand`). The Android design shows it as artboards 02/03 with both toggles
 * off and both on, which is how it surfaced.
 *
 * The gate is real: **I understand** does nothing until both switches are on. That is
 * the iOS contract, and it is the only place in the arc where the user is told, before
 * anything irreversible happens, that a lost backup is a lost wallet.
 *
 * The toggles are not `rememberSaveable`. Coming back to this screen and finding
 * consent already granted is not the behaviour to persist.
 */
@Composable
fun ConfirmScreen(
    onUnderstood: () -> Unit,
    onBack: () -> Unit,
    busy: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var ownBank by remember { mutableStateOf(false) }
    var noRecovery by remember { mutableStateOf(false) }

    BittrCanvas(modifier = modifier, onBack = onBack) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = CanvasGutter),
        ) {
            BittrCard {
                BittrStepHeading(
                    text = SignupStrings.CHECK_AND_CONFIRM,
                    modifier = Modifier.testTag(TestID.Signup.Create.Confirm.topLabel),
                )

                CanvasSpacer(BittrTokens.Spacing.xl)
                ToggleRow(
                    text = SignupStrings.CHECK_AND_CONFIRM_1,
                    checked = ownBank,
                    onCheckedChange = { ownBank = it },
                    testTag = TestID.Signup.Create.Confirm.switchOne,
                )
                CanvasSpacer(BittrTokens.Spacing.lg)
                ToggleRow(
                    text = SignupStrings.CHECK_AND_CONFIRM_2,
                    checked = noRecovery,
                    onCheckedChange = { noRecovery = it },
                    testTag = TestID.Signup.Create.Confirm.switchTwo,
                )
                CanvasSpacer(BittrTokens.Spacing.xxl)

                BittrPrimaryButton(
                    text = SignupStrings.I_UNDERSTAND,
                    onClick = onUnderstood,
                    enabled = ownBank && noRecovery && !busy,
                    modifier = Modifier.testTag(TestID.Signup.Create.Confirm.nextButton),
                    content = if (!busy) {
                        null
                    } else {
                        {
                            CircularProgressIndicator(
                                strokeWidth = 2.dp,
                                color = BittrTheme.colors.onActionFill,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun ToggleRow(
    text: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    testTag: String,
) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = bittrSwitchColors(),
            modifier = Modifier.testTag(testTag),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Start,
            modifier = Modifier.weight(1f),
        )
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun ConfirmScreenPreview() {
    BittrTheme {
        ConfirmScreen(onUnderstood = {}, onBack = {})
    }
}
