package com.bittr.android.navigation

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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrLogo
import com.bittr.android.core.designsystem.BittrPiggy
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

/**
 * Where the create-wallet arc lands. **A placeholder, and it says so.**
 *
 * It now wears the design's chrome — the canvas, the logo, the wallet card — and it
 * deliberately stops there. The mock's Home (artboard 18) is a balance, a profit
 * pill, Send / Receive / Buy and a bottom nav bar. Every one of those needs the node
 * BIT-6 owns, and drawing them against a wallet with no engine is the exact thing
 * constraint 1 on BIT-93 forbids: a zero balance and a Receive button on a build that
 * cannot receive invites a deposit the app will lose.
 *
 * So the shape is the design's and the content is honest. When BIT-6 lands, this file
 * is where artboard 18 gets built out — the card, the action row and the nav bar are
 * all already specified there.
 *
 * It carries `home.headerLabel` so a flow can assert the arc completed.
 */
@Composable
fun HomePlaceholderScreen(modifier: Modifier = Modifier) {
    BittrCanvas(modifier = modifier, appBar = false) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 16.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                BittrLogo(height = 19.dp)
            }
            CanvasSpacer(BittrTokens.Spacing.md)

            BittrCard(horizontalAlignment = Alignment.Start) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    BittrPiggy()
                    Text(
                        text = "your wallet",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.testTag(TestID.Home.headerLabel),
                    )
                }
                CanvasSpacer(BittrTokens.Spacing.lg)
                BittrBody(
                    text = "Your recovery phrase is saved and your PIN is set.",
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth(),
                )
                CanvasSpacer(BittrTokens.Spacing.sm)
                BittrBody(
                    text = "Balances, buying and receiving arrive with the wallet engine. " +
                        "This build holds no funds.",
                    textAlign = TextAlign.Start,
                    muted = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun HomePlaceholderScreenPreview() {
    BittrTheme {
        HomePlaceholderScreen()
    }
}
