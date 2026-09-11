package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens

/**
 * Android counterpart of iOS `Signup1ViewController` — the create-or-restore entry
 * point a new user sees on a fresh install.
 *
 * **This is the scaffold version.** It carries the real test IDs and the real theme
 * and nothing else: no wallet creation, no article links, no copy from the iOS
 * screen. Its job is to give the Maestro harness something true to assert against
 * before there is feature work to break. BIT-7 ports the actual screen against the
 * screenshots in `shared/docs/screenshots/` and the strings in `shared/strings/`;
 * the test IDs below are the part that survives that rewrite unchanged.
 */
@Composable
fun SignupStartScreen(
    onCreateWallet: () -> Unit = {},
    onRestoreWallet: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(BittrTokens.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(
            BittrTokens.Spacing.md,
            Alignment.CenterVertically,
        ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "bittr",
            style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.testTag(TestID.Signup.Create.Start.headerLabel),
        )

        Button(
            onClick = onCreateWallet,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Start.createWalletButton),
        ) {
            Text("Create wallet")
        }

        OutlinedButton(
            onClick = onRestoreWallet,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Create.Start.restoreButton),
        ) {
            Text("Restore wallet")
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
