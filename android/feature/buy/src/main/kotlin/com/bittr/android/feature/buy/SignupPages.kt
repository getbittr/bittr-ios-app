package com.bittr.android.feature.buy

import android.content.ContentValues
import android.graphics.Bitmap
import android.os.Build
import android.provider.MediaStore
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.text.TextStyle
import com.bittr.android.core.designsystem.appBarContentPadding
import com.bittr.android.core.designsystem.pageSlide
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.drawToBitmap
import com.bittr.android.core.common.TestID
import com.bittr.android.feature.academy.ArticleCard
import com.bittr.android.feature.academy.BittrArticles
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrPartnerRow
import com.bittr.android.core.designsystem.BittrPartnerRowWidth
import androidx.compose.foundation.layout.height
import com.bittr.android.core.designsystem.BittrTonalButton
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrSheetHeader
import androidx.compose.ui.res.painterResource
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The five bittr signup pages and what they sit in. They slide between one another as the
 * wallet's signup pages do (`moveToPage`), [SignupPage]'s order being their place in the strip.
 *
 * Two hosts, as on iOS. In the Buy section they are `RegisterIbanViewController`'s pages 0–4,
 * under its "buy bitcoin" header, and pull down to close. In onboarding ([onboarding]) they are
 * `SignupViewController`'s pages 10–13 after Signup7: under the logo top bar, which stays put as
 * the pages slide beneath it, and with no header or pull-down.
 *
 * Every page is laid out as the storyboards have them: `centerCard` 15 from the screen edges and
 * the article card 30 under it, centred together 40 above the middle.
 */
@Composable
internal fun SignupContainer(
    signup: SignupUiState,
    controller: BuyController,
    onOpenArticle: (String) -> Unit = {},
    onboarding: Boolean = false,
) {
    val focus = LocalFocusManager.current
    val pages: @Composable (Modifier) -> Unit = { modifier ->
        AnimatedContent(
            targetState = signup.page,
            transitionSpec = { pageSlide(initialState.ordinal, targetState.ordinal) },
            label = "bittrSignupPages",
            modifier = modifier,
        ) { page ->
            Column(
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxSize()
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .tapToClearFocus { focus.clearFocus() }
                    .then(
                        if (onboarding) {
                            Modifier
                                .appBarContentPadding()
                                .padding(start = 15.dp, end = 15.dp, bottom = 80.dp)
                        } else {
                            // Over Buy the pages fill the whole sheet under the header, and iOS
                            // centres them in it: clear of the header by as much at the bottom.
                            Modifier.padding(horizontal = 15.dp, vertical = SheetHeaderHeight)
                        },
                    ),
            ) {
                when (page) {
                    SignupPage.Ready -> ReadyPage(onNext = controller::onReadyNext, onOpenArticle = onOpenArticle)
                    SignupPage.Start -> StartPage(signup, controller, onOpenArticle)
                    SignupPage.Otp -> OtpPage(signup, controller)
                    SignupPage.Success -> SuccessPage(controller)
                    SignupPage.TransferInfo -> TransferInfoPage(controller)
                }
            }
        }
    }

    if (onboarding) {
        BittrCanvas(appBar = true, scrollsUnderAppBar = true) {
            pages(Modifier.weight(1f).fillMaxWidth())
        }
    } else {
        // `RegisterIbanViewController`: `addHeader` with the piggy, over the pages.
        Box(
            Modifier
                .fillMaxSize()
                .background(BittrTheme.colors.canvas)
                .dismissOnPullDown(controller::onCloseSignup),
        ) {
            pages(Modifier.fillMaxSize())
            BittrSheetHeader(
                icon = painterResource(R.drawable.buy_header_piggy),
                title = BuyStrings.BUY_BITCOIN,
                onDown = controller::onCloseSignup,
                titleTestTag = TestID.Header.titleLabel,
                downTestTag = TestID.Header.downButton,
            )
        }
    }
}

/** `addHeader`'s 58 pt band. */
private val SheetHeaderHeight = 58.dp

/**
 * `Signup7ViewController` as Buy shows it (`viewWillAppear` with an `ibanVC`): the badge, "wallet
 * is ready" and Skip go transparent but keep their room, and the line, now Gilroy-Bold 16, moves
 * up 76 into the badge's. That leaves it about 39 under the card's top, the partner row 40 under
 * it, Next 10 under that, and Skip's 10 + 25 + 20 of empty card below Next. The line's 16.4 pitch
 * is off the iOS screenshot.
 */
@Composable
private fun ReadyPage(onNext: () -> Unit, onOpenArticle: (String) -> Unit) {
    BittrCard(contentPadding = PaddingValues(start = 25.dp, end = 25.dp, top = 39.dp, bottom = 55.dp)) {
        Text(
            BuyStrings.FIRST_BITCOIN,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 16.4.sp),
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        CanvasSpacer(40.dp)
        BittrPartnerRow()
        CanvasSpacer(10.dp)
        // `continueView`: as wide as the partner row, as on Signup7.
        BittrPrimaryButton(
            text = BuyStrings.NEXT,
            onClick = onNext,
            modifier = Modifier
                .width(BittrPartnerRowWidth)
                .testTag(TestID.Signup.Create.Ready.continueButton),
        )
    }
    CanvasSpacer(30.dp)
    // `pageArticle1Slug = "what-is-bittr"`.
    ArticleCard(slug = BittrArticles.WHAT_IS_BITTR, onOpen = onOpenArticle)
}

/**
 * `Transfer1ViewController`, as its scene is: in the card, 30 from its top and 25 from its sides,
 * the line in Gilroy Regular 16; 30 below, the IBAN question in Gilroy Bold 16 and its field 10
 * under it; 30 below, the email question and its field; Verify 30 below, "I don't have an IBAN"
 * under it, and 25 of card under that row. Every label centred.
 */
@Composable
private fun StartPage(signup: SignupUiState, controller: BuyController, onOpenArticle: (String) -> Unit) {
    val focus = LocalFocusManager.current
    val ibanFocus = remember { FocusRequester() }
    val emailFocus = remember { FocusRequester() }
    // `triggerIbanAutoFocus`.
    LaunchedEffect(Unit) { runCatching { ibanFocus.requestFocus() } }
    val enabled = controller.canVerify(signup)

    // The skip row's 25 pt sits 25 above the card's bottom on iOS; its 48 dp touch target spends
    // 11.5 of that.
    BittrCard(contentPadding = PaddingValues(start = 25.dp, end = 25.dp, top = 30.dp, bottom = 13.dp)) {
        Text(
            BuyStrings.BITTR_INSTRUCTIONS_4,
            style = CardBody,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .tapToClearFocus { focus.clearFocus() }
                .testTag(TestID.Signup.Bittr.Start.topLabelOne),
        )
        CanvasSpacer(30.dp)
        Text(
            BuyStrings.WHATS_YOUR_IBAN,
            style = CardQuestion,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Bittr.Start.topLabelTwo),
        )
        CanvasSpacer(10.dp)
        BuyField(
            value = signup.iban,
            onValueChange = controller::onIbanChange,
            placeholder = BuyStrings.ENTER_IBAN,
            focusRequester = ibanFocus,
            buttonTag = TestID.Signup.Bittr.Start.ibanButton,
            fieldTag = TestID.Signup.Bittr.Start.ibanTextField,
            keyboard = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Next,
            ),
            onImeAction = { emailFocus.requestFocus() },
        )
        CanvasSpacer(30.dp)
        Text(
            BuyStrings.WHATS_YOUR_EMAIL,
            style = CardQuestion,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Bittr.Start.topLabelThree),
        )
        CanvasSpacer(10.dp)
        BuyField(
            value = signup.email,
            onValueChange = controller::onEmailChange,
            placeholder = BuyStrings.ENTER_EMAIL,
            focusRequester = emailFocus,
            buttonTag = TestID.Signup.Bittr.Start.emailButton,
            fieldTag = TestID.Signup.Bittr.Start.emailTextField,
            keyboard = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Done,
            ),
            // `textFieldShouldReturn`: Return on the email field verifies when the button is live.
            onImeAction = {
                if (controller.canVerify(signup)) {
                    focus.clearFocus()
                    controller.onVerify()
                }
            },
        )
        CanvasSpacer(30.dp)
        BusyButton(
            text = BuyStrings.VERIFY,
            busy = signup.busy,
            dimmed = !enabled,
            onClick = {
                focus.clearFocus()
                controller.onVerify()
            },
            tag = TestID.Signup.Bittr.Start.nextButton,
        )
        // iOS leaves 10 pt and a 25 pt row; the 48 dp touch target spends the 10.
        BittrTextButton(
            text = BuyStrings.NO_IBAN,
            onClick = {
                focus.clearFocus()
                controller.onSkip()
            },
            modifier = Modifier.testTag(TestID.Signup.Bittr.Start.skipButton),
        )
    }
    CanvasSpacer(30.dp)
    // Transfer1's `pageArticle1Slug = "supported-countries"`.
    ArticleCard(slug = BittrArticles.SUPPORTED_COUNTRIES, onOpen = onOpenArticle)
}

/** The Transfer pages' explanatory lines: Gilroy Regular 16. */
private val CardBody: TextStyle
    @Composable get() = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 20.sp)

/** The Transfer pages' questions over their fields: Gilroy Bold 16. */
private val CardQuestion: TextStyle
    @Composable get() = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 20.sp)

/**
 * `Transfer2ViewController`, as its scene is: in the card, 30 from its top and 40 from its sides,
 * the line in Gilroy Bold 16, centred; the code field 30 below; Confirm 30 below that, "Resend
 * code" under it, and 25 of card under that row.
 */
@Composable
private fun OtpPage(signup: SignupUiState, controller: BuyController) {
    val focus = LocalFocusManager.current
    val codeFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { codeFocus.requestFocus() } }

    // The resend row's 25 pt sits 25 above the card's bottom on iOS; its 48 dp touch target spends
    // 11.5 of that.
    BittrCard(contentPadding = PaddingValues(start = 40.dp, end = 40.dp, top = 30.dp, bottom = 13.dp)) {
        Text(
            BuyStrings.YOUVE_GOT_MAIL,
            style = CardQuestion,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .tapToClearFocus { focus.clearFocus() }
                .testTag(TestID.Signup.Bittr.Otp.topLabel),
        )
        CanvasSpacer(30.dp)
        BuyField(
            value = signup.code,
            onValueChange = controller::onCodeChange,
            placeholder = BuyStrings.ENTER_CODE,
            focusRequester = codeFocus,
            buttonTag = TestID.Signup.Bittr.Otp.codeButton,
            fieldTag = TestID.Signup.Bittr.Otp.codeTextField,
            keyboard = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            onImeAction = {
                focus.clearFocus()
                controller.onConfirmCode()
            },
        )
        CanvasSpacer(30.dp)
        BusyButton(
            text = BuyStrings.CONFIRM,
            busy = signup.busy,
            dimmed = signup.code.trim().length <= 5,
            onClick = {
                focus.clearFocus()
                controller.onConfirmCode()
            },
            tag = TestID.Signup.Bittr.Otp.nextButton,
        )
        // iOS leaves 10 pt and a 25 pt row; the 48 dp touch target spends the 10.
        BittrTextButton(
            text = BuyStrings.RESEND_CODE,
            onClick = {
                focus.clearFocus()
                controller.onResendCode()
            },
            modifier = Modifier.testTag(TestID.Signup.Bittr.Otp.resendButton),
        )
    }
}

/** `Transfer3ViewController`. */
@Composable
private fun SuccessPage(controller: BuyController) {
    val entity = controller.signupEntity()
    val clipboard = rememberTextClipboard()
    val view = LocalView.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun copy(value: String) {
        clipboard.copy(value)
        controller.showCopied(value)
    }

    BittrCard {
        BittrCheckBadge()
        CanvasSpacer(BittrTokens.Spacing.lg)
        Text(
            BuyStrings.READY_FOR_TRANSFER,
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Signup.Bittr.Success.topLabelOne),
        )
        CanvasSpacer(BittrTokens.Spacing.sm)
        BittrBody(BuyStrings.PERSONAL_DETAILS, modifier = Modifier.testTag(TestID.Signup.Bittr.Success.topLabelTwo))
        CanvasSpacer(BittrTokens.Spacing.lg)
        val ourIban = entity?.ourIbanNumber.orEmpty()
        val ourName = entity?.ourName.orEmpty()
        val code = entity?.yourUniqueCode.orEmpty()
        DetailRow(
            BuyStrings.OUR_IBAN, ourIban,
            valueTag = TestID.Signup.Bittr.Success.ourIbanLabel,
            onCopy = { copy(ourIban) }, copyTag = TestID.Signup.Bittr.Success.ibanButton,
        )
        DetailRow(
            BuyStrings.OUR_NAME, ourName,
            onCopy = { copy(ourName) }, copyTag = TestID.Signup.Bittr.Success.nameButton,
        )
        DetailRow(
            BuyStrings.YOUR_CODE, code,
            valueTag = TestID.Signup.Bittr.Success.yourCodeLabel,
            onCopy = { copy(code) }, copyTag = TestID.Signup.Bittr.Success.codeButton,
        )
        CanvasSpacer(BittrTokens.Spacing.lg)
        // A tonal button directly above Finish, not a text link (review, `bittr_success`).
        BittrTonalButton(
            text = BuyStrings.SCREENSHOT,
            onClick = {
                scope.launch {
                    val saved = runCatching {
                        val bitmap = view.rootView.drawToBitmap()
                        withContext(Dispatchers.IO) { saveToPictures(context, bitmap) }
                    }.getOrDefault(false)
                    controller.onScreenshotResult(saved)
                }
            },
            modifier = Modifier
                .height(52.dp)
                .testTag(TestID.Signup.Bittr.Success.screenshotButton),
        )
        CanvasSpacer(12.dp)
        BittrPrimaryButton(
            text = BuyStrings.FINAL_DETAILS,
            onClick = controller::onSuccessNext,
            modifier = Modifier.testTag(TestID.Signup.Bittr.Success.nextButton),
        )
    }
}

/** `Transfer4ViewController`. */
@Composable
private fun TransferInfoPage(controller: BuyController) {
    BittrCard {
        InfoCard(
            BuyStrings.TRANSFER_3_AMOUNT, BuyStrings.TRANSFER_3_AMOUNT_LABEL,
            TestID.Signup.Bittr.TransferInfo.amountTitle, TestID.Signup.Bittr.TransferInfo.amountLabel,
        )
        InfoCard(
            BuyStrings.TRANSFER_3_LIGHTNING, BuyStrings.TRANSFER_3_LIGHTNING_LABEL,
            TestID.Signup.Bittr.TransferInfo.lightningTitle, TestID.Signup.Bittr.TransferInfo.lightningLabel,
        )
        InfoCard(
            BuyStrings.TRANSFER_3_CONNECTION, BuyStrings.TRANSFER_3_CONNECTION_LABEL,
            TestID.Signup.Bittr.TransferInfo.connectionTitle, TestID.Signup.Bittr.TransferInfo.connectionLabel,
        )
        InfoCard(
            BuyStrings.TRANSFER_3_DCA, BuyStrings.TRANSFER_3_DCA_LABEL,
            TestID.Signup.Bittr.TransferInfo.dcaTitle, TestID.Signup.Bittr.TransferInfo.dcaLabel,
        )
        CanvasSpacer(BittrTokens.Spacing.lg)
        BittrPrimaryButton(
            text = BuyStrings.LETS_GO,
            onClick = controller::onLetsGo,
            modifier = Modifier.testTag(TestID.Signup.Bittr.TransferInfo.nextButton),
        )
        BittrTextButton(
            text = BuyStrings.BACK,
            onClick = controller::onTransferInfoBack,
            modifier = Modifier.testTag(TestID.Signup.Bittr.TransferInfo.backButton),
        )
    }
}

@Composable
private fun InfoCard(title: String, label: String, titleTag: String, labelTag: String) {
    Column(
        modifier = Modifier
            .padding(vertical = 4.dp)
            .fillMaxWidth()
            // White, 20 dp, as a card inside a sheet is in the proposal (review S1).
            .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(20.dp))
            .padding(16.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 17.sp),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.testTag(titleTag),
        )
        CanvasSpacer(BittrTokens.Spacing.xs)
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 22.sp),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.testTag(labelTag),
        )
    }
}

/**
 * A field in iOS's shape: a rounded box that is itself the "button" (`ibanButton`,
 * `emailButton`, `codeButton` — the flows tap it to focus the field), with the text field inside.
 *
 * The box and the field are parent and child, not siblings, so both keep their ids: a sibling
 * layer covering the field would drop one of them from the accessibility tree.
 *
 * iOS's `ibanView` / `emailView` / `codeView`: white in both schemes, 260 by 45 with 8 pt
 * corners, the text field 15 in from each side, in Gilroy Regular 16, black and centred.
 */
@Composable
private fun BuyField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    focusRequester: FocusRequester,
    buttonTag: String,
    fieldTag: String,
    keyboard: KeyboardOptions,
    onImeAction: () -> Unit,
) {
    val colors = BittrTheme.colors
    val textStyle = CardBody.copy(textAlign = TextAlign.Center)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(width = 260.dp, height = 45.dp)
            .background(colors.phraseCard, BuyFieldShape)
            .pointerInput(Unit) { detectTapGestures { runCatching { focusRequester.requestFocus() } } }
            .testTag(buttonTag)
            .padding(horizontal = 15.dp),
    ) {
        if (value.isEmpty()) {
            Text(
                placeholder,
                style = textStyle,
                color = colors.phrasePlaceholder,
                maxLines = 1,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = textStyle.copy(color = colors.onPhraseCard),
            cursorBrush = SolidColor(colors.onPhraseCard),
            keyboardOptions = keyboard,
            keyboardActions = KeyboardActions(onAny = { onImeAction() }),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester)
                // A hardware Enter — Maestro's `pressKey: Enter` — does what Return does.
                .onPreviewKeyEvent { event ->
                    if (event.key == Key.Enter && event.type == KeyEventType.KeyUp) {
                        onImeAction()
                        true
                    } else {
                        event.key == Key.Enter
                    }
                }
                .testTag(fieldTag),
        )
    }
}

private val BuyFieldShape = RoundedCornerShape(8.dp)

/** The Next button with its activity indicator — iOS hides the label while busy. */
@Composable
private fun BusyButton(text: String, busy: Boolean, dimmed: Boolean, onClick: () -> Unit, tag: String) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxWidth()) {
        BittrPrimaryButton(
            text = if (busy) "" else text,
            onClick = { if (!busy) onClick() },
            arrow = !busy,
            // Dimmed until the fields are filled, as iOS's `nextView` is, but still
            // tappable, so the "please fill in" alert is reachable.
            dimmed = dimmed,
            modifier = Modifier.testTag(tag),
        )
        if (busy) {
            BittrSpinner(
                strokeWidth = 2.dp,
                color = if (dimmed) BittrTheme.colors.onActionFillDisabled else BittrTheme.colors.onActionFill,
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(22.dp),
            )
        }
    }
}

/** Save [bitmap] to Pictures — the Android counterpart of `UIImageWriteToSavedPhotosAlbum`. */
private fun saveToPictures(context: android.content.Context, bitmap: Bitmap): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "bittr-${System.currentTimeMillis()}.png")
        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/bittr")
    }
    val resolver = context.contentResolver
    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
    return resolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } ?: false
}
