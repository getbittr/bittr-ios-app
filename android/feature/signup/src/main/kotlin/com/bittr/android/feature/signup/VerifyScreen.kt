package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.ui.graphics.SolidColor
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
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.seed.SeedChallenge

/**
 * Android counterpart of iOS `Signup4ViewController` — type three of the words back.
 * Artboards 05 and 06.
 *
 * The gate itself is [SeedChallenge], not this file: whether an answer is accepted is
 * decided in pure Kotlin, tested in `SeedChallengeTest`, and the composable only
 * collects strings and reports the verdict. BIT-19 records that iOS has no negative
 * coverage here at all, which is the reason the check lives somewhere a unit test can
 * reach it.
 *
 * **Confirm dims until all three fields have something in them**, which is the mock's
 * `dim` state and better than iOS's "press it and get told off". The
 * `SeedCheck.Missing` branch behind it is *not* dead code — `isNotBlank` lets a field
 * of spaces through to it, which is exactly the input that should be told it is empty
 * rather than told it is wrong.
 *
 * **The typed words are not `rememberSaveable`.** Three of the twelve words are still
 * three of the twelve; saved state is written to disk on process death, so the fields
 * deliberately lose their contents on rotation rather than persist a third of the
 * user's seed outside the Keystore.
 */
@Composable
fun VerifyScreen(
    challenge: SeedChallenge,
    onSubmit: (List<String>) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val answers = remember(challenge) {
        mutableStateListOf(*Array(SeedChallenge.ASK_COUNT) { "" })
    }
    val fieldTags = listOf(
        TestID.Signup.Create.Verify.field1,
        TestID.Signup.Create.Verify.field2,
        TestID.Signup.Create.Verify.field3,
    )
    val labelTags = listOf(
        TestID.Signup.Create.Verify.label1,
        TestID.Signup.Create.Verify.label2,
        TestID.Signup.Create.Verify.label3,
    )

    BittrCanvas(modifier = modifier, onBack = onBack) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CanvasGutter),
        ) {
            BittrCard {
                BittrStepHeading(
                    text = SignupStrings.CONFIRM_RECOVERY_PHRASE,
                    modifier = Modifier.testTag(TestID.Signup.Create.Verify.topLabel),
                )
                CanvasSpacer(BittrTokens.Spacing.xl)

                challenge.labels.forEachIndexed { index, wordNumber ->
                    if (index > 0) CanvasSpacer(12.dp)
                    WordField(
                        wordNumber = wordNumber,
                        value = answers[index],
                        onValueChange = { answers[index] = it },
                        labelTag = labelTags[index],
                        fieldTag = fieldTags[index],
                        last = index == SeedChallenge.ASK_COUNT - 1,
                    )
                }

                CanvasSpacer(BittrTokens.Spacing.xl)
                BittrPrimaryButton(
                    text = SignupStrings.CONFIRM,
                    onClick = { onSubmit(answers.toList()) },
                    enabled = answers.all { it.isNotBlank() },
                    modifier = Modifier.testTag(TestID.Signup.Create.Verify.nextButton),
                )
                BittrTextButton(
                    text = SignupStrings.BACK,
                    onClick = onBack,
                    modifier = Modifier.testTag(TestID.Signup.Create.Verify.backButton),
                )
            }
        }
    }
}

/**
 * One white field with its word number in it.
 *
 * The number is a label *inside* the field's container but outside its text, as on
 * iOS and in the mock — not Material's floating label. As a floating label it reads as
 * the field's own placeholder: a lone "5" sitting where the answer goes, with no hint
 * that it means "the fifth word".
 *
 * [BasicTextField] rather than `OutlinedTextField` because the mock's field has no
 * outline, no floating label and no 16 dp of Material's internal padding — reskinning
 * `OutlinedTextField` this far means fighting every one of its defaults.
 */
@Composable
private fun WordField(
    wordNumber: Int,
    value: String,
    onValueChange: (String) -> Unit,
    labelTag: String,
    fieldTag: String,
    last: Boolean,
) {
    BittrValueRow {
        BittrNumeral(
            text = "$wordNumber",
            width = 22.dp,
            modifier = Modifier.testTag(labelTag),
        )
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
                    // never `outline`. The mock's #B7B7B7 is 2.3 : 1 on white.
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
                // No autocorrect and no capitalisation: the keyboard "helpfully"
                // turning `abandon` into `Abandon` or into a different word is the
                // single most common way this screen fails for a user who did write
                // the phrase down correctly.
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = if (last) ImeAction.Done else ImeAction.Next,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(fieldTag),
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun VerifyScreenPreview() {
    BittrTheme {
        VerifyScreen(
            challenge = SeedChallenge(
                Mnemonic(
                    listOf(
                        "abandon", "ability", "able", "about", "above", "absent",
                        "absorb", "abstract", "absurd", "abuse", "access", "accident",
                    ),
                ),
                listOf(0, 5, 11),
            ),
            onSubmit = {},
            onBack = {},
        )
    }
}
