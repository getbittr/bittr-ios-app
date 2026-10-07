package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPiggy
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

/**
 * Android counterpart of iOS `Signup1ViewController` — the create-or-restore entry
 * point a new user sees on a fresh install. Artboard 01 of the Android design.
 *
 * **The piggy and "welcome" are white, as on iOS, and yellow in dark mode.** White on
 * the card over the brand yellow is 1.43 : 1, the pairing DEV-47 removed from every
 * other title; this screen has it back because Tom asked for Signup1 to match iOS
 * (2026-09-28, decision 47). It takes `BittrColors.welcomeHeader`, which exists for
 * this call site only. The piggy is iOS's own asset at its 18 pt, 10 pt from the word.
 *
 * The "What is bittr?" article card sits under the card (`pageArticle1Slug`), carrying
 * `signup.create.start.articleButton`; it is shown when [onOpenArticle] is given.
 *
 * **Create wallet no longer generates anything.** It advances to [ConfirmScreen],
 * which is where the seed is made — so the spinner that used to live in this button
 * lives there now, next to the action that actually takes time.
 */
@Composable
fun SignupStartScreen(
    onCreateWallet: () -> Unit = {},
    onRestoreWallet: () -> Unit = {},
    modifier: Modifier = Modifier,
    onOpenArticle: ((String) -> Unit)? = null,
) {
    BittrCanvas(modifier = modifier) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                // iOS's `centerCard` sits 15 pt from the screen edges; the mock's gutter is 18.
                .padding(horizontal = 15.dp),
        ) {
            // iOS: `centerCard` — BittrCard's own look; only the gutter is this screen's.
            BittrCard(
                // Header 20 in from the top and leading edge; the last row 25 above the bottom,
                // less the half of Restore's 48 dp touch target that iOS's 25 pt row does not have.
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 12.dp),
            ) {
                val header = BittrTheme.colors.welcomeHeader
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    BittrPiggy(size = 18.dp, tint = header)
                    Text(
                        text = SignupStrings.WELCOME,
                        // Gilroy Bold 18, the same height as the piggy beside it.
                        style = MaterialTheme.typography.titleLarge.copy(fontSize = 18.sp, lineHeight = 18.sp),
                        color = header,
                        // iOS centres the word 1 pt below the piggy's centre (`centerY` constant 1).
                        modifier = Modifier
                            .offset(y = 1.dp)
                            .testTag(TestID.Signup.Create.Start.headerLabel),
                    )
                }

                CanvasSpacer(35.dp)
                // 25 pt from the card's edges on iOS: the card's 20 plus 5.
                BittrBody(SignupStrings.CREATE_YOUR_OWN_WALLET, modifier = Modifier.padding(horizontal = 5.dp))
                CanvasSpacer(30.dp)

                BittrPrimaryButton(
                    text = SignupStrings.CREATE_WALLET,
                    onClick = onCreateWallet,
                    modifier = Modifier.testTag(TestID.Signup.Create.Start.createWalletButton),
                )
                // iOS leaves 10 pt and then a 25 pt row for Restore. Its 48 dp touch target
                // spends that 10 and more, so there is no spacer here.
                BittrTextButton(
                    text = SignupStrings.RESTORE_WALLET,
                    onClick = onRestoreWallet,
                    modifier = Modifier.testTag(TestID.Signup.Create.Start.restoreButton),
                )
            }
            if (onOpenArticle != null) {
                CanvasSpacer(30.dp)
                // `pageArticle1Slug = "what-is-bittr"`.
                ArticleCard(
                    slug = BittrArticles.WHAT_IS_BITTR,
                    onOpen = onOpenArticle,
                    testTag = TestID.Signup.Create.Start.articleButton,
                )
            }
        }
    }
}

/** The mock's screen gutter — 18 dp, outside the card. */
internal val CanvasGutter = 18.dp

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun SignupStartScreenPreview() {
    BittrTheme {
        SignupStartScreen()
    }
}
