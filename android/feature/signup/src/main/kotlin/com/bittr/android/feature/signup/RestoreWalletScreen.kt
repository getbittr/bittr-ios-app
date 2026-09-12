package com.bittr.android.feature.signup

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog

/**
 * The whole restore arc, as one destination — the twin of [CreateWalletScreen].
 *
 * One destination for the same reason: see that file for why twelve words must not
 * travel as navigation arguments.
 *
 * The step is named per iOS view controller in [RestoreWalletStep], so the port stays
 * greppable against `shared/docs/screens.md`.
 *
 * @param onFinished the PIN is set and the seed is stored — go to Home. This is
 *   `Restore3.nextButtonTapped` calling `hideSignup`; there is no Ready screen on
 *   this path.
 * @param onCancelled the user backed out of the arc without restoring anything.
 */
@Composable
fun RestoreWalletScreen(
    onFinished: () -> Unit,
    onCancelled: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: RestoreWalletViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    state.alert?.let { alert ->
        BittrAlertDialog(
            title = alert.title,
            message = alert.message,
            confirmLabel = SignupStrings.OKAY,
            onConfirm = viewModel::dismissAlert,
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }

    when (state.step) {
        RestoreWalletStep.Phrase -> RestoreScreen(
            onSubmit = viewModel::submitPhrase,
            onCancel = {
                viewModel.finish()
                onCancelled()
            },
            busy = state.busy,
            modifier = modifier,
        )

        RestoreWalletStep.PinSet -> PinScreen(
            title = SignupStrings.SET_A_PIN,
            titleTestTag = TestID.Signup.Restore.PinSet.topLabel,
            onSubmit = viewModel::submitFirstPin,
            modifier = modifier,
        )

        RestoreWalletStep.PinConfirm -> PinScreen(
            title = SignupStrings.CONFIRM_YOUR_PIN,
            titleTestTag = TestID.Signup.Restore.PinConfirm.topLabel,
            onSubmit = { pin -> viewModel.submitConfirmationPin(pin, onFinished) },
            onBack = viewModel::backToPinSet,
            modifier = modifier,
        )
    }
}
