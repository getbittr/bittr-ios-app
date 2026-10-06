package com.bittr.android.feature.send

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.BittrRowLabel
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.BittrSpinner
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.width
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.border
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrLoadingCard
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrHelpButton
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrBody
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
    val scope = rememberCoroutineScope()
    val controller = remember(source) { SendController(source, scope) }
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
            )
        } else {
            BittrAlert(
                title = alert.title,
                message = alert.message,
                buttons = alert.buttons.mapIndexed { position, button ->
                    BittrAlertButton(label = button.label, dismissesAlert = position == 0, onClick = { controller.onAlertButton(position) })
                },
                modifier = if (alert.tag != null) Modifier.testTag(alert.tag) else Modifier,
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
        val confirm = state.confirm
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
                horizontalAlignment = if (confirm == null) Alignment.CenterHorizontally else Alignment.Start,
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

@Composable
private fun ColumnScope.ConfirmPage(confirm: ConfirmState, controller: SendController) {
    Text(SendStrings.CHECK_DETAILS, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Gap()
    // Gold label on the left, the value on the right — every detail row's shape (review S15,
    // pass 3: these two had kept the stacked ink label).
    InfoBox {
        Row(verticalAlignment = Alignment.Top) {
            BittrRowLabel(if (confirm.mode == SendMode.Onchain) SendStrings.ADDRESS else SendStrings.INVOICE, modifier = Modifier.padding(end = 16.dp))
            Text(
                confirm.displayedAddress,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                textAlign = TextAlign.End,
                maxLines = 4,
                modifier = Modifier
                    .weight(1f)
                    .testTag(TestID.Send.Confirm.addressLabel),
            )
        }
    }
    Gap(BittrTokens.Spacing.sm)
    InfoBox {
        Row(verticalAlignment = Alignment.Top) {
            BittrRowLabel(SendStrings.AMOUNT, modifier = Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End) {
                Text(SendMath.formattedAmount(confirm.amountSats), style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.testTag(TestID.Send.Confirm.amountLabel))
                Text(
                    confirm.amountFiat.orEmpty(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.70f),
                    modifier = Modifier.testTag(TestID.Send.Confirm.amountFiatLabel),
                )
            }
        }
    }
    Gap(BittrTokens.Spacing.sm)

    if (confirm.mode == SendMode.Lightning) {
        InfoBox {
            Row(verticalAlignment = Alignment.CenterVertically) {
                BittrRowLabel(SendStrings.ESTIMATED_FEES, modifier = Modifier.weight(1f))
                QuestionMark(testTag = null, onClick = controller::onLightningFeesQuestion)
            }
            Text("1 - ${SendMath.group(confirm.lightningFeesSats ?: 0)} ${SendStrings.SATS}", style = MaterialTheme.typography.bodyLarge)
        }
    } else {
        Text(SendStrings.FEE_RATE, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(vertical = BittrTokens.Spacing.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
            FeeTile(confirm, FeeTier.High, SendStrings.TEN_MINS, TestID.Send.Confirm.feeFastButton, controller)
            FeeTile(confirm, FeeTier.Medium, SendStrings.ONE_HOUR, TestID.Send.Confirm.feeMediumButton, controller)
            FeeTile(confirm, FeeTier.Low, if (confirm.maxAvailableFeePerVb != null) SendStrings.SLOW else SendStrings.ONE_DAY, TestID.Send.Confirm.feeSlowButton, controller)
        }
    }

    Gap()
    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        // An ink square with `arrow_back`, as the lesson pages' Back is (review, pass 3).
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(BittrTheme.colors.actionFill)
                .clickable(role = Role.Button, onClick = controller::onBack),
        ) {
            Image(rememberFillIcon(BittrIconPaths.BACK, BittrTheme.colors.onActionFill), contentDescription = "Back", modifier = Modifier.size(24.dp))
        }
        PrimaryButton(SendStrings.SEND, loading = confirm.sending, testTag = TestID.Send.Confirm.confirmButton, modifier = Modifier.weight(1f), onClick = controller::onConfirm)
    }
}

@Composable
private fun RowScope.FeeTile(confirm: ConfirmState, tier: FeeTier, time: String, testTag: String, controller: SendController) {
    val selected = confirm.selectedFee == tier
    val fee = confirm.feeFor(tier)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .weight(1f)
            .background(
                if (selected) MaterialTheme.colorScheme.surfaceContainerLowest else BittrTheme.colors.tonalFill,
                RoundedCornerShape(12.dp),
            )
            // White against cream alone did not read as chosen (review S28, pass 4): the
            // selected rate also carries an ink edge, from the first frame as after a tap.
            .then(
                if (selected) {
                    Modifier.border(1.5.dp, MaterialTheme.colorScheme.onSurface, RoundedCornerShape(12.dp))
                } else {
                    Modifier
                },
            )
            .clickable { controller.onFee(tier) }
            .testTag(testTag)
            .padding(vertical = BittrTokens.Spacing.sm, horizontal = BittrTokens.Spacing.xs),
    ) {
        Text(time, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
        Text("$fee ${SendStrings.SATS}", style = MaterialTheme.typography.bodyMedium)
        Text(SendMath.formattedFiat(fee, confirm.pricePerBitcoin, confirm.fiatSymbol).orEmpty(), style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun InfoBox(content: @Composable ColumnScope.() -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xxs),
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, BittrCanvasShapes.field)
            .padding(16.dp),
        content = content,
    )
}

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

@Composable
private fun QuestionMark(testTag: String?, onClick: () -> Unit) {
    BittrHelpButton(
        onClick = onClick,
        modifier = if (testTag != null) Modifier.testTag(testTag) else Modifier,
    )
}

@Composable
private fun PrimaryButton(label: String, loading: Boolean, testTag: String, modifier: Modifier, onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(52.dp)
            .background(BittrTheme.colors.actionFill, RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .testTag(testTag),
    ) {
        if (loading) {
            BittrSpinner(strokeWidth = 2.dp, color = BittrTheme.colors.onActionFill, modifier = Modifier.size(20.dp))
        } else {
            Text(label, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.onActionFill)
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
