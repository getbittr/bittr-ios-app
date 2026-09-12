package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrNumeral
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.BittrValueRow
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.seed.Bip39

/**
 * Android counterpart of iOS `RestoreViewController` — the twelve fields.
 *
 * Built out of the same [WordField] shape as [VerifyScreen], because on iOS they are
 * literally the same control (`MnemonicTextField`) and a user who has been through
 * signup should recognise it. The differences are that there are twelve of them and
 * that nothing on this screen knows what the right answer is — the verdict comes from
 * `SeedPhraseEntry` via [RestoreWalletViewModel].
 *
 * **Restore is never dimmed.** [VerifyScreen] dims Confirm until all three fields have
 * something in them; here the button stays live on an incomplete phrase so the
 * `incompletephrase` alert is reachable, which is iOS's behaviour and the only way the
 * user is told *which* of the twelve they missed is a thing they can be told at all.
 *
 * **No autofill, no autocorrect, no capitalisation.** A keyboard that turns `attack`
 * into `Attack` or offers to save the phrase to the password manager is the single
 * most common way this screen fails someone who wrote their words down correctly.
 *
 * **The typed words are not `rememberSaveable`.** Saved state is written to disk on
 * process death, so the fields deliberately lose their contents on rotation rather
 * than persist the whole seed in cleartext outside the Keystore. That is a worse
 * trade-off here than on Verify — it is twelve words, not three — which is exactly
 * why it is made the same way.
 *
 * What is not ported: the "wallet recovery" article chip, which needs the article
 * fetch BIT-7 owns, and `removeWalletButton`, which is the forgot-PIN and
 * remove-wallet entry point rather than part of restoring — `restore_wallet.yaml`
 * does not touch it and iOS keeps it hidden unless `resettingPin` is set.
 */
@Composable
fun RestoreScreen(
    onSubmit: (List<String>) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
) {
    val words = remember { mutableStateListOf(*Array(Bip39.WORD_COUNT) { "" }) }
    val focusRequesters = remember { List(Bip39.WORD_COUNT) { FocusRequester() } }
    val keyboard = LocalSoftwareKeyboardController.current

    fun submit() {
        keyboard?.hide()
        onSubmit(words.toList())
    }

    BittrCanvas(modifier = modifier, onBack = onCancel) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                // The twelve fields plus the keyboard are taller than any phone, so
                // the content has to move up out from under the IME rather than sit
                // behind it. iOS does this by hand in keyboardWillAppear.
                .imePadding()
                .padding(horizontal = CanvasGutter, vertical = BittrTokens.Spacing.lg),
        ) {
            BittrCard {
                BittrStepHeading(
                    text = SignupStrings.ENTER_RECOVERY_PHRASE,
                    modifier = Modifier.testTag(TestID.Signup.Restore.topLabel),
                )
                CanvasSpacer(BittrTokens.Spacing.xl)

                repeat(Bip39.WORD_COUNT) { index ->
                    if (index > 0) CanvasSpacer(12.dp)
                    val last = index == Bip39.WORD_COUNT - 1
                    WordField(
                        wordNumber = index + 1,
                        value = words[index],
                        onValueChange = { words[index] = it },
                        fieldTag = RestoreFieldTags[index],
                        last = last,
                        focusRequester = focusRequesters[index],
                        // Next walks the fields; Done on the twelfth submits, which
                        // is RestoreViewController's `textField.tag == 12` branch.
                        onImeAction = {
                            if (last) submit() else focusRequesters[index + 1].requestFocus()
                        },
                    )
                }

                CanvasSpacer(BittrTokens.Spacing.xl)
                BittrPrimaryButton(
                    text = SignupStrings.RESTORE_WALLET,
                    onClick = ::submit,
                    enabled = !busy,
                    modifier = Modifier.testTag(TestID.Signup.Restore.nextButton),
                )
                BittrTextButton(text = SignupStrings.CANCEL, onClick = onCancel)
            }
        }
    }
}

/**
 * `signup.restore.field1` … `field12`, in field order.
 *
 * Listed rather than built from `"signup.restore.field${i + 1}"` so the ids stay
 * greppable against `shared/test-ids/test-ids.json` and the iOS `viewDidLoad` that
 * assigns them — a generated string matches nothing when someone searches for where
 * a failing Maestro selector comes from.
 */
private val RestoreFieldTags = listOf(
    TestID.Signup.Restore.field1,
    TestID.Signup.Restore.field2,
    TestID.Signup.Restore.field3,
    TestID.Signup.Restore.field4,
    TestID.Signup.Restore.field5,
    TestID.Signup.Restore.field6,
    TestID.Signup.Restore.field7,
    TestID.Signup.Restore.field8,
    TestID.Signup.Restore.field9,
    TestID.Signup.Restore.field10,
    TestID.Signup.Restore.field11,
    TestID.Signup.Restore.field12,
)

/**
 * One numbered field. The restore twin of `VerifyScreen`'s private `WordField`.
 *
 * Kept separate rather than shared because this one has to drive focus to the next
 * field — twelve fields is enough that making the user tap each one is a real cost,
 * where three is not — and folding the focus plumbing into Verify's would complicate
 * the screen that does not need it.
 */
@Composable
private fun WordField(
    wordNumber: Int,
    value: String,
    onValueChange: (String) -> Unit,
    fieldTag: String,
    last: Boolean,
    focusRequester: FocusRequester,
    onImeAction: () -> Unit,
) {
    BittrValueRow {
        BittrNumeral(text = "$wordNumber", width = 22.dp)
        Box(
            contentAlignment = Alignment.CenterStart,
            modifier = Modifier
                .weight(1f)
                .padding(start = BittrTokens.Spacing.lg),
        ) {
            if (value.isEmpty()) {
                Text(
                    text = SignupStrings.ENTER_WORD,
                    style = MaterialTheme.typography.bodyLarge,
                    // A11Y-21: placeholders on a field fill use `onSurfaceVariant`,
                    // never `outline`.
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = LocalTextStyle.current.merge(
                    MaterialTheme.typography.labelLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = if (last) ImeAction.Done else ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { onImeAction() },
                    onDone = { onImeAction() },
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester)
                    .testTag(fieldTag),
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun RestoreScreenPreview() {
    BittrTheme {
        RestoreScreen(onSubmit = {}, onCancel = {})
    }
}
