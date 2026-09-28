package com.bittr.android.feature.signup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.appBarContentPadding
import com.bittr.android.core.designsystem.AppBarContentInset
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.wallet.seed.Bip39
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles

/**
 * Android counterpart of iOS `RestoreViewController` — the twelve fields.
 *
 * Laid out as the storyboard's scene is (decision 55): no yellow card, but one white card of
 * twelve numbered words in two columns under a centred heading, and the button without an arrow.
 * Nothing on this screen knows what the right answer is — the verdict comes from
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
 * **With a field focused, the heading is parked at the top, so every field is above the
 * keyboard.** The first emulator run of `restore_wallet.yaml`, with twelve 56 dp rows, stopped
 * at field 7 behind the keyboard. Asking Compose to bring the next field into view on focus
 * was not enough, because moving focus between text fields hides and re-shows the keyboard —
 * the visible area changes height mid-animation, and a request made against that height lands
 * short. So focusing a field scrolls, without animation, to put the heading at the top of the
 * visible area, and while a field has focus the content gets a visible-area's worth of room
 * below it. iOS's white card is 240 pt, so heading and all twelve fields then fit above the
 * keyboard, and the heading the flows tap to dismiss it stays on screen.
 *
 * **The same screen serves the forgot-PIN reset**, which is iOS's arrangement too —
 * `startPinReset` opens this very view controller with `resettingPin` set, and the
 * only visible difference is that the primary button reads "Reset PIN". Hence
 * [submitLabel]. What differs is entirely behind [onSubmit]: restoring stores whatever
 * valid phrase was typed, resetting checks it against the phrase already on the
 * device and stores nothing. See `UnlockViewModel`.
 *
 * The "wallet recovery" article card (`pageArticle1Slug`) sits under the card when
 * [onOpenArticle] is given.
 *
 * @param submitLabel the primary button — "Restore wallet" when adopting a phrase,
 *   "Reset PIN" when proving one you already have.
 * @param onRemoveWallet the reset path's `removeWalletButton` — "I have lost my phrase
 *   too" — or null on the restore arc, where there is no wallet to remove.
 */
@Composable
fun RestoreScreen(
    onSubmit: (List<String>) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
    submitLabel: String = SignupStrings.RESTORE_WALLET,
    onRemoveWallet: (() -> Unit)? = null,
    onOpenArticle: ((String) -> Unit)? = null,
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
    // The heading's top on screen, in px, as of its last placement.
    var headingTop by remember { mutableIntStateOf(0) }
    // The top bar the content scrolls under: the status bar and the bar's 50, in px.
    val appBarBottom = WindowInsets.statusBars.getTop(density) + with(density) { AppBarContentInset.roundToPx() }

    // With a field focused, the heading goes to the top of the visible area, just below the top
    // bar the content scrolls under. The white card is
    // compact enough that all twelve fields then sit between it and the keyboard, and the heading
    // stays on screen — `forgot_pin.yaml` taps it after the last word to put the keyboard away,
    // which on iOS falls through to `backgroundButtonTapped`.
    LaunchedEffect(focusedIndex) {
        if (focusedIndex == NO_FOCUS) return@LaunchedEffect
        scrollState.scrollTo((headingTop - viewportTop - appBarBottom + scrollState.value).coerceAtLeast(0))
    }

    fun submit() {
        keyboard?.hide()
        onSubmit(words.toList())
    }

    BackHandler(onBack = onCancel)
    // No arrow in the app bar: Cancel goes back, as on iOS, and the system back
    // gesture does what that button does. The fields scroll up under the translucent top bar.
    BittrCanvas(modifier = modifier, scrollsUnderAppBar = true) {
        // RestoreViewController's scene: no yellow card. The heading, the white card of twelve
        // words 30 below it, the button 30 below that, Cancel, and the article card — one group,
        // centred 40 above the middle of the screen.
        Column(
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
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
                .appBarContentPadding()
                .padding(top = BittrTokens.Spacing.lg, bottom = BittrTokens.Spacing.lg + 80.dp),
        ) {
            Text(
                text = SignupStrings.ENTER_RECOVERY_PHRASE,
                // Gilroy Bold 16, centred, 40 from the screen edges.
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .onGloballyPositioned { headingTop = it.positionInRoot().y.toInt() }
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        focusManager.clearFocus()
                        keyboard?.hide()
                    }
                    .testTag(TestID.Signup.Restore.topLabel),
            )
            CanvasSpacer(30.dp)

            // `mnemonicView`: white, 13 pt corners, `setShadow()`, 40 from the screen edges and 15
            // inside. Two columns of six rows, each 35 pt — the storyboard's 240 pt card less its
            // padding, in six — so the buttons under it stay on screen:
            // forgot_pin_remove_wallet.yaml taps `removeWalletButton` without scrolling.
            val colors = BittrTheme.colors
            Column(
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .fillMaxWidth()
                    .iosShadow(IosCardShape)
                    .background(colors.phraseCard, IosCardShape)
                    .padding(15.dp),
            ) {
                repeat(Bip39.WORD_COUNT / FieldColumns) { row ->
                    Row(modifier = Modifier.height(RowHeight)) {
                        repeat(FieldColumns) { column ->
                            val index = row * FieldColumns + column
                            val last = index == Bip39.WORD_COUNT - 1
                            WordField(
                                wordNumber = index + 1,
                                value = words[index],
                                onValueChange = { words[index] = it },
                                fieldTag = RestoreFieldTags[index],
                                last = last,
                                focusRequester = focusRequesters[index],
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
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                        }
                    }
                }
            }

            CanvasSpacer(30.dp)
            // iOS's `restoreView`: the plate with its label alone — no arrow.
            BittrPrimaryButton(
                text = submitLabel,
                onClick = ::submit,
                enabled = !busy,
                arrow = false,
                modifier = Modifier.testTag(TestID.Signup.Restore.nextButton),
            )
            // iOS leaves 10 pt and a 25 pt row for Cancel; its 48 dp touch target spends the 10.
            BittrTextButton(text = SignupStrings.CANCEL, onClick = onCancel)
            if (onRemoveWallet != null) {
                BittrTextButton(
                    text = SignupStrings.REMOVE_WALLET_FROM_DEVICE,
                    onClick = onRemoveWallet,
                    modifier = Modifier.testTag(TestID.Signup.Restore.removeWalletButton),
                )
            }
            if (onOpenArticle != null) {
                // 50 below Cancel's 25 pt row on iOS, less the rest of the 48 dp target.
                CanvasSpacer(38.dp)
                // RestoreViewController's `pageArticle1Slug = "wallet-recovery"`.
                ArticleCard(slug = BittrArticles.WALLET_RECOVERY, onOpen = onOpenArticle)
            }

            // Room to park the heading at the top. Only while a field has focus, so the
            // resting layout is unchanged.
            if (focusedIndex != NO_FOCUS && viewportHeight > 0) {
                Spacer(Modifier.height(with(density) { viewportHeight.toDp() }))
            }
        }
    }
}

private const val NO_FOCUS = -1

/** The storyboard's two columns of six fields. */
private const val FieldColumns = 2

/** One row of the white card: (240 − 2 × 15) / 6. */
private val RowHeight = 35.dp

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
 * One numbered word in the white card. The restore twin of `VerifyScreen`'s private
 * `WordField`, kept separate because this one drives focus to the next field.
 */
@Composable
private fun WordField(
    wordNumber: Int,
    value: String,
    onValueChange: (String) -> Unit,
    fieldTag: String,
    last: Boolean,
    focusRequester: FocusRequester,
    onFocusChange: (Boolean) -> Unit,
    onImeAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    // iOS: the number 15 in, 20 wide, in Gilroy Bold 16 and the brand yellow; 3 pt; the field in
    // Gilroy Regular 18. Both centred 2 pt below the row's centre, as the storyboard has them.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .offset(y = 2.dp)
            .padding(start = 15.dp),
    ) {
        Text(
            text = "$wordNumber",
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 16.sp),
            color = colors.brandFixed,
            modifier = Modifier.width(20.dp),
        )
        Box(
            contentAlignment = Alignment.CenterStart,
            modifier = Modifier
                .weight(1f)
                .padding(start = 3.dp),
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
