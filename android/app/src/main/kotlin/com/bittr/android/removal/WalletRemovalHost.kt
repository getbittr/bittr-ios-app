package com.bittr.android.removal

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import com.bittr.android.core.designsystem.BittrInlineAlert
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrTheme

/**
 * Draws a wallet removal over [content]: iOS's `fullViewCover` with its spinner while the removal
 * works, and the removal's alerts.
 *
 * Over the whole app rather than inside a screen, because the screen a removal starts from is
 * gone before it finishes — erasing the wallet swaps the navigation graph to signup.
 *
 * @param onWalletRemoved the wallet is off the device; leave for signup.
 */
@Composable
fun WalletRemovalHost(
    coordinator: WalletRemovalCoordinator,
    onWalletRemoved: () -> Unit,
    content: @Composable () -> Unit,
) {
    val state by coordinator.uiState.collectAsState()
    val handOff by coordinator.handOff.collectAsState()

    LaunchedEffect(handOff) {
        if (handOff) {
            coordinator.consumeHandOff()
            onWalletRemoved()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        content()

        if (state.busy) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .background(BittrTheme.colors.canvas.copy(alpha = COVER_ALPHA))
                    // The cover swallows taps, as iOS's does.
                    .pointerInput(Unit) { detectTapGestures { } },
            ) {
                BittrSpinner()
            }
        }

        // In the activity's own window, not a dialog: this alert can be up at launch (a removal
        // resumed from the last run), and Maestro reads only the focused window — a dialog then
        // hides `core.launchComplete` and the next flow cannot even see that the app started.
        // iOS's AlertManager adds its alerts as subviews for the same effect.
        state.alert?.let { alert ->
            BittrInlineAlert(
                title = alert.title,
                message = alert.message,
                buttons = alert.buttons.map { button ->
                    BittrAlertButton(
                        label = button.label,
                        // Cancelling a resumed removal is the way out too, drawn as the quiet
                        // text action rather than a second filled pill (review S20).
                        dismissesAlert = button.step == null || button.step == RemovalStep.CancelResume,
                        onClick = { coordinator.press(button) },
                    )
                },
            )
        }
    }
}

/** `fullViewCover.alpha = 0.8`. */
private const val COVER_ALPHA = 0.8f
