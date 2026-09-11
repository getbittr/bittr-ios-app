package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens

/**
 * Android counterpart of iOS `Signup1ViewController` — the create-or-restore entry
 * point a new user sees on a fresh install.
 *
 * The card, the copy and the two actions are the iOS screen's. What is not ported:
 * the "what is bittr" article tile, which needs the article fetch BIT-7 owns, and
 * the piggy icon, which needs assets that are not in `shared/` yet. Restore is a
 * button with nothing behind it for the same reason — BIT-93 is the create arc.
 *
 * The test IDs are the part designed to survive this rewrite; they have not changed
 * since the scaffold.
 *
 * @param busy true while the seed is being generated and stored. iOS shows a spinner
 *   in the button for the same window.
 */
@Composable
fun SignupStartScreen(
    onCreateWallet: () -> Unit = {},
    onRestoreWallet: () -> Unit = {},
    busy: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(BittrTokens.Spacing.gutter),
        verticalArrangement = Arrangement.spacedBy(
            BittrTokens.Spacing.lg,
            Alignment.CenterVertically,
        ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            color = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            shape = MaterialTheme.shapes.medium,
            tonalElevation = BittrTokens.Elevation.level3,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(BittrTokens.Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = SignupStrings.WELCOME,
                    style = MaterialTheme.typography.displaySmall,
                    modifier = Modifier.testTag(TestID.Signup.Create.Start.headerLabel),
                )
                Text(
                    text = SignupStrings.CREATE_YOUR_OWN_WALLET,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                )
            }
        }

        Button(
            onClick = onCreateWallet,
            enabled = !busy,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Start.createWalletButton),
        ) {
            if (busy) {
                CircularProgressIndicator(
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                Text(SignupStrings.CREATE_WALLET)
            }
        }

        TextButton(
            onClick = onRestoreWallet,
            enabled = !busy,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Start.restoreButton),
        ) {
            Text(SignupStrings.RESTORE_WALLET)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun SignupStartScreenPreview() {
    BittrTheme {
        SignupStartScreen()
    }
}
