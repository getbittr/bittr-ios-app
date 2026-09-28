package com.bittr.android.feature.signup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

/**
 * Android counterpart of iOS `Signup3ViewController` — the twelve words.
 *
 * Laid out as the storyboard's scene is: the two labels 40 from the screen edges, then
 * `mnemonicView` — the canvas-coloured card with 13 pt corners and `setShadow()`, fixed at 250
 * wide — holding the twelve words, then Next and the article card. Too tall for a phone, so it
 * scrolls, as iOS's does once `viewDidAppear` finds the centre view taller than the screen.
 *
 * The word rows carry `signup.create.mnemonic.word1…word12`, which is what the
 * Maestro flow reads them by; `wordAt` keeps the 1-based numbering iOS uses rather
 * than letting the list index leak into a test id.
 *
 * **The index number is brand yellow**, as iOS draws it in `yellow` on the white word row. That
 * measures 1.7 : 1, the pairing DEV-40 darkened for `DetailRow` labels; matched to iOS on this
 * screen at Tom's request, as Restore's numbers are.
 *
 * **No "Copy to clipboard".** The mock offers it under Next. Putting a seed phrase on
 * the system clipboard hands it to every app with a foreground read, and iOS does not
 * do it — `becareful`/`noscreenshot` is the copy iOS shows *instead*. If it is wanted
 * it is a decision with a security review attached, not a button this screen adds.
 */
@Composable
fun MnemonicScreen(
    mnemonic: Mnemonic,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    onOpenArticle: ((String) -> Unit)? = null,
) {
    BackHandler(enabled = onBack != null) { onBack?.invoke() }
    // No arrow in the app bar, as on iOS; the system back gesture goes back when there is a back.
    BittrCanvas(modifier = modifier) {
        // The storyboard's centre view: 30 above the first label, 40 below the article card.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(top = 30.dp, bottom = 40.dp),
        ) {
            Text(
                text = SignupStrings.RECOVERY_PHRASE,
                // Gilroy Bold 16, centred, 40 from the screen edges.
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .testTag(TestID.Signup.Create.Mnemonic.topLabelOne),
            )
            CanvasSpacer(15.dp)
            Text(
                text = SignupStrings.RECOVERY_PHRASE_2,
                // Gilroy Regular 16, `blackorwhite` like the label above.
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 20.sp),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 40.dp),
            )
            CanvasSpacer(30.dp)

            // `mnemonicView`: 250 wide, `yelloworblue1`, 13 pt corners and `setShadow()` — BittrCard's
            // own look, as Signup1's `centerCard` is. The stack inside is 10 from its top and bottom.
            BittrCard(
                contentPadding = PaddingValues(vertical = 10.dp),
                modifier = Modifier.width(MnemonicCardWidth),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Signup.Create.Mnemonic.mnemonicStack),
                ) {
                    mnemonic.words.forEachIndexed { index, word ->
                        WordRow(position = index, word = word)
                    }
                }
            }

            CanvasSpacer(30.dp)
            BittrPrimaryButton(
                text = SignupStrings.NEXT,
                onClick = onNext,
                modifier = Modifier.testTag(TestID.Signup.Create.Mnemonic.nextButton),
            )
            if (onOpenArticle != null) {
                CanvasSpacer(50.dp)
                // Signup3's `pageArticle1Slug = "wallet-recovery"`.
                ArticleCard(slug = BittrArticles.WALLET_RECOVERY, onOpen = onOpenArticle)
            }
        }
    }
}

/** The storyboard pins `mnemonicView` at 250 pt wide. */
private val MnemonicCardWidth = 250.dp

/**
 * One word, as `setMnemonic` builds it: a `whiteorblue3` row 40 tall with 8 pt corners, 10 in
 * from the card's sides and 50 below the one above. The number 20 in, the word centred on the
 * row — so twelve words of different lengths line up as a column — both in Gilroy Bold 16 and
 * 1.5 pt below the row's centre.
 */
@Composable
private fun WordRow(position: Int, word: String) {
    val labelStyle = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp, lineHeight = 16.sp)
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .padding(horizontal = 10.dp)
            .fillMaxWidth()
            .height(40.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, WordRowShape)
            .offset(y = 1.5.dp),
    ) {
        Text(
            text = "${position + 1}",
            style = labelStyle,
            color = BittrTheme.colors.brandFixed,
            modifier = Modifier.padding(start = 20.dp),
        )
        Text(
            text = word,
            style = labelStyle,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Mnemonic.wordAt(position)),
        )
    }
}

private val WordRowShape = RoundedCornerShape(8.dp)

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
