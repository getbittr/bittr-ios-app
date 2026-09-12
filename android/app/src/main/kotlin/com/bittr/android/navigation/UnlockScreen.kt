package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.feature.signup.PinScreen
import com.bittr.android.feature.signup.RestoreScreen
import com.bittr.android.feature.signup.SignupStrings

/**
 * The PIN gate on an existing wallet — iOS `PinViewController` in its unlock role,
 * plus the forgot-PIN reset arc that hangs off it.
 *
 * Four Maestro flows run through this one composable: `helpers/unlock.yaml`,
 * `features/wrong_pin.yaml`, `features/pin_warning.yaml` and
 * `features/forgot_pin.yaml`. They are one composable rather than four destinations
 * because on iOS they are one screen and one piece of `CoreViewController` state
 * (`resettingPin`), and because the reset must not survive a back-stack entry: a
 * half-finished PIN reset that the user can press Back into is a screen asking for a
 * recovery phrase with nothing behind it.
 *
 * **What is still not here**, and is BIT-6's rather than deferred by choice: the
 * cooperative Lightning channel close that has to precede the wipe when the wallet has
 * an open channel (`wrong_pin_with_channel.yaml`), and the `removeWalletButton` escape
 * hatch on the phrase screen for a user who has lost their phrase as well
 * (`remove_wallet.yaml`, `forgot_pin_remove_wallet.yaml`). Both need a node to close
 * channels against. The no-channel branches below are complete.
 *
 * @param onUnlocked the PIN was right.
 * @param onWalletWiped ten wrong entries; there is no wallet on this device any more,
 *   so the caller must leave for signup and must not allow Back into this screen.
 */
@Composable
fun UnlockScreen(
    onUnlocked: () -> Unit,
    onWalletWiped: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: UnlockViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    // CoreViewController.checkWalletRemoval — a wipe already earned is finished here
    // even if nobody types anything.
    LaunchedEffect(Unit) { viewModel.checkLockout() }

    state.alert?.let { alert ->
        BittrAlertDialog(
            title = alert.title,
            message = alert.message,
            confirmLabel = alert.confirmLabel,
            onConfirm = {
                // The confirm button is the one that *does* something on the two
                // alerts that have a second button; on the rest it is just Okay.
                when (alert) {
                    is UnlockAlert.Warning, UnlockAlert.ConfirmReset -> viewModel.startPinReset()
                    else -> if (viewModel.dismissAlert()) onWalletWiped()
                }
            },
            confirmTestTag = TestID.Alert.buttonAt(if (alert.dismissLabel != null) 1 else 0),
            dismissLabel = alert.dismissLabel,
            onDismiss = { viewModel.dismissAlert() },
            dismissTestTag = TestID.Alert.buttonAt(0),
        )
    }

    when (state.step) {
        UnlockStep.Pin -> PinScreen(
            title = UnlockStrings.ENTER_YOUR_PIN,
            titleTestTag = TestID.Unlock.topLabel,
            onSubmit = { pin -> viewModel.submitPin(pin, onUnlocked) },
            // iOS's `restoreWalletButton` in the `.core` embedding. Same button, same
            // `pin.restoreButton` id as Back on the signup steps — see PinScreen.
            onBack = viewModel::forgotPin,
            backLabel = UnlockStrings.FORGOT_PIN,
            // `clearPinField()`, which iOS calls on every confirm that does not
            // unlock. This is the one embedding where the screen stays put after a
            // rejection, so it is the one that has to empty the cells.
            clearOnSubmit = true,
            modifier = modifier,
        )

        UnlockStep.ResetPhrase -> RestoreScreen(
            onSubmit = viewModel::submitResetPhrase,
            onCancel = viewModel::cancelPinReset,
            busy = state.busy,
            submitLabel = UnlockStrings.RESET_PIN,
            modifier = modifier,
        )

        // Restore2 / Restore3, and they carry the `signup.restore.pin*` ids because on
        // iOS they are literally those view controllers — `startPinReset` opens the
        // signup container at the restore page. The flows select by those ids on both
        // the restore arc and this one.
        UnlockStep.ResetPinSet -> PinScreen(
            title = SignupStrings.SET_A_PIN,
            titleTestTag = TestID.Signup.Restore.PinSet.topLabel,
            onSubmit = viewModel::submitFirstPin,
            modifier = modifier,
        )

        UnlockStep.ResetPinConfirm -> PinScreen(
            title = SignupStrings.CONFIRM_YOUR_PIN,
            titleTestTag = TestID.Signup.Restore.PinConfirm.topLabel,
            onSubmit = { pin -> viewModel.submitConfirmationPin(pin, onUnlocked) },
            onBack = viewModel::backToPinSet,
            modifier = modifier,
        )
    }
}
