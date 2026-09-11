package com.bittr.android.feature.signup

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrNumeral
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.Mnemonic

/**
 * Android counterpart of iOS `Signup3ViewController` — the twelve words. Artboard 04.
 *
 * The word rows carry `signup.create.mnemonic.word1…word12`, which is what the
 * Maestro flow reads them by; `wordAt` keeps the 1-based numbering iOS uses rather
 * than letting the list index leak into a test id.
 *
 * **The index number is not brand yellow**, here or in the mock's palette. iOS draws
 * it in `yellow` on the white word card, which measures 1.7 : 1 — invisible to a good
 * fraction of users and a fail under WCAG 1.4.3 for what is, in a 12-word list,
 * load-bearing information. See [BittrNumeral].
 *
 * **No "Copy to clipboard".** The mock offers it under Next. Putting a seed phrase on
 * the system clipboard hands it to every app with a foreground read, and iOS does not
 * do it — `becareful`/`noscreenshot` is the copy iOS shows *instead*. If it is wanted
 * it is a decision with a security review attached, not a button this screen adds.
 *
 * The list is 12 rows of 36 dp and fits an unscrolled 891 dp screen; the scroll is
 * there for the large end of dynamic type, where it is the difference between reading
 * word 12 and not having word 12.
 */
@Composable
fun MnemonicScreen(
    mnemonic: Mnemonic,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    BittrCanvas(modifier = modifier, onBack = onBack) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CanvasGutter),
        ) {
            BittrStepHeading(
                text = SignupStrings.RECOVERY_PHRASE,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(TestID.Signup.Create.Mnemonic.topLabelOne),
            )
            CanvasSpacer(8.dp)
            Text(
                text = SignupStrings.RECOVERY_PHRASE_2,
                style = MaterialTheme.typography.bodyMedium,
                color = BittrTheme.colors.mutedOnCanvas,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            CanvasSpacer(12.dp)

            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BittrTheme.colors.cardWash, BittrCanvasShapes.card)
                    .padding(8.dp)
                    .testTag(TestID.Signup.Create.Mnemonic.mnemonicStack),
            ) {
                mnemonic.words.forEachIndexed { index, word ->
                    WordRow(position = index, word = word)
                }
            }

            CanvasSpacer(12.dp)
            BittrPrimaryButton(
                text = SignupStrings.NEXT,
                onClick = onNext,
                compact = true,
                modifier = Modifier.testTag(TestID.Signup.Create.Mnemonic.nextButton),
            )
            CanvasSpacer(12.dp)
        }
    }
}

/**
 * One word: the index hard left, the word optically centred in the row.
 *
 * The word is centred against the *row*, not against the space left of the index,
 * which is why it is a [Box] overlay rather than a weighted [Row] cell — twelve words
 * of different lengths have to line up as a column or the phrase is hard to read back.
 */
@Composable
private fun WordRow(position: Int, word: String) {
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 36.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, BittrCanvasShapes.wordRow)
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        BittrNumeral(text = "${position + 1}", width = 20.dp)
        Text(
            text = word,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Mnemonic.wordAt(position)),
        )
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
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
