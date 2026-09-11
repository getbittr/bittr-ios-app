package com.bittr.android.feature.signup

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBackspaceIcon
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.seed.SeedWalletService

/**
 * The PIN pad, shared by `Signup5` (set), `Signup6` (confirm) and the unlock screen —
 * the same three uses iOS gets out of one `PinViewController` via `embeddingView`.
 * Artboards 07–10, and 46–48 for unlock.
 *
 * It carries the `pin.*` test ids, which are the ones the iOS flows already drive, so
 * a Maestro flow written against iOS reads the same here.
 *
 * **The cells grow with the PIN.** The mock draws four, because four is the minimum
 * and what its artboards show. The app accepts four to eight
 * ([SeedWalletService.MIN_PIN_LENGTH]–[SeedWalletService.MAX_PIN_LENGTH]), so the row
 * shows `max(4, entered)` cells inside a fixed 260 dp: at four they are the mock's
 * 56 dp, and past that they narrow rather than running off the screen or silently
 * dropping the digits the user can see they typed.
 *
 * **It lives in `:feature:signup` for now and should not stay there.** Unlock is not a
 * signup concern, and BIT-7 should lift this into `:feature:pin` when it ports the
 * rest of the PIN behaviour — attempt counting, the wipe-after-ten warning
 * (`pinwarning2`), forgot-PIN. None of that is in BIT-93's scope: this pad sets a PIN
 * and checks a PIN, and nothing else. The mock's "Forgot PIN" affordance belongs with
 * that work, so it is not drawn here rather than drawn dead.
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
    confirmLabel: String = SignupStrings.CONFIRM,
) {
    var pin by remember { mutableStateOf("") }

    BittrCanvas(modifier = modifier, onBack = onBack) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = PinGutter),
        ) {
            CanvasSpacer(36.dp)
            BittrStepHeading(
                text = title,
                modifier = Modifier
                    .fillMaxWidth()
                    .then(titleTestTag?.let { Modifier.testTag(it) } ?: Modifier),
            )

            CanvasSpacer(18.dp)
            PinCells(length = pin.length)

            Spacer(Modifier.weight(1f))
            Keypad(
                onDigit = { digit ->
                    if (pin.length < SeedWalletService.MAX_PIN_LENGTH) pin += digit
                },
                onBackspace = { pin = pin.dropLast(1) },
                backspaceEnabled = pin.isNotEmpty(),
                digitsEnabled = pin.length < SeedWalletService.MAX_PIN_LENGTH,
            )

            CanvasSpacer(22.dp)
            BittrPrimaryButton(
                text = confirmLabel,
                onClick = { onSubmit(pin) },
                enabled = SeedWalletService.isValidPin(pin),
                arrow = false,
                modifier = Modifier.testTag(TestID.Pin.confirmButton),
            )
            if (onBack != null) {
                BittrTextButton(text = backLabel, onClick = onBack)
            } else {
                CanvasSpacer(12.dp)
            }
        }
    }
}

/** The mock's PIN screens use a wider gutter than the card screens. */
private val PinGutter = 24.dp

/** 56 × 74 at four cells, with the mock's 12 dp between them. */
private val CellRowMaxWidth = 260.dp
private val CellHeight = 74.dp

/**
 * The masked PIN, as cream cells with an ink dot.
 *
 * `pin.pinTextField` is on the row: it is the node the iOS flows assert against, and
 * on Android it is the only node that represents the field at all — there is no
 * `EditText` here, because a PIN pad that raises the soft keyboard is a PIN pad the
 * user can paste into.
 */
@Composable
private fun ColumnScope.PinCells(length: Int) {
    val cells = maxOf(SeedWalletService.MIN_PIN_LENGTH, length)
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .align(Alignment.CenterHorizontally)
            .widthIn(max = CellRowMaxWidth)
            .fillMaxWidth()
            .height(CellHeight)
            .semantics { contentDescription = "$length digits entered" }
            .testTag(TestID.Pin.pinTextField),
    ) {
        repeat(cells) { index ->
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(CellHeight)
                    .background(BittrTheme.colors.tonalFill, BittrCanvasShapes.cell),
            ) {
                if (index < length) {
                    Box(
                        Modifier
                            .size(13.dp)
                            .background(BittrTheme.colors.onTonalFill, CircleShape),
                    )
                }
            }
        }
    }
}

/**
 * 1–9, then a gap, 0 and delete — the mock's layout, which is also every phone
 * keypad's.
 *
 * The keys are transparent: on this canvas an outlined button per digit reads as
 * twelve competing buttons, and the ink digit on yellow is already 15.6 : 1.
 */
@Composable
private fun Keypad(
    onDigit: (Int) -> Unit,
    onBackspace: () -> Unit,
    backspaceEnabled: Boolean,
    digitsEnabled: Boolean,
) {
    val rows = listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                row.forEach { digit ->
                    DigitKey(digit = digit, enabled = digitsEnabled, onClick = { onDigit(digit) })
                }
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Spacer(Modifier.weight(1f))
            DigitKey(digit = 0, enabled = digitsEnabled, onClick = { onDigit(0) })
            Key(
                testTag = TestID.Pin.buttonBackspace,
                enabled = backspaceEnabled,
                onClick = onBackspace,
                contentDescription = "Delete",
            ) {
                BittrBackspaceIcon()
            }
        }
    }
}

@Composable
private fun RowScope.DigitKey(digit: Int, enabled: Boolean, onClick: () -> Unit) {
    Key(testTag = digitTestTag(digit), enabled = enabled, onClick = onClick) {
        Text(
            text = "$digit",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun RowScope.Key(
    testTag: String,
    enabled: Boolean,
    onClick: () -> Unit,
    contentDescription: String? = null,
    content: @Composable () -> Unit,
) {
    val label = contentDescription
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 62.dp)
            .clip(BittrCanvasShapes.pill)
            .clickable(enabled = enabled, onClick = onClick)
            .then(
                if (label != null) {
                    Modifier.semantics { this.contentDescription = label }
                } else {
                    Modifier
                },
            )
            .testTag(testTag)
            .padding(4.dp),
    ) {
        content()
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

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun PinScreenPreview() {
    BittrTheme {
        PinScreen(title = SignupStrings.SET_A_PIN, onSubmit = {})
    }
}
