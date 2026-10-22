package com.bittr.android.feature.send

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import com.bittr.android.core.designsystem.rememberRetained
import com.bittr.android.core.designsystem.MiddleEllipsisText
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.BittrSpinner
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.width
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrLoadingCard
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTextFieldAlert
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.R as DesignR
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.ui.unit.IntOffset

/**
 * Send — `SendViewController` with `ConfirmSendViewController` as its second page.
 *
 * iOS's keyboard-toolbar Done is the keyboard's own ✓ here, which closes the keyboard and goes
 * on to Next as `doneButtonTapped` does; the flows press Enter for it
 * (`helpers/amount_done.yaml`). Labels that sit inside a tappable control carry their own test
 * id, so the tap target is a transparent layer over them rather than their parent —
 * a clickable parent would merge the label's id away.
 *
 * @param scanned what the scanner handed back, consumed once it has been applied.
 * @param lnurlRequest an LNURL handed over from outside Send (the in-app browser), handled
 *   once when the screen opens.
 */
@Composable
fun SendRoute(
    source: SendSource,
    onDown: () -> Unit,
    onOpenScanner: () -> Unit,
    onOpenTransaction: (String) -> Unit,
    onOpenLightningQuestion: () -> Unit,
    scanned: Destination?,
    onScannedConsumed: () -> Unit,
    modifier: Modifier = Modifier,
    onSwapAndPayInvoice: (invoice: String, amountSats: Long) -> Unit = { _, _ -> },
    onSwapAndPayAddress: (address: String, amountSats: Long) -> Unit = { _, _ -> },
    lnurlRequest: SendLnurlRequest? = null,
) {
    // Kept on the sheet's back-stack entry, not this composition — see [rememberRetained].
    val controller = rememberRetained("send") { scope -> SendController(source, scope) }
    val openTransaction by rememberUpdatedState(onOpenTransaction)
    val openQuestion by rememberUpdatedState(onOpenLightningQuestion)
    val swapInvoice by rememberUpdatedState(onSwapAndPayInvoice)
    val swapAddress by rememberUpdatedState(onSwapAndPayAddress)

    LaunchedEffect(controller) {
        controller.start()
        controller.effects.collect { effect ->
            when (effect) {
                is SendEffect.OpenTransaction -> openTransaction(effect.id)
                SendEffect.OpenLightningQuestion -> openQuestion()
                is SendEffect.SwapAndPayInvoice -> swapInvoice(effect.invoice, effect.amountSats)
                is SendEffect.SwapAndPayAddress -> swapAddress(effect.address, effect.amountSats)
            }
        }
    }
    LaunchedEffect(scanned) {
        if (scanned != null) {
            controller.onDestination(scanned)
            onScannedConsumed()
        }
    }
    LaunchedEffect(lnurlRequest) {
        if (lnurlRequest != null) controller.onLnurl(lnurlRequest.raw, lnurlRequest.source)
    }

    val state by controller.state.collectAsState()
    SendScreen(state, controller, onDown, onOpenScanner, modifier)
}

@Composable
internal fun SendScreen(
    state: SendUiState,
    controller: SendController,
    onDown: () -> Unit,
    onOpenScanner: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusManager = LocalFocusManager.current

    state.alert?.let { alert ->
        val field = alert.field
        if (field != null && alert.buttons.size == 2) {
            BittrTextFieldAlert(
                title = alert.title,
                message = alert.message,
                initialText = "",
                placeholder = field.placeholder,
                cancelLabel = alert.buttons[0].label,
                saveLabel = alert.buttons[1].label,
                onCancel = { controller.onAlertButton(0) },
                onSave = { text -> controller.onAlertText(1, text) },
                testTag = alert.tag,
                keyboardType = KeyboardType.Number,
                identity = alert,
            )
        } else {
            BittrAlert(
                title = alert.title,
                message = alert.message,
                buttons = alert.buttons.mapIndexed { position, button ->
                    BittrAlertButton(label = button.label, dismissesAlert = position == 0, onClick = { controller.onAlertButton(position) })
                },
                modifier = if (alert.tag != null) Modifier.testTag(alert.tag) else Modifier,
                identity = alert,
            )
        }
    }

    // `addHeader` with the piggy over a block centred in the whole sheet, as `SendViewController`
    // lays it out: Scan and Paste, and 25 under them `yellowCard`, 15 in, `yelloworblue2` with 13
    // corners and the iOS shadow. A tap beside the fields closes the keyboard (`backgroundButton`).
    Box(modifier = modifier) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown)
            .imePadding()
            .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } },
    ) {
        val sheetHeight = maxHeight
        // `SendToConfirm`: the confirm page slides in from the right as the send page leaves to the
        // left, and back again, over 0.3 s ease-in-out. Keyed on which page shows, so a fee change on
        // the confirm page updates it in place rather than sliding.
        AnimatedContent(
            targetState = state.confirm,
            contentKey = { it != null },
            transitionSpec = {
                val forward = targetState != null
                val spec = tween<IntOffset>(durationMillis = 300, easing = FastOutSlowInEasing)
                slideInHorizontally(spec) { width -> if (forward) width else -width } togetherWith
                    slideOutHorizontally(spec) { width -> if (forward) -width else width }
            },
            label = "sendConfirmSlide",
            modifier = Modifier.fillMaxSize(),
        ) { confirm ->
            Column(
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = sheetHeight)
                    .padding(vertical = 58.dp),
            ) {
                if (confirm == null) {
                    ScanAndPaste(
                        onScan = {
                            focusManager.clearFocus()
                            onOpenScanner()
                        },
                        onPaste = { focusManager.clearFocus() },
                        controller = controller,
                    )
                    Gap(25.dp)
                }
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .padding(horizontal = 15.dp)
                        .fillMaxWidth()
                        .iosShadow(YellowCardShape)
                        .background(BittrTheme.colors.levelCard, YellowCardShape)
                        .padding(start = 20.dp, end = 20.dp, top = 30.dp, bottom = if (confirm == null) 30.dp else 20.dp),
                ) {
                    if (confirm == null) {
                        SendPage(
                            state = state,
                            controller = controller,
                            clearFocus = { focusManager.clearFocus() },
                        )
                    } else {
                        ConfirmPage(confirm, controller)
                    }
                }
            }
        }

        BittrSheetHeader(
            icon = painterResource(DesignR.drawable.bittr_piggy_icon),
            title = SendStrings.SEND_BITCOIN,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
    if (state.lnurlLoading) LoadingCover(SendStrings.HANDLING_LNURL, TestID.Loading.handlingLnurl)
    }
}

/** `showLoading(id:message:)`: the shared loading card, over the screen. */
@Composable
private fun BoxScope.LoadingCover(message: String, testTag: String) {
    Box(Modifier.matchParentSize()) {
        BittrLoadingCard(message = message, testTag = testTag)
    }
}

/**
 * `Buttons Stack`: Scan and Paste, two 70 pt `whiteorblue3` squares 10 apart with 8 corners and
 * the iOS shadow. The labels share one line, 43 from the top; above them `qrcode` (22 × 19) and
 * `clipboard` (20 × 23) sit where the storyboard draws them, 17.7 and 13.7 from the top, so the
 * taller clipboard rises rather than pushing its label down.
 */
@Composable
private fun ScanAndPaste(onScan: () -> Unit, onPaste: () -> Unit, controller: SendController) {
    val clipboard = rememberTextClipboard()
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SquareButton(SendStrings.SCAN, SCAN_PATH, iconWidth = 22.dp, iconHeight = 19.dp, iconTop = 17.67.dp, testTag = TestID.Send.scanButton, onClick = onScan)
        SquareButton(SendStrings.PASTE, PASTE_PATH, iconWidth = 20.dp, iconHeight = 23.dp, iconTop = 13.67.dp, testTag = TestID.Send.pasteButton) {
            onPaste()
            clipboard.paste(controller::onPaste)
        }
    }
}

@Composable
private fun SquareButton(
    label: String,
    path: String,
    iconWidth: Dp,
    iconHeight: Dp,
    iconTop: Dp,
    testTag: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(70.dp)
            .iosShadow(PlateShape)
            .clip(PlateShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onClick)
            .testTag(testTag),
    ) {
        Image(
            rememberStrokeIcon(path, MaterialTheme.colorScheme.onSurface, strokeWidth = 1.6f),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = iconTop)
                .size(width = iconWidth, height = iconHeight),
        )
        Text(
            label,
            style = Bold14,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 43.dp),
        )
    }
}

/**
 * The card's content: the Regular / Instant switch with its question mark, `toLabel` 25 under
 * it, the address and the amount fields (45 tall, 10 apart, the text centred), what can be sent
 * with its question mark, and Next — as the storyboard spaces them.
 */
@Composable
private fun ColumnScope.SendPage(
    state: SendUiState,
    controller: SendController,
    clearFocus: () -> Unit,
) {
    val amountFocus = remember { FocusRequester() }
    // A pay request with a range: `amountTextField.becomeFirstResponder()`.
    LaunchedEffect(state.focusAmountRequests) {
        if (state.focusAmountRequests > 0) amountFocus.requestFocus()
    }

    // `Switch Stack` centred on the card, `switchQuestionMark` 10 after it. The 40 on the left
    // balances the question mark's 40 target on the right, so the switch itself is centred.
    Row(verticalAlignment = Alignment.CenterVertically) {
        Spacer(Modifier.width(40.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(7.5.dp)) {
            ModeTile(SendStrings.REGULAR, selected = state.mode == SendMode.Onchain, bolt = false, testTag = TestID.Send.regularButton) {
                clearFocus()
                controller.onModeSelected(SendMode.Onchain)
            }
            ModeTile(SendStrings.INSTANT, selected = state.mode == SendMode.Lightning, bolt = true, testTag = null) {
                clearFocus()
                controller.onModeSelected(SendMode.Lightning)
            }
        }
        SmallQuestion(TestID.Send.switchQuestionButton, Modifier.offset(x = (-2).dp)) {
            clearFocus()
            controller.onSwitchQuestion()
        }
    }

    Gap(25.dp)
    Text(
        state.toLabel,
        style = MaterialTheme.typography.labelLarge.copy(lineHeight = 16.sp),
        color = BittrTheme.colors.emphasis,
        textAlign = TextAlign.Center,
        modifier = Modifier.testTag(TestID.Send.toLabel),
    )
    Gap(12.dp)
    Entry(
        value = state.toText,
        placeholder = state.toPlaceholder,
        onValueChange = controller::onToChange,
        keyboardType = KeyboardType.Uri,
        imeAction = ImeAction.Next,
        onIme = { if (controller.onToReturn()) amountFocus.requestFocus() else clearFocus() },
        testTag = TestID.Send.toTextField,
        modifier = Modifier.fillMaxWidth(),
        ellipsizeWhenIdle = true,
    )

    Gap(10.dp)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Entry(
            value = state.amountText,
            placeholder = SendStrings.ENTER_AMOUNT,
            onValueChange = controller::onAmountChange,
            // Whole satoshis take digits only. `Number` is not that: Gboard and Samsung's keyboard
            // still offer `,` `.` and `-` on it. `NumberPassword` is the digit-only pad, and a
            // BasicTextField has no visual transformation, so nothing is masked. Bitcoin and
            // fiat amounts keep the decimal separator.
            keyboardType = if (state.currency == AmountCurrency.Satoshis) KeyboardType.NumberPassword else KeyboardType.Decimal,
            imeAction = ImeAction.Done,
            onIme = {
                clearFocus()
                controller.onNext()
            },
            testTag = TestID.Send.amountTextField,
            // The keyboard's ✓ is iOS's toolbar Done (`doneButtonTapped`): it closes the
            // keyboard and goes on to Next.
            modifier = Modifier
                .weight(1f)
                .focusRequester(amountFocus),
        )
        // `btcView`: 45 square, `whiteorblue3` with the iOS shadow.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .height(FieldHeight)
                .widthIn(min = FieldHeight)
                .iosShadow(PlateShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape),
        ) {
            // Under the label, not over it: a node a later sibling covers entirely is dropped
            // from the accessibility tree, which would hide the label's own test id.
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(PlateShape)
                    .clickable {
                        clearFocus()
                        controller.onCurrencyButton()
                    }
                    .testTag(TestID.Send.currencyButton),
            )
            Text(
                state.currencyLabel,
                style = Bold14,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .padding(horizontal = 6.dp)
                    .offset(y = 1.dp)
                    .testTag(TestID.Send.currencyLabel),
            )
        }
    }

    // `Available Stack`: 2 under the amount, 40 tall, the line centred with its question mark 5
    // after it and `bdkSpinner` 8 after that.
    Gap(2.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.height(40.dp),
    ) {
        Box {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable {
                        clearFocus()
                        controller.onAvailableTapped()
                    }
                    .testTag(TestID.Send.availableButton),
            )
            Text(
                state.available,
                style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier.testTag(TestID.Send.availableLabel),
            )
        }
        Box(contentAlignment = Alignment.CenterStart) {
            SmallQuestion(TestID.Send.availableQuestionButton, Modifier.offset(x = (-7).dp)) {
                clearFocus()
                controller.onAvailableQuestion()
            }
            if (state.availableLoading) {
                BittrSpinner(
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .padding(start = 29.dp)
                        .size(16.dp)
                        .testTag(TestID.Send.bdkSpinner),
                )
            }
        }
    }

    Gap(16.dp)
    NextButton(loading = state.nextLoading) {
        clearFocus()
        controller.onNext()
    }
}

/**
 * `ConfirmSendViewController`'s card, as its scene is: the heading in Gilroy-Regular 16 30 from the
 * top and 40 in; 15 under it and 20 in, the address and amount rows (`whiteorblue3`, 8 corners), 10
 * apart — the title in yellow Gilroy-Bold 16 and the value right-aligned in Bold 16, the amount's fiat
 * under it in Regular 15. Then Lightning's estimated-fees row, or 30 under the rows the fee rate's line
 * and its three tiles; the back and Send buttons 35 under those, centred, 20 from the bottom.
 */
@Composable
private fun ColumnScope.ConfirmPage(confirm: ConfirmState, controller: SendController) {
    val ink = MaterialTheme.colorScheme.onSurface
    Text(
        SendStrings.CHECK_DETAILS,
        style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.4.sp),
        color = ink,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
    )
    Gap(15.dp)
    ConfirmRow(if (confirm.mode == SendMode.Onchain) SendStrings.ADDRESS else SendStrings.INVOICE) {
        // Truncated in the middle, as iOS's `addressLabel` is, so the end can be checked.
        MiddleEllipsisText(
            confirm.displayedAddress,
            style = ConfirmValue,
            color = ink,
            textAlign = TextAlign.End,
            maxLines = 4,
            modifier = Modifier.testTag(TestID.Send.Confirm.addressLabel),
        )
    }
    Gap(10.dp)
    ConfirmRow(SendStrings.AMOUNT) {
        Column(horizontalAlignment = Alignment.End) {
            Text(
                SendMath.formattedAmount(confirm.amountSats),
                style = ConfirmValue,
                color = ink,
                modifier = Modifier.testTag(TestID.Send.Confirm.amountLabel),
            )
            Text(
                confirm.amountFiat.orEmpty(),
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 15.sp),
                color = ink,
                modifier = Modifier
                    .padding(top = 4.dp)
                    .testTag(TestID.Send.Confirm.amountFiatLabel),
            )
        }
    }

    if (confirm.mode == SendMode.Lightning) {
        // `lightningFeesView`: 10 under the amount, the estimate and its question mark 8 after it.
        Gap(10.dp)
        ConfirmRow(SendStrings.ESTIMATED_FEES) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("1 - ${SendMath.group(confirm.lightningFeesSats ?: 0)} ${SendStrings.SATS}", style = ConfirmValue, color = ink)
                Image(
                    rememberFillIcon(BittrIconPaths.HELP, ink),
                    contentDescription = "More information",
                    modifier = Modifier
                        .padding(start = 8.dp)
                        .offset(y = (-1).dp)
                        .size(16.dp)
                        .clip(CircleShape)
                        .clickable(role = Role.Button, onClick = controller::onLightningFeesQuestion),
                )
            }
        }
    } else {
        Gap(30.dp)
        Text(
            SendStrings.FEE_RATE,
            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
            color = ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Gap(15.dp)
        // `feesView`: three tiles, each 30 % of the row's width, the middle one centred.
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val tile = maxWidth * 0.3f
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                FeeTile(confirm, FeeTier.High, SendStrings.TEN_MINS, TestID.Send.Confirm.feeFastButton, controller, Modifier.width(tile))
                FeeTile(confirm, FeeTier.Medium, SendStrings.ONE_HOUR, TestID.Send.Confirm.feeMediumButton, controller, Modifier.width(tile))
                FeeTile(
                    confirm,
                    FeeTier.Low,
                    if (confirm.maxAvailableFeePerVb != null) SendStrings.SLOW else SendStrings.ONE_DAY,
                    TestID.Send.Confirm.feeSlowButton,
                    controller,
                    Modifier.width(tile),
                )
            }
        }
    }

    Gap(35.dp)
    // `backView` and `confirmView`: 40 tall and black with 8 corners, 7 apart — the left arrow in a
    // 40 square, and "Send" in Gilroy-Bold 14 17 in, the spinner in its place while it sends.
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(40.dp)
                .clip(PlateShape)
                .background(BittrTheme.colors.actionFill)
                .clickable(role = Role.Button, onClickLabel = "Back", onClick = controller::onBack),
        ) {
            Image(
                painter = painterResource(DesignR.drawable.bittr_arrow_right),
                contentDescription = "Back",
                colorFilter = ColorFilter.tint(BittrTheme.colors.onActionFill),
                modifier = Modifier
                    .size(11.dp)
                    .graphicsLayer { scaleX = -1f },
            )
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .height(40.dp)
                .clip(PlateShape)
                .background(BittrTheme.colors.actionFill)
                .clickable(role = Role.Button, onClick = controller::onConfirm)
                .testTag(TestID.Send.Confirm.confirmButton)
                .padding(horizontal = 17.dp),
        ) {
            Text(
                SendStrings.SEND,
                style = Bold14,
                color = BittrTheme.colors.onActionFill,
                modifier = Modifier
                    .offset(y = 1.dp)
                    .alpha(if (confirm.sending) 0f else 1f),
            )
            if (confirm.sending) {
                BittrSpinner(strokeWidth = 2.dp, color = BittrTheme.colors.onActionFill, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/**
 * One fee rate: 30 % of the row and 75 tall, 8 corners and the iOS shadow; `whiteorblue3` when chosen
 * and `white0.7orblue1` otherwise. The time in Gilroy-Bold 14 (`blackoryellow`) 14 from the top, the
 * fee and its fiat in Regular 13 under it, 5 apart, all centred.
 */
@Composable
private fun FeeTile(
    confirm: ConfirmState,
    tier: FeeTier,
    time: String,
    testTag: String,
    controller: SendController,
    modifier: Modifier = Modifier,
) {
    val selected = confirm.selectedFee == tier
    val fee = confirm.feeFor(tier)
    val small = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp, lineHeight = 13.sp)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .height(75.dp)
            .iosShadow(PlateShape)
            .clip(PlateShape)
            .background(if (selected) MaterialTheme.colorScheme.surfaceContainerHigh else BittrTheme.colors.scrim1)
            .clickable { controller.onFee(tier) }
            .testTag(testTag)
            .padding(top = 14.dp, start = 4.dp, end = 4.dp),
    ) {
        Text(time, style = Bold14, color = BittrTheme.colors.emphasis, maxLines = 1)
        Text("$fee ${SendStrings.SATS}", style = small, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, modifier = Modifier.padding(top = 5.dp))
        Text(
            SendMath.formattedFiat(fee, confirm.pricePerBitcoin, confirm.fiatSymbol).orEmpty(),
            style = small,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            modifier = Modifier.padding(top = 5.dp),
        )
    }
}

/**
 * A confirm row: `whiteorblue3` with 8 corners, at least 45 tall; the title in yellow Gilroy-Bold 16
 * 15 in and centred on the row, the value at the end 15 after it, 12 from the top and 9 from the bottom.
 */
@Composable
private fun ConfirmRow(title: String, value: @Composable () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 45.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape)
            .padding(start = 15.dp, end = 15.dp, top = 12.dp, bottom = 9.dp),
    ) {
        Text(title, style = ConfirmValue, color = BittrTheme.colors.brandFixed, modifier = Modifier.offset(y = 1.dp))
        Box(
            contentAlignment = Alignment.CenterEnd,
            modifier = Modifier
                .weight(1f)
                .padding(start = 15.dp),
        ) { value() }
    }
}

/** The confirm rows' titles and values: Gilroy-Bold 16. */
private val ConfirmValue: TextStyle
    @Composable get() = MaterialTheme.typography.labelLarge.copy(lineHeight = 18.sp)

/**
 * One half of `Switch Stack`: 40 tall with 8 corners, `whiteorblue3` with a faint shadow when
 * chosen and `white0.7orblue1` when not; the Gilroy-Bold 14 label 20 from either end, and on
 * Instant the 12 pt `bolt.fill` 16 in with the label 4 after it.
 */
@Composable
private fun ModeTile(label: String, selected: Boolean, bolt: Boolean, testTag: String?, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .height(40.dp)
            .then(if (selected) Modifier.iosShadow(PlateShape) else Modifier)
            .clip(PlateShape)
            .background(if (selected) MaterialTheme.colorScheme.surfaceContainerHigh else colors.scrim1)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
            .padding(start = if (bolt) 16.dp else 20.dp, end = 20.dp),
    ) {
        if (bolt) {
            Image(
                rememberFillIcon(BittrIconPaths.BOLT, MaterialTheme.colorScheme.onSurface),
                contentDescription = null,
                modifier = Modifier
                    .padding(end = 4.dp)
                    .size(13.dp),
            )
        }
        Text(label, style = Bold14, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.offset(y = 1.dp))
    }
}

/** `questionmark.circle`, 16 pt in black or white, in a 40 pt target. */
@Composable
private fun SmallQuestion(testTag: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(testTag),
    ) {
        Image(
            rememberFillIcon(BittrIconPaths.HELP, MaterialTheme.colorScheme.onSurface),
            contentDescription = "More information",
            modifier = Modifier.size(16.dp),
        )
    }
}

/**
 * `nextView`: 40 tall and black with 8 corners, "Next" in Gilroy-Bold 14 17 in and the 11 pt
 * white arrow 10 after it and 17 from the end; the spinner in its place while it works.
 */
@Composable
private fun NextButton(loading: Boolean, onClick: () -> Unit) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .height(40.dp)
            .clip(PlateShape)
            .background(colors.actionFill)
            .clickable(onClick = onClick)
            .testTag(TestID.Send.nextButton),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .padding(horizontal = 17.dp)
                .alpha(if (loading) 0f else 1f),
        ) {
            Text(SendStrings.NEXT, style = Bold14, color = colors.onActionFill, modifier = Modifier.offset(y = 1.dp))
            // iOS's own `arrowrightwhite`, tinted so it follows the label in dark mode too.
            Image(
                painter = painterResource(DesignR.drawable.bittr_arrow_right),
                contentDescription = null,
                colorFilter = ColorFilter.tint(colors.onActionFill),
                modifier = Modifier
                    .padding(start = 10.dp)
                    .size(11.dp),
            )
        }
        if (loading) {
            BittrSpinner(strokeWidth = 2.dp, color = colors.onActionFill, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * `toView` / `amountView`: 45 tall, `white0.7orblue1` with 8 corners, Gilroy-Regular 16 centred
 * 15 from either end.
 */
@Composable
private fun Entry(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    keyboardType: KeyboardType,
    imeAction: ImeAction,
    onIme: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
    ellipsizeWhenIdle: Boolean = false,
) {
    val colors = BittrTheme.colors
    var focused by remember { mutableStateOf(false) }
    // Not being edited, a long address or invoice shows its two ends on one line rather than
    // clipping mid-string at the field's edge (review, pass 3). The field underneath keeps the
    // whole value, and its test id, for editing and for the flows.
    val idleText = ellipsizeWhenIdle && !focused && value.isNotEmpty()
    val style = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(FieldHeight)
            .background(colors.scrim1, PlateShape)
            .onFocusChanged { focused = it.hasFocus }
            .padding(horizontal = 15.dp),
    ) {
        if (idleText) {
            Text(
                value,
                style = style,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
                modifier = Modifier
                    .fillMaxWidth()
                    .clearAndSetSemantics {},
            )
        }
        if (value.isEmpty()) {
            Text(
                placeholder,
                style = style,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = style.copy(
                color = if (idleText) Color.Transparent else MaterialTheme.colorScheme.onSurface,
            ),
            cursorBrush = SolidColor(colors.onTonalFill),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction, autoCorrectEnabled = false),
            keyboardActions = KeyboardActions(onNext = { onIme() }, onDone = { onIme() }),
            modifier = Modifier
                .fillMaxWidth()
                .testTag(testTag),
        )
    }
}

@Composable
private fun Gap(height: androidx.compose.ui.unit.Dp = BittrTokens.Spacing.md) =
    androidx.compose.foundation.layout.Spacer(Modifier.height(height))

private val YellowCardShape = RoundedCornerShape(13.dp)
private val PlateShape = RoundedCornerShape(8.dp)
private val FieldHeight = 45.dp
private val Bold14 @Composable get() = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp)

/** SF Symbols' `qrcode`: three finder squares and the scattered modules, drawn on a 24 grid. */
private const val SCAN_PATH =
    "M3.5 3.5h7v7h-7z M13.5 3.5h7v7h-7z M3.5 13.5h7v7h-7z M6.5 6.5h1v1h-1z M16.5 6.5h1v1h-1z M6.5 16.5h1v1h-1z " +
        "M14 14h2 M19 14h1.5 M14 17.5v3 M17.5 17.5h3v3"
/** SF Symbols' `clipboard`: the board with its clip on top. */
private const val PASTE_PATH = "M8 4.5H6.5a2 2 0 00-2 2v13a2 2 0 002 2h11a2 2 0 002-2v-13a2 2 0 00-2-2H16 M8.5 3h7v3h-7z"
