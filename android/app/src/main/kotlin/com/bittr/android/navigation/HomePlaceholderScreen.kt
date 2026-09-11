package com.bittr.android.navigation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
 * Where the create-wallet arc lands. **A placeholder, and it says so.**
 *
 * The real Home screen is a balance, a sync state, buy/send/receive and the map —
 * all of which need the node BIT-6 owns. What would be dishonest is a Home that
 * *looks* finished: a zero balance and a receive button on a build with no wallet
 * engine behind it invites exactly the deposit BIT-93 must not accept.
 *
 * It carries `home.headerLabel` so a flow can assert the arc completed.
 */
@Composable
fun HomePlaceholderScreen(modifier: Modifier = Modifier) {
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
            text = "bittr",
            style = MaterialTheme.typography.displayMedium,
            modifier = Modifier.testTag(TestID.Home.headerLabel),
        )
        Text(
            text = "Your recovery phrase is saved and your PIN is set.",
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        Text(
            text = "Balances, buying and receiving arrive with the wallet engine. " +
                "This build holds no funds.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun HomePlaceholderScreenPreview() {
    BittrTheme {
        HomePlaceholderScreen()
    }
}
