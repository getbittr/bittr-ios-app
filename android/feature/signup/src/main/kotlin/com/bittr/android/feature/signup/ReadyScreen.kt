package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrPartnerRow
import com.bittr.android.core.designsystem.BittrPartnerRowWidth
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

/**
 * Android counterpart of iOS `Signup7ViewController` — the wallet exists. Artboard 11.
 *
 * Next continues into the bittr signup (the Buy signup pages); Skip goes straight to the
 * wallet. The "What is bittr?" article card sits under the card when [onOpenArticle] is given.
 *
 * Laid out as the storyboard's scene is: `centerCard` 15 from the screen edges and the article
 * card 30 under it, centred together 40 above the middle. In the card, 30 from its top, the 50 pt
 * `checkView`; 20 below, "Your wallet is ready!" in Gilroy Bold 16; 20 below, the line under it in
 * Gilroy Regular 16, both 25 from the card's sides; 40 below, the partner row, and 10 below that
 * Next, both 200 by 40; Skip under Next, and 20 of card under Skip's row.
 */
@Composable
fun ReadyScreen(
    onContinue: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenArticle: ((String) -> Unit)? = null,
) {
    BittrCanvas(modifier = modifier, background = BittrTheme.colors.primaryHigh) {
        Column(
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(start = 15.dp, end = 15.dp, bottom = 80.dp),
        ) {
            // Skip's 25 pt row sits 20 above the card's bottom on iOS; its 48 dp touch target
            // spends 11.5 of that.
            BittrCard(contentPadding = PaddingValues(start = 25.dp, end = 25.dp, top = 30.dp, bottom = 8.dp)) {
                // `checkView`: 50 pt, the `checkmark` 20 by 16 in it.
                BittrCheckBadge(size = 50.dp, checkSize = 26.dp, strokeWidth = 1.8f)
                CanvasSpacer(20.dp)
                Text(
                    text = SignupStrings.WALLET_IS_READY,
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Signup.Create.Ready.topLabelOne),
                )
                CanvasSpacer(20.dp)
                Text(
                    text = SignupStrings.FIRST_BITCOIN,
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 20.sp),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
                CanvasSpacer(40.dp)
                BittrPartnerRow()
                CanvasSpacer(10.dp)

                // `continueView`: as wide as the partner row, 40 tall, 8 pt corners.
                BittrPrimaryButton(
                    text = SignupStrings.NEXT,
                    onClick = onContinue,
                    modifier = Modifier
                        .width(BittrPartnerRowWidth)
                        .testTag(TestID.Signup.Create.Ready.continueButton),
                )
                // iOS leaves 10 pt and a 25 pt row for Skip; its 48 dp touch target spends the 10.
                BittrTextButton(
                    text = SignupStrings.SKIP,
                    onClick = onSkip,
                    modifier = Modifier.testTag(TestID.Signup.Create.Ready.skipButton),
                )
            }
            if (onOpenArticle != null) {
                CanvasSpacer(30.dp)
                // Signup7's `pageArticle1Slug = "what-is-bittr"`.
                ArticleCard(slug = BittrArticles.WHAT_IS_BITTR, onOpen = onOpenArticle)
            }
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun ReadyScreenPreview() {
    BittrTheme {
        ReadyScreen(onContinue = {}, onSkip = {})
    }
}
