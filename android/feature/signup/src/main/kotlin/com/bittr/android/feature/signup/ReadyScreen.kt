package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens

/**
 * Android counterpart of iOS `Signup7ViewController` — the wallet exists.
 *
 * iOS offers to register an IBAN here or skip into the wallet. Neither is ported:
 * the bittr-account arc is out of BIT-93's scope, so both buttons land on the same
 * home placeholder and keep their ids for when it is not.
 *
 * The no-funds notice is not decoration. This build holds a real seed and has no
 * node behind it, so it must not look like somewhere to send money until BIT-6 lands
 * and the key handling has been reviewed.
 */
@Composable
fun ReadyScreen(
    onContinue: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(BittrTokens.Spacing.gutter),
        verticalArrangement = Arrangement.spacedBy(
            BittrTokens.Spacing.md,
            Alignment.CenterVertically,
        ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = SignupStrings.WALLET_IS_READY,
            style = MaterialTheme.typography.displaySmall,
            textAlign = TextAlign.Center,
            modifier = Modifier.testTag(TestID.Signup.Create.Ready.topLabelOne),
        )

        Surface(
            color = MaterialTheme.colorScheme.surfaceContainer,
            contentColor = MaterialTheme.colorScheme.onSurface,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = SignupStrings.NO_FUNDS_YET,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(BittrTokens.Spacing.md),
            )
        }

        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Ready.continueButton),
        ) {
            Text(SignupStrings.CONTINUE)
        }

        TextButton(
            onClick = onSkip,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Ready.skipButton),
        ) {
            Text(SignupStrings.SKIP)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ReadyScreenPreview() {
    BittrTheme {
        ReadyScreen(onContinue = {}, onSkip = {})
    }
}
