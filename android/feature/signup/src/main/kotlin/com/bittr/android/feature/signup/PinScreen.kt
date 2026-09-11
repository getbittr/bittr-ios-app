package com.bittr.android.feature.signup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.wallet.seed.SeedWalletService

/**
 * The PIN pad, shared by `Signup5` (set), `Signup6` (confirm) and the unlock screen —
 * the same three uses iOS gets out of one `PinViewController` via `embeddingView`.
 *
 * It carries the `pin.*` test ids, which are the ones the iOS flows already drive, so
 * a Maestro flow written against iOS reads the same here.
 *
 * **It lives in `:feature:signup` for now and should not stay there.** Unlock is not a
 * signup concern, and BIT-7 should lift this into `:feature:pin` when it ports the
 * rest of the PIN behaviour — attempt counting, the wipe-after-ten warning
 * (`pinwarning2`), forgot-PIN. None of that is in BIT-93's scope: this pad sets a PIN
 * and checks a PIN, and nothing else.
 *
 * @param title the instruction above the pad — which of the three uses this is.
 * @param onSubmit called with the digits when the user confirms.
 * @param titleTestTag the screen-level id; the signup steps have their own.
 */
@Composable
fun PinScreen(
    title: String,
    onSubmit: (String) -> Unit,
    modifier: Modifier = Modifier,
    titleTestTag: String? = null,
    onBack: (() -> Unit)? = null,
    backLabel: String = SignupStrings.BACK,
) {
    var pin by remember { mutableStateOf("") }

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
            text = title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = titleTestTag?.let { Modifier.testTag(it) } ?: Modifier,
        )

        // The digits are masked on screen, as on iOS. The test id is on the masked
        // field because that is the node the flows assert against.
        Text(
            text = "•".repeat(pin.length),
            style = MaterialTheme.typography.displaySmall,
            modifier = Modifier
                .heightIn(min = BittrTokens.Size.minTouchTarget)
                .testTag(TestID.Pin.pinTextField),
        )

        // 1–9, then backspace, 0, and the confirm below.
        val rows = listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))
        rows.forEach { row ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                modifier = Modifier.fillMaxWidth(),
            ) {
                row.forEach { digit ->
                    PinKey(
                        label = "$digit",
                        testTag = digitTestTag(digit),
                        enabled = pin.length < SeedWalletService.MAX_PIN_LENGTH,
                        onClick = { pin += digit.toString() },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
            modifier = Modifier.fillMaxWidth(),
        ) {
            PinKey(
                label = "⌫",
                testTag = TestID.Pin.buttonBackspace,
                enabled = pin.isNotEmpty(),
                onClick = { pin = pin.dropLast(1) },
                modifier = Modifier.weight(1f),
            )
            PinKey(
                label = "0",
                testTag = TestID.Pin.button0,
                enabled = pin.length < SeedWalletService.MAX_PIN_LENGTH,
                onClick = { pin += "0" },
                modifier = Modifier.weight(1f),
            )
            // Keeps the pad a 3-wide grid rather than letting 0 stretch.
            Spacer(Modifier.weight(1f))
        }

        Button(
            onClick = { onSubmit(pin) },
            enabled = SeedWalletService.isValidPin(pin),
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Pin.confirmButton),
        ) {
            Text(SignupStrings.CONFIRM)
        }

        if (onBack != null) {
            TextButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                Text(backLabel)
            }
        }
    }
}

/**
 * `TestIDs.kt` is generated from `shared/test-ids/test-ids.json` and declares the ten
 * digits as ten constants, so the mapping is spelled out here rather than by editing
 * a generated file. Keeping it exhaustive means a renamed id fails to compile.
 */
private fun digitTestTag(digit: Int): String = when (digit) {
    0 -> TestID.Pin.button0
    1 -> TestID.Pin.button1
    2 -> TestID.Pin.button2
    3 -> TestID.Pin.button3
    4 -> TestID.Pin.button4
    5 -> TestID.Pin.button5
    6 -> TestID.Pin.button6
    7 -> TestID.Pin.button7
    8 -> TestID.Pin.button8
    9 -> TestID.Pin.button9
    else -> error("Not a digit: $digit")
}

@Composable
private fun PinKey(
    label: String,
    testTag: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .heightIn(min = BittrTokens.Size.minTouchTarget)
            .testTag(testTag),
    ) {
        Text(text = label, style = MaterialTheme.typography.titleLarge)
    }
}

@Preview(showBackground = true)
@Composable
private fun PinScreenPreview() {
    BittrTheme {
        PinScreen(title = SignupStrings.SET_A_PIN, onSubmit = {})
    }
}
