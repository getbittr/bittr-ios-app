package com.bittr.android.feature.signup

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrNumeral
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrStepHeading
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.BittrValueRow
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.seed.Bip39

/**
 * Android counterpart of iOS `RestoreViewController` — the twelve fields.
 *
 * Built out of the same [WordField] shape as [VerifyScreen], because on iOS they are
 * literally the same control (`MnemonicTextField`) and a user who has been through
 * signup should recognise it. The differences are that there are twelve of them and
 * that nothing on this screen knows what the right answer is — the verdict comes from
 * `SeedPhraseEntry` via [RestoreWalletViewModel].
 *
 * **Restore is never dimmed.** [VerifyScreen] dims Confirm until all three fields have
 * something in them; here the button stays live on an incomplete phrase so the
 * `incompletephrase` alert is reachable, which is iOS's behaviour and the only way the
 * user is told *which* of the twelve they missed is a thing they can be told at all.
 *
 * **No autofill, no autocorrect, no capitalisation.** A keyboard that turns `attack`
 * into `Attack` or offers to save the phrase to the password manager is the single
 * most common way this screen fails someone who wrote their words down correctly.
 *
 * **The typed words are not `rememberSaveable`.** Saved state is written to disk on
 * process death, so the fields deliberately lose their contents on rotation rather
 * than persist the whole seed in cleartext outside the Keystore. That is a worse
 * trade-off here than on Verify — it is twelve words, not three — which is exactly
 * why it is made the same way.
 *
 * **The focused field is parked near the top, so the next ones are above the keyboard.**
 * Twelve fields plus a keyboard are taller than any phone, and the first emulator run
 * of `restore_wallet.yaml` stopped at field 7: it sat behind the keyboard, where it
 * cannot be seen or tapped. Asking Compose to bring the next field into view on focus
 * was not enough, because moving focus between text fields hides and re-shows the
 * keyboard — the visible area changes height mid-animation, and a request made against
 * that height lands short. So focusing a field scrolls it, without animation, to one
 * row below the top of the visible area, and while a field has focus the content gets
 * a visible-area's worth of room below it so even the twelfth can go there. That does
 * not depend on what the keyboard is doing at the time.
 *
 * **The same screen serves the forgot-PIN reset**, which is iOS's arrangement too —
 * `startPinReset` opens this very view controller with `resettingPin` set, and the
 * only visible difference is that the primary button reads "Reset PIN". Hence
 * [submitLabel]. What differs is entirely behind [onSubmit]: restoring stores whatever
 * valid phrase was typed, resetting checks it against the phrase already on the
 * device and stores nothing. See `UnlockViewModel`.
 *
 * What is not ported: the "wallet recovery" article chip, which needs the article
 * fetch BIT-7 owns, and `removeWalletButton` — the "I have lost my phrase too, wipe
 * the wallet" escape hatch iOS shows on the reset path. That one leads to
 * `restoreWalletTapped`, whose no-channel and channel-close branches are
 * `remove_wallet.yaml` and belong with BIT-6's wave, not here.
 *
 * @param submitLabel the primary button — "Restore wallet" when adopting a phrase,
 *   "Reset PIN" when proving one you already have.
 */
@Composable
fun RestoreScreen(
    onSubmit: (List<String>) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
    submitLabel: String = SignupStrings.RESTORE_WALLET,
) {
    val words = remember { mutableStateListOf(*Array(Bip39.WORD_COUNT) { "" }) }
    val focusRequesters = remember { List(Bip39.WORD_COUNT) { FocusRequester() } }
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    val density = LocalDensity.current

    val scrollState = rememberScrollState()
    var focusedIndex by remember { mutableIntStateOf(NO_FOCUS) }
    // Where the visible area starts on screen, and how tall it is, in px.
    var viewportTop by remember { mutableIntStateOf(0) }
    var viewportHeight by remember { mutableIntStateOf(0) }
    // Each row's top on screen, in px, as of its last placement.
    val rowTops = remember { IntArray(Bip39.WORD_COUNT) }

    LaunchedEffect(focusedIndex) {
        if (focusedIndex == NO_FOCUS) return@LaunchedEffect
        // Top of the row within the scrolled content: where it is on screen, minus
        // where the visible area starts, plus how far the content is already scrolled.
        val rowInContent = rowTops[focusedIndex] - viewportTop + scrollState.value
        val oneRowAbove = with(density) { (RowHeight + RowGap).roundToPx() }
        scrollState.scrollTo((rowInContent - oneRowAbove).coerceAtLeast(0))
    }

    fun submit() {
        keyboard?.hide()
        onSubmit(words.toList())
    }

    BittrCanvas(modifier = modifier, onBack = onCancel) {
        // Above the scroll, not inside it: a focused field is parked near the top of the
        // visible area, which would scroll the heading away. `restore_wallet.yaml` taps
        // it after the twelfth word to put the keyboard away — on iOS that tap falls
        // through to `backgroundButtonTapped` — so it has to stay on screen, and a tap
        // on it does the same thing here.
        BittrStepHeading(
            text = SignupStrings.ENTER_RECOVERY_PHRASE,
            modifier = Modifier
                .padding(horizontal = CanvasGutter)
                .padding(top = BittrTokens.Spacing.sm)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    focusManager.clearFocus()
                    keyboard?.hide()
                }
                .testTag(TestID.Signup.Restore.topLabel),
        )

        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                // Before the scroll, not inside it: padding applied inside a scroll
                // container pads the content and leaves the viewport running under
                // the keyboard. Applied here, the visible area ends at the keyboard.
                .imePadding()
                .onGloballyPositioned { coordinates ->
                    viewportTop = coordinates.positionInRoot().y.toInt()
                }
                .onSizeChanged { viewportHeight = it.height }
                .verticalScroll(scrollState)
                .padding(horizontal = CanvasGutter, vertical = BittrTokens.Spacing.lg),
        ) {
            BittrCard {
                repeat(Bip39.WORD_COUNT) { index ->
                    if (index > 0) CanvasSpacer(RowGap)
                    val last = index == Bip39.WORD_COUNT - 1
                    WordField(
                        wordNumber = index + 1,
                        value = words[index],
                        onValueChange = { words[index] = it },
                        fieldTag = RestoreFieldTags[index],
                        last = last,
                        focusRequester = focusRequesters[index],
                        onPlaced = { top -> rowTops[index] = top },
                        onFocusChange = { focused ->
                            if (focused) {
                                focusedIndex = index
                            } else if (focusedIndex == index) {
                                focusedIndex = NO_FOCUS
                            }
                        },
                        // Next walks the fields; Done on the twelfth submits, which
                        // is RestoreViewController's `textField.tag == 12` branch.
                        onImeAction = {
                            if (last) submit() else focusRequesters[index + 1].requestFocus()
                        },
                    )
                }

                CanvasSpacer(BittrTokens.Spacing.xl)
                BittrPrimaryButton(
                    text = submitLabel,
                    onClick = ::submit,
                    enabled = !busy,
                    modifier = Modifier.testTag(TestID.Signup.Restore.nextButton),
                )
                BittrTextButton(text = SignupStrings.CANCEL, onClick = onCancel)
            }

            // Room to park even the last field one row from the top. Only while a field
            // has focus, so the resting layout is unchanged.
            if (focusedIndex != NO_FOCUS && viewportHeight > 0) {
                Spacer(Modifier.height(with(density) { viewportHeight.toDp() }))
            }
        }
    }
}

private const val NO_FOCUS = -1

/** [BittrValueRow]'s default height, which every row here uses. */
private val RowHeight = 56.dp

/** The gap between rows. */
private val RowGap = 12.dp

/**
 * `signup.restore.field1` … `field12`, in field order.
 *
 * Listed rather than built from `"signup.restore.field${i + 1}"` so the ids stay
 * greppable against `shared/test-ids/test-ids.json` and the iOS `viewDidLoad` that
 * assigns them — a generated string matches nothing when someone searches for where
 * a failing Maestro selector comes from.
 */
private val RestoreFieldTags = listOf(
    TestID.Signup.Restore.field1,
    TestID.Signup.Restore.field2,
    TestID.Signup.Restore.field3,
    TestID.Signup.Restore.field4,
    TestID.Signup.Restore.field5,
    TestID.Signup.Restore.field6,
    TestID.Signup.Restore.field7,
    TestID.Signup.Restore.field8,
    TestID.Signup.Restore.field9,
    TestID.Signup.Restore.field10,
    TestID.Signup.Restore.field11,
    TestID.Signup.Restore.field12,
)

/**
 * One numbered field. The restore twin of `VerifyScreen`'s private `WordField`.
 *
 * Kept separate rather than shared because this one has to drive focus to the next
 * field — twelve fields is enough that making the user tap each one is a real cost,
 * where three is not — and folding the focus plumbing into Verify's would complicate
 * the screen that does not need it.
 *
 * @param onPlaced the row's top on screen, in px, each time it is placed.
 */
@Composable
private fun WordField(
    wordNumber: Int,
    value: String,
    onValueChange: (String) -> Unit,
    fieldTag: String,
    last: Boolean,
    focusRequester: FocusRequester,
    onPlaced: (Int) -> Unit,
    onFocusChange: (Boolean) -> Unit,
    onImeAction: () -> Unit,
) {
    BittrValueRow(
        modifier = Modifier.onGloballyPositioned { onPlaced(it.positionInRoot().y.toInt()) },
    ) {
        BittrNumeral(text = "$wordNumber", width = 22.dp)
        Box(
            contentAlignment = Alignment.CenterStart,
            modifier = Modifier
                .weight(1f)
                .padding(start = BittrTokens.Spacing.lg),
        ) {
            if (value.isEmpty()) {
                Text(
                    text = SignupStrings.ENTER_WORD,
                    style = MaterialTheme.typography.bodyLarge,
                    // A11Y-21: placeholders on a field fill use `onSurfaceVariant`,
                    // never `outline`.
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = LocalTextStyle.current.merge(
                    MaterialTheme.typography.labelLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = if (last) ImeAction.Done else ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { onImeAction() },
                    onDone = { onImeAction() },
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester)
                    .onFocusChanged { onFocusChange(it.isFocused) }
                    .testTag(fieldTag),
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun RestoreScreenPreview() {
    BittrTheme {
        RestoreScreen(onSubmit = {}, onCancel = {})
    }
}
