package com.bittr.android.feature.buy

import android.content.ContentValues
import android.graphics.Bitmap
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
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
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrCheckBadge
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTextButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** `RegisterIbanViewController` — the header, and whichever of the five pages is current. */
@Composable
internal fun SignupContainer(signup: SignupUiState, controller: BuyController, onOpenArticle: (String) -> Unit = {}) {
    val focus = LocalFocusManager.current
    BittrCanvas(modifier = Modifier.dismissOnPullDown(controller::onCloseSignup), appBar = false) {
        BittrModalHeader(
            title = BuyStrings.BUY_BITCOIN,
            onDown = controller::onCloseSignup,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .tapToClearFocus { focus.clearFocus() }
                .padding(BittrTokens.Spacing.md),
        ) {
            when (signup.page) {
                SignupPage.Ready -> ReadyPage(onNext = controller::onReadyNext, onOpenArticle = onOpenArticle)
                SignupPage.Start -> StartPage(signup, controller, onOpenArticle)
                SignupPage.Otp -> OtpPage(signup, controller)
                SignupPage.Success -> SuccessPage(controller)
                SignupPage.TransferInfo -> TransferInfoPage(controller)
            }
        }
    }
}

/** `Signup7ViewController` as Buy shows it: no badge, no "wallet is ready", no Skip. */
@Composable
private fun ReadyPage(onNext: () -> Unit, onOpenArticle: (String) -> Unit) {
    BittrCard {
        Text(
            BuyStrings.FIRST_BITCOIN,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        CanvasSpacer(BittrTokens.Spacing.xl)
        BittrPrimaryButton(
            text = BuyStrings.NEXT,
            onClick = onNext,
            modifier = Modifier.testTag(TestID.Signup.Create.Ready.continueButton),
        )
    }
    CanvasSpacer(BittrTokens.Spacing.lg)
    // `pageArticle1Slug = "what-is-bittr"`.
    ArticleCard(slug = BittrArticles.WHAT_IS_BITTR, onOpen = onOpenArticle)
}

/** `Transfer1ViewController`. */
@Composable
private fun StartPage(signup: SignupUiState, controller: BuyController, onOpenArticle: (String) -> Unit) {
    val focus = LocalFocusManager.current
    val ibanFocus = remember { FocusRequester() }
    val emailFocus = remember { FocusRequester() }
    // `triggerIbanAutoFocus`.
    LaunchedEffect(Unit) { runCatching { ibanFocus.requestFocus() } }
    val enabled = controller.canVerify(signup)

    BittrCard(horizontalAlignment = Alignment.Start) {
        Text(
            BuyStrings.BITTR_INSTRUCTIONS_4,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier
                .fillMaxWidth()
                .tapToClearFocus { focus.clearFocus() }
                .testTag(TestID.Signup.Bittr.Start.topLabelOne),
        )
        CanvasSpacer(BittrTokens.Spacing.lg)
        Text(
            BuyStrings.WHATS_YOUR_IBAN,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.testTag(TestID.Signup.Bittr.Start.topLabelTwo),
        )
        CanvasSpacer(BittrTokens.Spacing.sm)
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
        CanvasSpacer(BittrTokens.Spacing.lg)
        Text(
            BuyStrings.WHATS_YOUR_EMAIL,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.testTag(TestID.Signup.Bittr.Start.topLabelThree),
        )
        CanvasSpacer(BittrTokens.Spacing.sm)
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
        CanvasSpacer(BittrTokens.Spacing.xl)
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
        BittrTextButton(
            text = BuyStrings.NO_IBAN,
            onClick = {
                focus.clearFocus()
                controller.onSkip()
            },
            modifier = Modifier.testTag(TestID.Signup.Bittr.Start.skipButton),
        )
    }
    CanvasSpacer(BittrTokens.Spacing.lg)
    // Transfer1's `pageArticle1Slug = "supported-countries"`.
    ArticleCard(slug = BittrArticles.SUPPORTED_COUNTRIES, onOpen = onOpenArticle)
}

/** `Transfer2ViewController`. */
@Composable
private fun OtpPage(signup: SignupUiState, controller: BuyController) {
    val focus = LocalFocusManager.current
    val codeFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { codeFocus.requestFocus() } }

    BittrCard(horizontalAlignment = Alignment.Start) {
        Text(
            BuyStrings.YOUVE_GOT_MAIL,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier
                .fillMaxWidth()
                .tapToClearFocus { focus.clearFocus() }
                .testTag(TestID.Signup.Bittr.Otp.topLabel),
        )
        CanvasSpacer(BittrTokens.Spacing.lg)
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
        CanvasSpacer(BittrTokens.Spacing.xl)
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
    val clipboard = LocalClipboardManager.current
    val view = LocalView.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun copy(value: String) {
        clipboard.setText(AnnotatedString(value))
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
        BittrTextButton(
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
            modifier = Modifier.testTag(TestID.Signup.Bittr.Success.screenshotButton),
        )
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
            .padding(vertical = BittrTokens.Spacing.xs)
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
            .padding(BittrTokens.Spacing.md),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.testTag(titleTag))
        CanvasSpacer(BittrTokens.Spacing.xs)
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag(labelTag))
    }
}

/**
 * A field in iOS's shape: a rounded box that is itself the "button" (`ibanButton`,
 * `emailButton`, `codeButton` — the flows tap it to focus the field), with the text field inside.
 *
 * The box and the field are parent and child, not siblings, so both keep their ids: a sibling
 * layer covering the field would drop one of them from the accessibility tree.
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
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
            .pointerInput(Unit) { detectTapGestures { runCatching { focusRequester.requestFocus() } } }
            .testTag(buttonTag)
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        if (value.isEmpty()) {
            Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
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

/** The Next button with its activity indicator — iOS hides the label while busy. */
@Composable
private fun BusyButton(text: String, busy: Boolean, dimmed: Boolean, onClick: () -> Unit, tag: String) {
    Box(Modifier.fillMaxWidth()) {
        BittrPrimaryButton(
            text = if (busy) "" else text,
            onClick = { if (!busy) onClick() },
            arrow = !busy,
            modifier = Modifier
                .fillMaxWidth()
                // `nextView` at 60 % black until the fields are filled; still tappable, so
                // the "please fill in" alert is reachable.
                .then(if (dimmed) Modifier.alpha(0.6f) else Modifier)
                .testTag(tag),
        )
        if (busy) {
            CircularProgressIndicator(
                strokeWidth = 2.dp,
                color = BittrTheme.colors.onActionFill,
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
