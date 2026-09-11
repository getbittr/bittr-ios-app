package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.seed.SeedChallenge

/**
 * Android counterpart of iOS `Signup4ViewController` — type three of the words back.
 *
 * The gate itself is [SeedChallenge], not this file: whether an answer is accepted is
 * decided in pure Kotlin, tested in `SeedChallengeTest`, and the composable only
 * collects strings and reports the verdict. BIT-19 records that iOS has no negative
 * coverage here at all, which is the reason the check lives somewhere a unit test can
 * reach it.
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(BittrTokens.Spacing.gutter),
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
    ) {
        Text(
            text = SignupStrings.CONFIRM_RECOVERY_PHRASE,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.testTag(TestID.Signup.Create.Verify.topLabel),
        )

        challenge.labels.forEachIndexed { index, wordNumber ->
            // The word number is a label *beside* the field, as on iOS, not Material's
            // floating label inside it. As a floating label it reads as the field's
            // own placeholder — a lone "5" sitting where the answer goes, with no hint
            // that it means "the fifth word".
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = "$wordNumber",
                    style = MaterialTheme.typography.titleLarge,
                    textAlign = TextAlign.End,
                    modifier = Modifier
                        .width(36.dp)
                        .testTag(labelTags[index]),
                )
                OutlinedTextField(
                    value = answers[index],
                    onValueChange = { answers[index] = it },
                    singleLine = true,
                    placeholder = { Text(SignupStrings.ENTER_WORD) },
                    // No autocorrect and no capitalisation: the keyboard "helpfully"
                    // turning `abandon` into `Abandon` or into a different word is the
                    // single most common way this screen fails for a user who did
                    // write the phrase down correctly.
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = if (index == SeedChallenge.ASK_COUNT - 1) {
                            ImeAction.Done
                        } else {
                            ImeAction.Next
                        },
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .testTag(fieldTags[index]),
                )
            }
        }

        Button(
            onClick = { onSubmit(answers.toList()) },
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Verify.nextButton),
        ) {
            Text(SignupStrings.CONFIRM)
        }

        TextButton(
            onClick = onBack,
            colors = ButtonDefaults.textButtonColors(
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Verify.backButton),
        ) {
            Text(SignupStrings.BACK)
        }
    }
}

@Preview(showBackground = true)
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
