package com.bittr.android.feature.signup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.bittrSwitchColors
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

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
    onOpenArticle: ((String) -> Unit)? = null,
) {
    var ownBank by remember { mutableStateOf(false) }
    var noRecovery by remember { mutableStateOf(false) }

    BackHandler(onBack = onBack)
    // No arrow in the app bar: the card's own button goes back, as on iOS, and the system back
    // gesture does what that button does.
    BittrCanvas(modifier = modifier, background = BittrTheme.colors.primaryHigh) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                // iOS's `centerCard` sits 15 pt from the screen edges.
                .padding(horizontal = 15.dp),
        ) {
            // Signup2's storyboard: the title 30 from the top and 25 from the sides, the
            // statements 30 below it and 20 from the sides, the button 40 below them, then
            // Cancel — 10 and a 25 pt row on iOS, then 20 to the card's bottom: 55 below the
            // button. Cancel's 48 dp touch target takes 48 of those, so the bottom is 8.
            BittrCard(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 30.dp, bottom = 8.dp)) {
                Text(
                    text = SignupStrings.CHECK_AND_CONFIRM,
                    // Gilroy Bold 16; Gilroy's line gap puts iOS's lines at 1.24 of the size.
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .padding(horizontal = 5.dp)
                        .testTag(TestID.Signup.Create.Confirm.topLabel),
                )

                CanvasSpacer(30.dp)
                ToggleRow(
                    text = SignupStrings.CHECK_AND_CONFIRM_1,
                    checked = ownBank,
                    onCheckedChange = { ownBank = it },
                    testTag = TestID.Signup.Create.Confirm.switchOne,
                )
                CanvasSpacer(20.dp)
                ToggleRow(
                    text = SignupStrings.CHECK_AND_CONFIRM_2,
                    checked = noRecovery,
                    onCheckedChange = { noRecovery = it },
                    testTag = TestID.Signup.Create.Confirm.switchTwo,
                )
                CanvasSpacer(40.dp)

                BittrPrimaryButton(
                    text = SignupStrings.I_UNDERSTAND,
                    onClick = onUnderstood,
                    enabled = ownBank && noRecovery && !busy,
                    // iOS keeps the plate black while it is busy; light mode dims it.
                    dimmed = !(ownBank && noRecovery) || (busy && !BittrTheme.isDark),
                    modifier = Modifier.testTag(TestID.Signup.Create.Confirm.nextButton),
                    content = if (!busy) {
                        null
                    } else {
                        {
                            BittrSpinner(
                                strokeWidth = 2.dp,
                                color = if (BittrTheme.isDark) BittrTheme.colors.onActionFill else BittrTheme.colors.onActionFillDisabled,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    },
                )
                // iOS's `cancelButton`, back to Signup1 — `fresh_install_unhappy.yaml` taps it.
                BittrTextButton(
                    text = SignupStrings.CANCEL,
                    onClick = onBack,
                    color = BittrTheme.colors.cancelLabel,
                    modifier = Modifier.testTag(TestID.Signup.Create.Confirm.cancelButton),
                )
            }
            if (onOpenArticle != null) {
                CanvasSpacer(30.dp)
                // Signup2's `pageArticle1Slug = "what-is-a-bitcoin-wallet"`.
                ArticleCard(slug = BittrArticles.WHAT_IS_A_BITCOIN_WALLET, onOpen = onOpenArticle)
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
    // iOS: the switch, 20 pt, then the statement in Gilroy Regular 15, top-aligned with it.
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(20.dp),
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
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 18.5.sp),
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
