package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrPartnerRow
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

/**
 * Android counterpart of iOS `Signup7ViewController` — the wallet exists. Artboard 11.
 *
 * Next continues into the bittr signup (the Buy signup pages); Skip goes straight to the
 * wallet. The "What is bittr?" article card sits under the card when [onOpenArticle] is given.
 */
@Composable
fun ReadyScreen(
    onContinue: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenArticle: ((String) -> Unit)? = null,
) {
    BittrCanvas(modifier = modifier) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = CanvasGutter),
        ) {
            BittrCard {
                BittrCheckBadge()
                CanvasSpacer(BittrTokens.Spacing.lg)
                Text(
                    text = SignupStrings.WALLET_IS_READY,
                    style = MaterialTheme.typography.headlineSmall,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Signup.Create.Ready.topLabelOne),
                )
                CanvasSpacer(14.dp)
                BittrBody(SignupStrings.FIRST_BITCOIN)
                CanvasSpacer(BittrTokens.Spacing.xl)
                BittrPartnerRow()
                CanvasSpacer(16.dp)

                BittrPrimaryButton(
                    text = SignupStrings.NEXT,
                    onClick = onContinue,
                    modifier = Modifier.testTag(TestID.Signup.Create.Ready.continueButton),
                )
                BittrTextButton(
                    text = SignupStrings.SKIP,
                    onClick = onSkip,
                    modifier = Modifier.testTag(TestID.Signup.Create.Ready.skipButton),
                )
            }
            if (onOpenArticle != null) {
                CanvasSpacer(BittrTokens.Spacing.lg)
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
