package com.bittr.android.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon
import kotlinx.coroutines.delay

/**
 * The three rows of `CoreViewController`'s sync view, and whether each is done.
 *
 * iOS completes "Start lightning node" when the node has started and "Final calculations" after
 * `loadWalletData()`. Android's overview only publishes once both have happened, so the two
 * complete together on the first wallet reading.
 */
internal data class SyncProgress(val conversion: Boolean, val node: Boolean, val final: Boolean)

internal fun syncProgress(state: HomeUiState) = SyncProgress(
    conversion = state.conversionFetched,
    node = state.walletHasSynced,
    final = state.walletHasSynced,
)

/**
 * `sync.statusView` — slides up over a light dim when the header's sync button is tapped before
 * the wallet has synced (`syncingStatusTapped`). Each row shows a spinner until its step is done,
 * then a check; the sheet closes itself half a second after the last one, or on `sync.closeButton`.
 */
@Composable
internal fun BoxScope.SyncStatusSheet(progress: SyncProgress, onClose: () -> Unit) {
    LaunchedEffect(progress.final) {
        if (progress.final) {
            delay(AUTO_DISMISS_MS)
            onClose()
        }
    }
    Box(
        contentAlignment = Alignment.BottomCenter,
        modifier = Modifier
            .matchParentSize()
            .background(Color.Black.copy(alpha = 0.2f))
            .pointerInput(Unit) { detectTapGestures { onClose() } },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            modifier = Modifier
                .navigationBarsPadding()
                .padding(BittrTokens.Spacing.md)
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(28.dp))
                // Taps on the sheet stay on the sheet.
                .pointerInput(Unit) { detectTapGestures { } }
                .padding(BittrTokens.Spacing.lg)
                .testTag(TestID.Sync.statusView),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = HomeStrings.SYNCING_WALLET,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(BittrTokens.Size.minTouchTarget)
                        .clickable(onClick = onClose)
                        .testTag(TestID.Sync.closeButton),
                ) {
                    Image(
                        imageVector = rememberStrokeIcon(CLOSE_PATH, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
                        contentDescription = HomeStrings.CLOSE,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
            SyncRow(HomeStrings.FETCH_CONVERSION_RATES, progress.conversion)
            SyncRow(HomeStrings.START_LIGHTNING_NODE, progress.node)
            SyncRow(HomeStrings.FINAL_CALCULATIONS, progress.final)
        }
    }
}

@Composable
private fun SyncRow(label: String, done: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md)) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(20.dp)) {
            if (done) {
                Image(
                    imageVector = rememberStrokeIcon(CHECK_PATH, BittrTheme.colors.emphasis, strokeWidth = 2.5f),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            } else {
                BittrSpinner(strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            }
        }
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}

private const val AUTO_DISMISS_MS = 500L
private const val CHECK_PATH = "M5 12l5 5 9-10"
private const val CLOSE_PATH = "M6 6l12 12M18 6L6 18"
