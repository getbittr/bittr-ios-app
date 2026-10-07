package com.bittr.android.feature.home

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The three rows of `CoreViewController`'s sync view, and whether each is done.
 *
 * iOS completes "Start lightning node" when the node has started (`completeSync(.ldk)`) and runs
 * the wallets' sync and `loadWalletData()` under "Final calculations", which completes with the
 * first wallet reading.
 */
internal data class SyncProgress(val conversion: Boolean, val node: Boolean, val final: Boolean)

internal fun syncProgress(state: HomeUiState) = SyncProgress(
    conversion = state.conversionFetched,
    node = state.nodeStarted || state.walletHasSynced,
    final = state.walletHasSynced,
)

/**
 * `sync.statusView`, as `CoreViewController` draws it over everything — the menu bar included, which
 * is why Home puts it [AboveChrome]. Opened when the header's sync button is tapped before the wallet
 * has synced (`syncingStatusTapped`).
 *
 * `showSyncView()`: the card slides up from below the screen over 0.3 s, overshooting by 15 and
 * settling in 0.1 s, as the dim behind it rises to black at 20 %; `hideSyncView()` slides it back down.
 * A tap anywhere closes it — iOS's close button covers the whole view — and it closes itself half a
 * second after the last step, as `completeSync(.final)` does.
 *
 * The card: white with 13 corners, 10 from the screen's sides and resting on the safe area's bottom.
 * Its three steps 24 in, 30 from its top and bottom and 11 apart — a spinner, `iconcheck` once done,
 * and the Gilroy-Bold 14 label 10 after it — and `iconcloseblack` 22 from the top and 18 from the end.
 * White and black in both schemes, as the storyboard has it.
 */
@Composable
internal fun SyncStatusSheet(progress: SyncProgress, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val shown = remember { Animatable(0f) }
    val lift = remember { Animatable(0f) }
    var closing by remember { mutableStateOf(false) }
    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

    LaunchedEffect(Unit) {
        launch { shown.animateTo(1f, tween(SLIDE_MS, easing = FastOutSlowInEasing)) }
        lift.animateTo(OVERSHOOT_DP, tween(SLIDE_MS, easing = FastOutSlowInEasing))
        lift.animateTo(0f, tween(SETTLE_MS, easing = FastOutSlowInEasing))
    }
    fun close() {
        if (closing) return
        closing = true
        scope.launch {
            lift.snapTo(0f)
            shown.animateTo(0f, tween(SLIDE_MS, easing = FastOutSlowInEasing))
            onClose()
        }
    }
    LaunchedEffect(progress.final) {
        if (progress.final) {
            delay(AUTO_DISMISS_MS)
            close()
        }
    }

    Box(
        contentAlignment = Alignment.BottomCenter,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.2f * shown.value))
            .pointerInput(Unit) { detectTapGestures { close() } },
    ) {
        Box(
            modifier = Modifier
                .navigationBarsPadding()
                .padding(horizontal = 10.dp)
                .fillMaxWidth()
                .graphicsLayer {
                    translationY = (1f - shown.value) * (size.height + bottomInset.toPx()) - lift.value.dp.toPx()
                }
                .background(Color.White, RoundedCornerShape(13.dp))
                .testTag(TestID.Sync.statusView),
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(11.dp),
                modifier = Modifier.padding(start = 24.dp, top = 30.dp, bottom = 30.dp),
            ) {
                SyncRow(HomeStrings.FETCH_CONVERSION_RATES, progress.conversion)
                SyncRow(HomeStrings.START_LIGHTNING_NODE, progress.node)
                SyncRow(HomeStrings.FINAL_CALCULATIONS, progress.final)
            }
            // `iconcloseblack`, 12 pt, 22 from the top and 18 from the end, in a 40 dp target.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 8.dp, end = 4.dp)
                    .size(40.dp)
                    .clickable(role = Role.Button, onClickLabel = HomeStrings.CLOSE) { close() }
                    .testTag(TestID.Sync.closeButton),
            ) {
                Image(
                    painter = painterResource(R.drawable.sync_close),
                    contentDescription = HomeStrings.CLOSE,
                    modifier = Modifier.size(12.dp),
                )
            }
        }
    }
}

/** One step: 14 tall, the 20 pt spinner — or the 14 pt check, 1 above its centre — and the label 10 after it. */
@Composable
private fun SyncRow(label: String, done: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(14.dp)) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.requiredSize(20.dp)) {
            if (done) {
                Image(
                    painter = painterResource(R.drawable.sync_check),
                    contentDescription = null,
                    modifier = Modifier
                        .offset(y = (-1).dp)
                        .size(14.dp),
                )
            } else {
                // The activity indicator's grey, on a card that is white in both schemes.
                BittrSpinner(strokeWidth = 2.dp, color = BittrTheme.colors.phrasePlaceholder, modifier = Modifier.size(16.dp))
            }
        }
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp),
            color = Color.Black,
            modifier = Modifier.padding(start = 10.dp),
        )
    }
}

private const val AUTO_DISMISS_MS = 500L
private const val SLIDE_MS = 300
private const val SETTLE_MS = 100
private const val OVERSHOOT_DP = 15f
