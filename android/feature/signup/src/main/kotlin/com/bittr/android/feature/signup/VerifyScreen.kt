package com.bittr.android.feature.signup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.seed.SeedChallenge
import com.bittr.android.core.wallet.seed.SeedCheck

/**
 * Android counterpart of iOS `Signup4ViewController` — type three of the words back.
 * Artboards 05 and 06.
 *
 * The gate itself is [SeedChallenge], not this file: whether an answer is accepted is
 * decided in pure Kotlin, tested in `SeedChallengeTest`, and the composable only
 * collects strings and reports the verdict. BIT-19 records that iOS has no negative
 * coverage here at all, which is the reason the check lives somewhere a unit test can
 * reach it.
 *
 * **Confirm is always tappable, as on iOS.** The mock dims it until all three fields
 * have something in them, and an earlier port did that — but
 * `seed_gate_rejects_wrong_words.yaml` presses Confirm with a field empty and asserts
 * `alert.missingWords`, and `shared/docs/parity.md` marks that flow parity-critical and
 * to be passed unchanged. A dimmed button swallows the tap, so the `SeedCheck.Missing`
 * branch never fires and the flow fails on Android alone. The rejection lives in the
 * view model either way; this screen just lets the press through.
 *
 * **The keyboard never hides Confirm.** Next moves to the next word; Done on the third
 * submits once all three have something in them. Tapping the heading closes the
 * keyboard, as iOS's `backgroundButtonTapped` does — `seed_gate_rejects_wrong_words.yaml`
 * taps it before Confirm — and the content is padded above the keyboard so the button
 * stays reachable.
 *
 * **The third field losing focus with the right words submits**, as
 * `Signup4ViewController.textFieldDidEndEditing` does. Both `happy_path_wallet.yaml` and
 * `seed_gate_rejects_wrong_words.yaml` type the three words, tap the heading to close
 * the keyboard, and expect the PIN screen — never Confirm. Only a match advances:
 * losing focus with wrong words must leave the user on this screen, and does. The
 * screen remembers that it advanced so Done (which submits, then closes the keyboard)
 * does not submit a second time on the focus change it causes.
 *
 * **The typed words are not `rememberSaveable`.** Three of the twelve words are still
 * three of the twelve; saved state is written to disk on process death, so the fields
 * deliberately lose their contents on rotation rather than persist a third of the
 * user's seed outside the Keystore.
 */
@Composable
fun VerifyScreen(
    challenge: SeedChallenge,
    onSubmit: (List<String>) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val answers = remember(challenge) {
        mutableStateListOf(*Array(SeedChallenge.ASK_COUNT) { "" })
    }
    val fieldTags = listOf(
        TestID.Signup.Create.Verify.field1,
        TestID.Signup.Create.Verify.field2,
        TestID.Signup.Create.Verify.field3,
    )
    val labelTags = listOf(
        TestID.Signup.Create.Verify.label1,
        TestID.Signup.Create.Verify.label2,
        TestID.Signup.Create.Verify.label3,
    )
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun closeKeyboard() {
        focusManager.clearFocus()
        keyboard?.hide()
    }
    // iOS advances once, on the blur; Done's own submit closes the keyboard, and that
    // blur must not submit again.
    var advanced by remember(challenge) { mutableStateOf(false) }
    fun submit() {
        if (challenge.check(answers.toList()) == SeedCheck.Correct) advanced = true
        closeKeyboard()
        onSubmit(answers.toList())
    }

    BackHandler(onBack = onBack)
    // No arrow in the app bar: the card's own button goes back, as on iOS, and the system back
    // gesture does what that button does.
    BittrCanvas(modifier = modifier) {
        // Signup4's scene: `centerCard` 15 from the screen edges, centred 40 above the middle.
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                // Before the scroll: the visible area ends at the keyboard, so Confirm
                // can be scrolled into view above it.
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(start = 15.dp, end = 15.dp, bottom = 80.dp),
        ) {
            // The label 30 below the card's top; Back's 25 pt row 20 above its bottom, less the
            // half of its 48 dp touch target that iOS's row does not have.
            BittrCard(contentPadding = PaddingValues(top = 30.dp, bottom = 8.dp)) {
                Text(
                    text = SignupStrings.CONFIRM_RECOVERY_PHRASE,
                    // Gilroy Bold 16, centred, 40 from the card's sides.
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .padding(horizontal = 40.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = ::closeKeyboard,
                        )
                        .testTag(TestID.Signup.Create.Verify.topLabel),
                )
                CanvasSpacer(30.dp)

                challenge.labels.forEachIndexed { index, wordNumber ->
                    if (index > 0) CanvasSpacer(10.dp)
                    WordField(
                        wordNumber = wordNumber,
                        value = answers[index],
                        onValueChange = { answers[index] = it },
                        labelTag = labelTags[index],
                        fieldTag = fieldTags[index],
                        last = index == SeedChallenge.ASK_COUNT - 1,
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                        onDone = {
                            if (answers.all { it.isNotBlank() }) submit() else closeKeyboard()
                        },
                        onFocusLost = {
                            if (index == SeedChallenge.ASK_COUNT - 1 && !advanced &&
                                challenge.check(answers.toList()) == SeedCheck.Correct
                            ) {
                                submit()
                            }
                        },
                    )
                }

                CanvasSpacer(30.dp)
                BittrPrimaryButton(
                    text = SignupStrings.CONFIRM,
                    onClick = ::submit,
                    modifier = Modifier.testTag(TestID.Signup.Create.Verify.nextButton),
                )
                // iOS leaves 10 pt and a 25 pt row for Back; its 48 dp touch target spends the 10.
                BittrTextButton(
                    text = SignupStrings.BACK,
                    onClick = onBack,
                    modifier = Modifier.testTag(TestID.Signup.Create.Verify.backButton),
                )
            }
        }
    }
}

/**
 * One white field with its word number in it — iOS's `mnemonicView`: white in both schemes, 200 by
 * 45 with 8 pt corners. The number 25 in and 20 wide, in Gilroy Bold 16 and the brand yellow; the
 * field 15 after it and 15 from the right, in Gilroy Regular 18, black, with a gray placeholder.
 * Both sit 1 pt below the row's centre, as the storyboard has them.
 *
 * The yellow numbers on white are 1.7 : 1, the pairing DEV-40 darkened for `DetailRow` labels;
 * matched to iOS here at Tom's request, as on Signup3 and Restore.
 *
 * The number is a label *inside* the field's container but outside its text, as on
 * iOS and in the mock — not Material's floating label. As a floating label it reads as
 * the field's own placeholder: a lone "5" sitting where the answer goes, with no hint
 * that it means "the fifth word".
 *
 * [BasicTextField] rather than `OutlinedTextField` because the mock's field has no
 * outline, no floating label and no 16 dp of Material's internal padding — reskinning
 * `OutlinedTextField` this far means fighting every one of its defaults.
 */
@Composable
private fun WordField(
    wordNumber: Int,
    value: String,
    onValueChange: (String) -> Unit,
    labelTag: String,
    fieldTag: String,
    last: Boolean,
    onNext: () -> Unit,
    onDone: () -> Unit,
    onFocusLost: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .size(width = 200.dp, height = 45.dp)
            .background(colors.phraseCard, WordFieldShape)
            .offset(y = 1.dp)
            .padding(start = 25.dp, end = 15.dp),
    ) {
        Text(
            text = "$wordNumber",
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 16.sp),
            color = colors.brandFixed,
            modifier = Modifier
                .width(20.dp)
                .testTag(labelTag),
        )
        Box(
            contentAlignment = Alignment.CenterStart,
            modifier = Modifier
                .weight(1f)
                .padding(start = 15.dp),
        ) {
            val wordStyle = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 22.sp)
            if (value.isEmpty()) {
                Text(
                    text = SignupStrings.ENTER_WORD,
                    style = wordStyle,
                    color = colors.phrasePlaceholder,
                    maxLines = 1,
                )
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = wordStyle.copy(color = colors.onPhraseCard),
                cursorBrush = SolidColor(colors.onPhraseCard),
                // No autocorrect and no capitalisation: the keyboard "helpfully"
                // turning `abandon` into `Abandon` or into a different word is the
                // single most common way this screen fails for a user who did write
                // the phrase down correctly.
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = if (last) ImeAction.Done else ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { onNext() },
                    onDone = { onDone() },
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .onFocusChanged { state ->
                        if (focused && !state.isFocused) onFocusLost()
                        focused = state.isFocused
                    }
                    .testTag(fieldTag),
            )
        }
    }
}

private val WordFieldShape = RoundedCornerShape(8.dp)

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun VerifyScreenPreview() {
    BittrTheme {
        VerifyScreen(
            challenge = SeedChallenge(
                Mnemonic(
                    listOf(
                        "abandon", "ability", "able", "about", "above", "absent",
                        "absorb", "abstract", "absurd", "abuse", "access", "accident",
                    ),
                ),
                listOf(0, 5, 11),
            ),
            onSubmit = {},
            onBack = {},
        )
    }
}
