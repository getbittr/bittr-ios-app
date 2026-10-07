package com.bittr.android.feature.signup

import androidx.compose.animation.AnimatedContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.pageSlide

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
    // `Signup7ViewController.nextButtonTapped` — Continue on "Your wallet is ready" goes on
    // into the bittr signup (`moveToPage(10)`); Skip is [onFinished], into the wallet.
    onContinueToSignup: () -> Unit = onFinished,
    // The pages' article cards (`launchArticle(articleTag:)`). The article opens as its own
    // destination on top of this one, so the arc's view model — and the phrase — survive it.
    onOpenArticle: ((String) -> Unit)? = null,
) {
    val state by viewModel.uiState.collectAsState()

    state.alert?.let { alert ->
        BittrAlertDialog(
            title = alert.title,
            message = alert.message,
            confirmLabel = SignupStrings.OKAY,
            onConfirm = viewModel::dismissAlert,
            confirmTestTag = TestID.Alert.buttonAt(0),
            // The alert's own id goes on the card, as iOS's `showAlert(id:)` does —
            // BittrAlertDialog publishes it through exposeTestTags.
            modifier = if (alert.tag != null) Modifier.testTag(alert.tag) else Modifier,
        )
    }

    // iOS slides between these pages (`moveToPage`); see pageSlide.
    AnimatedContent(
        targetState = state.step,
        transitionSpec = { pageSlide(initialState.page, targetState.page) },
        label = "createWalletPages",
    ) { step ->
        // The page leaving still recomposes with the new state while it slides out, so the fallbacks
        // below — a step whose data has gone — act only on the page arriving, and a departing page
        // with nothing left to show slides out as the bare canvas.
        val arriving = step == state.step
        when (step) {
            CreateWalletStep.Start -> SignupStartScreen(
                onCreateWallet = viewModel::startCreate,
                onRestoreWallet = onRestoreWallet,
                modifier = modifier,
                onOpenArticle = onOpenArticle,
            )

            CreateWalletStep.Confirm -> ConfirmScreen(
                onUnderstood = viewModel::createWallet,
                onBack = viewModel::backToStart,
                busy = state.busy,
                modifier = modifier,
                onOpenArticle = onOpenArticle,
            )

            CreateWalletStep.Phrase -> {
                val mnemonic = state.mnemonic
                if (mnemonic == null) {
                    // Only reachable if the phrase was dropped out from under the step,
                    // which would mean showing an empty backup screen. Go back instead.
                    if (arriving) LaunchedEffect(Unit) { viewModel.finish() } else BittrCanvas(modifier) {}
                } else {
                    MnemonicScreen(
                        mnemonic = mnemonic,
                        onNext = viewModel::confirmPhraseSeen,
                        modifier = modifier,
                        onOpenArticle = onOpenArticle,
                    )
                }
            }

            CreateWalletStep.Verify -> {
                // Back drops the challenge in the same update that starts the slide to the phrase,
                // so the page keeps the one it was showing and slides out as it was, words typed
                // and all, instead of as the bare canvas.
                val challenge = rememberLastNonNull(state.challenge)
                if (arriving && state.challenge == null) {
                    LaunchedEffect(Unit) { viewModel.backToPhrase() }
                } else if (challenge == null) {
                    BittrCanvas(modifier) {}
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
                confirmLabel = SignupStrings.NEXT,
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

            // Leaving from here does not reset the arc with `finish()`: that puts the step back to
            // Start, and the page, still drawn while it slides away to Home or Transfer1, would
            // race six pages sideways as it went. Both ways out pop this destination, which clears
            // the view model; the PIN and the phrase were dropped when the PIN was confirmed.
            CreateWalletStep.Ready -> ReadyScreen(
                onContinue = onContinueToSignup,
                onSkip = onFinished,
                modifier = modifier,
                onOpenArticle = onOpenArticle,
            )
        }
    }
}

/**
 * [value], or the last non-null value it had while this call stayed composed — for a page that goes
 * on being drawn while it slides out after its data has been cleared. A plain holder, not state:
 * nothing needs to recompose when it changes, as [value] changing already has.
 */
@Composable
private fun <T : Any> rememberLastNonNull(value: T?): T? {
    val last = remember { LastValue<T>() }
    if (value != null) last.value = value
    return last.value
}

private class LastValue<T : Any> {
    var value: T? = null
}
