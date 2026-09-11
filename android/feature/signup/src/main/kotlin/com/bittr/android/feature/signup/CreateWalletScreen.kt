package com.bittr.android.feature.signup

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID

/**
 * The whole create-wallet arc, as one destination.
 *
 * **Why one destination rather than six routes.** Compose Navigation puts arguments
 * in the saved-state `Bundle`, which the system writes to disk when it kills the
 * process — so routing between a screen that shows twelve words and a screen that
 * checks three of them would mean the seed leaving the Keystore and landing in
 * `onSaveInstanceState`. Keeping the arc in one destination, with
 * [CreateWalletViewModel] holding the phrase in memory, closes that. The step is
 * still named per iOS view controller in [CreateWalletStep], so the port stays
 * greppable against the screen inventory.
 *
 * Back inside the arc is handled per step rather than by the nav stack, matching
 * `Signup4`'s and `Signup6`'s own back buttons.
 */
@Composable
fun CreateWalletScreen(
    onFinished: () -> Unit,
    onRestoreWallet: () -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: CreateWalletViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    state.alert?.let { alert ->
        AlertDialog(
            onDismissRequest = viewModel::dismissAlert,
            title = { Text(alert.title) },
            text = { Text(alert.message) },
            confirmButton = {
                TextButton(
                    onClick = viewModel::dismissAlert,
                    modifier = Modifier.testTag(TestID.Alert.buttonAt(0)),
                ) {
                    Text(SignupStrings.OKAY)
                }
            },
        )
    }

    when (state.step) {
        CreateWalletStep.Start -> SignupStartScreen(
            onCreateWallet = viewModel::createWallet,
            onRestoreWallet = onRestoreWallet,
            busy = state.busy,
            modifier = modifier,
        )

        CreateWalletStep.Phrase -> {
            val mnemonic = state.mnemonic
            if (mnemonic == null) {
                // Only reachable if the phrase was dropped out from under the step,
                // which would mean showing an empty backup screen. Go back instead.
                LaunchedEffect(Unit) { viewModel.finish() }
            } else {
                MnemonicScreen(
                    mnemonic = mnemonic,
                    onNext = viewModel::confirmPhraseSeen,
                    modifier = modifier,
                )
            }
        }

        CreateWalletStep.Verify -> {
            val challenge = state.challenge
            if (challenge == null) {
                LaunchedEffect(Unit) { viewModel.backToPhrase() }
            } else {
                VerifyScreen(
                    challenge = challenge,
                    onSubmit = viewModel::submitVerification,
                    onBack = viewModel::backToPhrase,
                    modifier = modifier,
                )
            }
        }

        CreateWalletStep.PinSet -> PinScreen(
            title = SignupStrings.SET_A_PIN,
            titleTestTag = TestID.Signup.Create.PinSet.topLabel,
            onSubmit = viewModel::submitFirstPin,
            modifier = modifier,
        )

        CreateWalletStep.PinConfirm -> PinScreen(
            title = SignupStrings.CONFIRM_YOUR_PIN,
            titleTestTag = TestID.Signup.Create.PinConfirm.topLabel,
            onSubmit = viewModel::submitConfirmationPin,
            onBack = viewModel::backToPinSet,
            modifier = modifier,
        )

        CreateWalletStep.Ready -> ReadyScreen(
            onContinue = {
                viewModel.finish()
                onFinished()
            },
            onSkip = {
                viewModel.finish()
                onFinished()
            },
            modifier = modifier,
        )
    }
}
