package com.bittr.android.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.feature.signup.PinScreen

/**
 * The PIN gate on an existing wallet — iOS `PinViewController` in its unlock role.
 *
 * This is the screen that makes the Definition of Done true: create a wallet, set a
 * PIN, force-quit, reopen, and land here rather than back at signup.
 *
 * **What is deliberately not here yet:** attempt counting, the warning after several
 * wrong PINs, the wipe after ten, and forgot-PIN-via-recovery-phrase. Those are real
 * iOS behaviours (`pinwarning2`, `pinlock`, `forgotpin`) and BIT-7 owns porting them.
 * A PIN pad with no lockout is not a regression against a build that had no PIN at
 * all, but it must not be mistaken for the finished screen.
 */
@Composable
fun UnlockScreen(
    onUnlocked: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: WalletGateViewModel = hiltViewModel(),
) {
    var wrongPin by remember { mutableStateOf(false) }

    if (wrongPin) {
        BittrAlertDialog(
            title = UnlockStrings.INCORRECT_PIN,
            message = UnlockStrings.INCORRECT_PIN_2,
            confirmLabel = UnlockStrings.OKAY,
            onConfirm = { wrongPin = false },
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }

    PinScreen(
        title = UnlockStrings.ENTER_YOUR_PIN,
        onSubmit = { pin ->
            viewModel.unlock(pin) { unlocked ->
                if (unlocked) onUnlocked() else wrongPin = true
            }
        },
        modifier = modifier,
    )
}

/** Ported from `ios/bittr/Language.swift`; see `SignupStrings` for why not `strings.xml`. */
private object UnlockStrings {
    const val ENTER_YOUR_PIN = "Enter your PIN"
    const val INCORRECT_PIN = "Incorrect PIN"
    const val INCORRECT_PIN_2 =
        "Please enter your correct PIN. If you've forgotten it, please restore your wallet."
    const val OKAY = "Okay"
}
