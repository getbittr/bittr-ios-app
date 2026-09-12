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
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

/**
 * Android counterpart of iOS `Signup7ViewController` — the wallet exists. Artboard 11.
 *
 * The mock follows this with the partner sign-up arc (artboards 12–17: IBAN, OTP,
 * transfer details). That is the bittr-account flow and it is out of BIT-93's scope,
 * so both buttons land on the same home placeholder and keep their ids for when it is
 * not. The mock's partner row is not drawn: a row that looks like a connected account
 * on a build with no account behind it is the same lie the no-funds notice exists to
 * avoid.
 *
 * The no-funds notice is not decoration. This build holds a real seed and has no node
 * behind it, so it must not look like somewhere to send money until BIT-6 lands and
 * the key handling has been reviewed.
 */
@Composable
fun ReadyScreen(
    onContinue: () -> Unit,
    onSkip: () -> Unit,
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
                BittrBody(SignupStrings.NO_FUNDS_YET)
                CanvasSpacer(BittrTokens.Spacing.xl)

                BittrPrimaryButton(
                    text = SignupStrings.CONTINUE,
                    onClick = onContinue,
                    modifier = Modifier.testTag(TestID.Signup.Create.Ready.continueButton),
                )
                BittrTextButton(
                    text = SignupStrings.SKIP,
                    onClick = onSkip,
                    modifier = Modifier.testTag(TestID.Signup.Create.Ready.skipButton),
                )
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
