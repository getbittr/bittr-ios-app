package com.bittr.android.feature.signup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.wallet.seed.SeedWalletService

/**
 * The PIN pad, shared by `Signup5` (set), `Signup6` (confirm) and the unlock screen —
 * the same three uses iOS gets out of one `PinViewController` via `embeddingView`.
 * Artboards 07–10, and 46–48 for unlock.
 *
 * It carries the `pin.*` test ids, which are the ones the iOS flows already drive, so
 * a Maestro flow written against iOS reads the same here.
 *
 * **One card per digit typed, and none before**, as iOS's `pinCollectionView` has it: a
 * 40 × 60 card for each of the four to eight digits
 * ([SeedWalletService.MIN_PIN_LENGTH]–[SeedWalletService.MAX_PIN_LENGTH]), 10 apart and
 * centred. Eight are wider than a narrow screen, so the row scrolls then, as iOS's does.
 *
 * **It lives in `:feature:signup` and still should not stay there.** BIT-97 ported the
 * rest of the PIN behaviour — attempt counting, the wipe-after-ten warning
 * (`pinwarning2`), forgot-PIN — into `:app`'s `UnlockScreen` rather than moving this
 * file, because the reset arc reuses [RestoreScreen] as well as this pad and a
 * `:feature:pin` that depended on `:feature:signup` would have the arrow pointing the
 * wrong way. Lifting both screens out is the move, and it is a module change rather
 * than a behaviour one. This pad still only sets a PIN and checks a PIN; everything
 * that decides what a wrong one *means* is in `UnlockViewModel`.
 *
 * @param title the instruction above the pad — which of the three uses this is.
 * @param onSubmit called with the digits when the user confirms.
 * @param titleTestTag the screen-level id; the signup steps have their own.
 * @param onBack the secondary button under Confirm. iOS's `restoreWalletButton`: Back
 *   on the signup steps, "Forgot PIN" on unlock — one button and one id
 *   ([TestID.Pin.restoreButton]) in both, with [backLabel] saying which it is.
 * @param clearKey empty the cells whenever this changes — `clearPinField()`, which iOS calls
 *   on unlock when a PIN is refused, and only then: a PIN that unlocks stays in the cells,
 *   the button stays live, while the pad slides away to Home. Without the clearing the next
 *   four taps would append to the digits just refused, and at the eight-digit cap the pad
 *   would stop accepting input entirely. Left alone on the signup steps, matching
 *   `Signup6ViewController`, where a mismatch leaves what was typed so the user can correct
 *   a single digit rather than retype all of it.
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
    clearKey: Int = 0,
) {
    var pin by remember { mutableStateOf("") }
    val initialClearKey = remember { clearKey }
    LaunchedEffect(clearKey) { if (clearKey != initialClearKey) pin = "" }

    BackHandler(enabled = onBack != null) { onBack?.invoke() }
    // No arrow in the app bar: Back under the pad goes back, as on iOS, and the system back
    // gesture does what that button does.
    BittrCanvas(modifier = modifier, background = BittrTheme.colors.primaryHigh) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = PinGutter),
        ) {
            // The label and the PIN cards, centred as one group in the room between the top bar and
            // the keypad — iOS centres them in the view from under its top bar to the pad's top.
            // The cards' row keeps its height with no digits, so the label does not move as they
            // appear.
            Column(
                verticalArrangement = Arrangement.Center,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            ) {
                BittrStepHeading(
                    text = title,
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(titleTestTag?.let { Modifier.testTag(it) } ?: Modifier),
                )

                CanvasSpacer(15.dp)
                PinCells(length = pin.length)
            }

            Keypad(
                onDigit = { digit ->
                    if (pin.length < SeedWalletService.MAX_PIN_LENGTH) pin += digit
                },
                onBackspace = { pin = pin.dropLast(1) },
                backspaceEnabled = pin.isNotEmpty(),
                digitsEnabled = pin.length < SeedWalletService.MAX_PIN_LENGTH,
            )

            CanvasSpacer(30.dp)
            // iOS's `confirmPinView`: 45 tall with 8 pt corners and `setShadow()`, the label alone and
            // centred, running from 5 left of the 1 to 5 right of the 3 — two key columns plus about
            // 22, centred under the pad.
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val column = (maxWidth - KeySpacing * 2) / 3 + KeySpacing
                BittrPrimaryButton(
                    text = confirmLabel,
                    onClick = {
                        onSubmit(pin)
                    },
                    enabled = SeedWalletService.isValidPin(pin),
                    // iOS never dims it; light mode does until the PIN is long enough.
                    dimmed = !SeedWalletService.isValidPin(pin) && !BittrTheme.isDark,
                    fill = BittrTheme.colors.pinConfirm,
                    arrow = false,
                    modifier = Modifier
                        .size(width = column * 2 + 22.dp, height = 45.dp)
                        .iosShadow(ConfirmShape)
                        .testTag(TestID.Pin.confirmButton),
                )
            }
            // Without a back button the confirm pill would otherwise sit on the
            // screen's bottom edge — `navigationBarsPadding` is zero on a
            // three-button device and on the render harness, so the gap has to be
            // real rather than borrowed from the inset.
            // One button, three labels — iOS's `restoreWalletButton`, which is "Back"
            // under Signup6/Restore3 and "Forgot PIN" on unlock. It carries
            // `pin.restoreButton` in every embedding there, so it does here: the
            // flows select it by that id whichever of the three they are driving.
            if (onBack != null) {
                BittrTextButton(
                    text = backLabel,
                    onClick = onBack,
                    modifier = Modifier.testTag(TestID.Pin.restoreButton),
                )
            } else {
                CanvasSpacer(20.dp)
            }
        }
    }
}

/** The mock's PIN screens use a wider gutter than the card screens. */
private val PinGutter = 24.dp

/** Between the keypad's keys, across and down. */
private val KeySpacing = 6.dp

/** The confirm plate's corners — BittrPrimaryButton's own 8 pt. */
private val ConfirmShape = RoundedCornerShape(8.dp)

/** `PinCollectionViewCell`: 40 × 60, 10 apart. */
private val CellWidth = 40.dp
private val CellHeight = 60.dp
private val CellSpacing = 10.dp
private val CellShape = RoundedCornerShape(13.dp)

/**
 * The masked PIN, as iOS's `PinCollectionViewCell`s: a `pinCell` card per digit with
 * 13 pt corners and `setShadow()`, and a 10 pt black dot in its centre. The row keeps its
 * 60 pt height with no digits, so the pad does not move as the first one appears.
 *
 * `pin.pinTextField` is on the row: it is the node the iOS flows assert against, and
 * on Android it is the only node that represents the field at all — there is no
 * `EditText` here, because a PIN pad that raises the soft keyboard is a PIN pad the
 * user can paste into.
 */
@Composable
private fun ColumnScope.PinCells(length: Int) {
    val colors = BittrTheme.colors
    val scroll = rememberScrollState()
    BoxWithConstraints(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(CellHeight)
            .semantics { contentDescription = "$length digits entered" }
            .testTag(TestID.Pin.pinTextField),
    ) {
        // Scrolls only when the cards are wider than the screen: a scrolling row clips what is
        // drawn outside it, and that would cut the cards' shadows off at every length.
        val rowWidth = CellWidth * length + CellSpacing * (length - 1).coerceAtLeast(0)
        Row(
            horizontalArrangement = Arrangement.spacedBy(CellSpacing),
            modifier = if (rowWidth > maxWidth) Modifier.horizontalScroll(scroll) else Modifier,
        ) {
            repeat(length) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(width = CellWidth, height = CellHeight)
                        .iosShadow(CellShape)
                        .background(colors.pinCell, CellShape),
                ) {
                    Box(
                        Modifier
                            .size(10.dp)
                            .background(colors.onPinCell, CircleShape),
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
    Column(verticalArrangement = Arrangement.spacedBy(KeySpacing)) {
        rows.forEach { row ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(KeySpacing),
                modifier = Modifier.fillMaxWidth(),
            ) {
                row.forEach { digit ->
                    DigitKey(digit = digit, enabled = digitsEnabled, onClick = { onDigit(digit) })
                }
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(KeySpacing),
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
            // A 56 dp circle of ink behind the numeral when pressed, not a pill as wide as the
            // column and clipped by its neighbours (review S17).
            .clickable(
                enabled = enabled,
                interactionSource = null,
                indication = ripple(bounded = false, radius = 28.dp, color = BittrTheme.colors.pinKeyPress),
                onClick = onClick,
            )
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
