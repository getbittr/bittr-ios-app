package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.wallet.Mnemonic

/**
 * Android counterpart of iOS `Signup3ViewController` — the twelve words.
 *
 * The word rows carry `signup.create.mnemonic.word1…word12`, which is what the
 * Maestro flow reads them by; `wordAt` keeps the 1-based numbering iOS uses rather
 * than letting the list index leak into a test id.
 *
 * **The index number is not brand yellow.** iOS draws it in `yellow` on the white
 * word card, which measures 1.7:1 — invisible to a good fraction of users and a fail
 * under WCAG 1.4.3 for what is, in a 12-word list, load-bearing information. It uses
 * `onSurfaceVariant` here, the same substitution A11Y-15 and A11Y-21 already made
 * elsewhere in the token set.
 */
@Composable
fun MnemonicScreen(
    mnemonic: Mnemonic,
    onNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(BittrTokens.Spacing.gutter),
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
    ) {
        Text(
            text = SignupStrings.RECOVERY_PHRASE,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.testTag(TestID.Signup.Create.Mnemonic.topLabelOne),
        )
        Text(
            text = SignupStrings.RECOVERY_PHRASE_2,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Surface(
            color = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            shape = MaterialTheme.shapes.medium,
            tonalElevation = BittrTokens.Elevation.level3,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                modifier = Modifier
                    .padding(BittrTokens.Spacing.sm)
                    .testTag(TestID.Signup.Create.Mnemonic.mnemonicStack),
            ) {
                mnemonic.words.forEachIndexed { index, word ->
                    WordRow(position = index, word = word)
                }
            }
        }

        Button(
            onClick = onNext,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Mnemonic.nextButton),
        ) {
            Text(SignupStrings.NEXT)
        }
    }
}

@Composable
private fun WordRow(position: Int, word: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(
                horizontal = BittrTokens.Spacing.md,
                vertical = BittrTokens.Spacing.sm,
            ),
        ) {
            Text(
                text = "${position + 1}",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.width(24.dp),
            )
            Text(
                text = word,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .weight(1f)
                    .testTag(TestID.Signup.Create.Mnemonic.wordAt(position)),
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun MnemonicScreenPreview() {
    BittrTheme {
        MnemonicScreen(
            mnemonic = Mnemonic(
                listOf(
                    "abandon", "ability", "able", "about", "above", "absent",
                    "absorb", "abstract", "absurd", "abuse", "access", "accident",
                ),
            ),
            onNext = {},
        )
    }
}
