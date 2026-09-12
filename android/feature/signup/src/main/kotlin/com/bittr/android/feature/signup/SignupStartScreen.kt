package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPiggy
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

/**
 * Android counterpart of iOS `Signup1ViewController` — the create-or-restore entry
 * point a new user sees on a fresh install. Artboard 01 of the Android design.
 *
 * **"welcome" is ink, where the mock draws it white.** White on the card over the
 * brand yellow is 1.43 : 1. That exact pairing is what DEV-47 removed from the token
 * set — iOS's `whiteoryellow`, 16 call sites, every screen title — with founder
 * sign-off on BIT-15. Reintroducing it on the first screen of the app would undo the
 * single largest accessibility fix the port has made.
 *
 * What is still not ported: the "What is bittr?" article chip, which needs the article
 * fetch BIT-7 owns. Restore is a button with nothing behind it for the same reason —
 * BIT-93 is the create arc.
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
) {
    BittrCanvas(modifier = modifier) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = CanvasGutter),
        ) {
            BittrCard {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    BittrPiggy()
                    Text(
                        text = SignupStrings.WELCOME,
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.testTag(TestID.Signup.Create.Start.headerLabel),
                    )
                }

                CanvasSpacer(BittrTokens.Spacing.xl)
                BittrBody(SignupStrings.CREATE_YOUR_OWN_WALLET)
                CanvasSpacer(BittrTokens.Spacing.xl)

                BittrPrimaryButton(
                    text = SignupStrings.CREATE_WALLET,
                    onClick = onCreateWallet,
                    modifier = Modifier.testTag(TestID.Signup.Create.Start.createWalletButton),
                )
                BittrTextButton(
                    text = SignupStrings.RESTORE_WALLET,
                    onClick = onRestoreWallet,
                    modifier = Modifier.testTag(TestID.Signup.Create.Start.restoreButton),
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
