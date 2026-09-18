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
import androidx.compose.foundation.layout.fillMaxHeight
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
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrHelpButton
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTextFieldAlert
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon

/**
 * Send — `SendViewController` with `ConfirmSendViewController` as its second page.
 *
 * As on Receive, "Done" is a button beside the amount field rather than a keyboard
 * toolbar: the flows tap it by its text, and a keyboard toolbar is not in an Android
 * app's view hierarchy. Labels that sit inside a tappable control carry their own test
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

    Box(modifier = modifier) {
    BittrCanvas(modifier = Modifier.dismissOnPullDown(onDown), appBar = false) {
        BittrModalHeader(
            title = SendStrings.SEND_BITCOIN,
            onDown = onDown,
            icon = BittrIconPaths.PIGGY,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            BittrCard(horizontalAlignment = Alignment.Start) {
                val confirm = state.confirm
                if (confirm == null) {
                    SendPage(
                        state = state,
                        controller = controller,
                        onScan = {
                            focusManager.clearFocus()
                            onOpenScanner()
                        },
                        clearFocus = { focusManager.clearFocus() },
                    )
                } else {
                    ConfirmPage(confirm, controller)
                }
            }
        }
    }
    if (state.lnurlLoading) LoadingCover(SendStrings.HANDLING_LNURL, TestID.Loading.handlingLnurl)
    }
}

/**
 * `showLoading(id:message:)`: a dim cover that swallows taps, and a card with a spinner and the
 * message. In the window rather than a dialog, so the screen underneath stays in Maestro's view.
 */
@Composable
private fun BoxScope.LoadingCover(message: String, testTag: String) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .matchParentSize()
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.4f))
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .background(BittrTheme.colors.dialogContainer, RoundedCornerShape(20.dp))
                .padding(BittrTokens.Spacing.lg)
                .testTag(testTag),
        ) {
            BittrSpinner(strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            Text(message, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}

@Composable
private fun ColumnScope.SendPage(
    state: SendUiState,
    controller: SendController,
    onScan: () -> Unit,
    clearFocus: () -> Unit,
) {
    val clipboard = rememberTextClipboard()
    val amountFocus = remember { FocusRequester() }
    var amountFocused by remember { mutableStateOf(false) }
    // A pay request with a range: `amountTextField.becomeFirstResponder()`.
    LaunchedEffect(state.focusAmountRequests) {
        if (state.focusAmountRequests > 0) amountFocus.requestFocus()
    }

    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        // One connected, single-select control — the proposal's segmented button — rather than
        // two detached chips (review, `send_lightning/02`).
        Row(
            modifier = Modifier
                .weight(1f)
                .height(48.dp)
                .clip(BittrCanvasShapes.pill)
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f), BittrCanvasShapes.pill),
        ) {
            ModeTile(SendStrings.REGULAR, selected = state.mode == SendMode.Onchain, bolt = false, testTag = TestID.Send.regularButton, modifier = Modifier.weight(1f)) {
                clearFocus()
                controller.onModeSelected(SendMode.Onchain)
            }
            Box(
                Modifier
                    .width(1.dp)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)),
            )
            ModeTile(SendStrings.INSTANT, selected = state.mode == SendMode.Lightning, bolt = true, testTag = null, modifier = Modifier.weight(1f)) {
                clearFocus()
                controller.onModeSelected(SendMode.Lightning)
            }
        }
        QuestionMark(TestID.Send.switchQuestionButton) {
            clearFocus()
            controller.onSwitchQuestion()
        }
    }

    Gap()
    Text(state.toLabel, style = MaterialTheme.typography.titleMedium, color = BittrTheme.colors.emphasis, modifier = Modifier.testTag(TestID.Send.toLabel))
    Gap(BittrTokens.Spacing.xs)
    // The two ways in first, then the field they fill — the proposal's order (review, pass 2,
    // `send_swap_suggestion_*/02`).
    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
        ActionTile(SendStrings.SCAN, SCAN_PATH, TestID.Send.scanButton, Modifier.weight(1f), onScan)
        ActionTile(SendStrings.PASTE, PASTE_PATH, TestID.Send.pasteButton, Modifier.weight(1f)) {
            clearFocus()
            clipboard.paste(controller::onPaste)
        }
    }
    Gap(BittrTokens.Spacing.sm)
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

    Gap()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Entry(
            value = state.amountText,
            placeholder = SendStrings.ENTER_AMOUNT,
            onValueChange = controller::onAmountChange,
            keyboardType = if (state.currency == AmountCurrency.Satoshis) KeyboardType.Number else KeyboardType.Decimal,
            imeAction = ImeAction.Done,
            onIme = {
                clearFocus()
                controller.onNext()
            },
            testTag = TestID.Send.amountTextField,
            modifier = Modifier
                .weight(1f)
                .focusRequester(amountFocus)
                .onFocusChanged { amountFocused = it.hasFocus },
            // Field and unit are one control: the field's right corners and the chip's left
            // ones are square, and nothing sits between them (review, pass 3).
            shape = RoundedCornerShape(topStart = 16.dp, bottomStart = 16.dp),
        )
        OverlaidTile(
            TestID.Send.currencyButton,
            onClick = {
                clearFocus()
                controller.onCurrencyButton()
            },
            shape = RoundedCornerShape(topEnd = 16.dp, bottomEnd = 16.dp),
        ) {
            Text(state.currencyLabel, style = MaterialTheme.typography.labelLarge, modifier = Modifier.testTag(TestID.Send.currencyLabel))
        }
        // The keyboard's companion, so only there while the amount is being typed: with the
        // keyboard down it competed with the screen's own Next (review, `send_lightning/02`).
        if (amountFocused) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .padding(start = BittrTokens.Spacing.sm)
                    .height(56.dp)
                    .clip(BittrCanvasShapes.pill)
                    .background(BittrTheme.colors.actionFill)
                    .clickable {
                        clearFocus()
                        controller.onNext()
                    }
                    .padding(horizontal = BittrTokens.Spacing.lg),
            ) {
                Text(SendStrings.DONE, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.onActionFill)
            }
        }
    }

    Gap(BittrTokens.Spacing.sm)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(modifier = Modifier.weight(1f, fill = false)) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable {
                        clearFocus()
                        controller.onAvailableTapped()
                    }
                    .testTag(TestID.Send.availableButton),
            )
            Text(state.available, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag(TestID.Send.availableLabel))
        }
        if (state.availableLoading) {
            BittrSpinner(
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .padding(start = BittrTokens.Spacing.xs)
                    .size(16.dp)
                    .testTag(TestID.Send.bdkSpinner),
            )
        }
        QuestionMark(TestID.Send.availableQuestionButton) {
            clearFocus()
            controller.onAvailableQuestion()
        }
    }

    Gap()
    PrimaryButton(SendStrings.NEXT, loading = state.nextLoading, testTag = TestID.Send.nextButton, modifier = Modifier.fillMaxWidth()) {
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
                RoundedCornerShape(8.dp),
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

/** One segment of the payment-mode selector: white with a leading glyph when selected, cream when not. */
@Composable
private fun ModeTile(label: String, selected: Boolean, bolt: Boolean, testTag: String?, modifier: Modifier, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .fillMaxHeight()
            .background(if (selected) MaterialTheme.colorScheme.surfaceContainer else BittrTheme.colors.tonalFill)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        // The lightning segment always shows its bolt; the selected segment leads with a check
        // otherwise, as Material's segmented button does.
        val glyph = when {
            bolt -> BittrIconPaths.BOLT
            selected -> BittrIconPaths.CHECK
            else -> null
        }
        if (glyph != null) {
            Image(
                rememberStrokeIcon(glyph, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier
                    .padding(end = 6.dp)
                    .size(18.dp),
            )
        }
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun ActionTile(label: String, path: String, testTag: String, modifier: Modifier, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        modifier = modifier
            .height(44.dp)
            .background(BittrTheme.colors.tonalFill, RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .testTag(testTag),
    ) {
        Image(rememberStrokeIcon(path, BittrTheme.colors.onTonalFill, strokeWidth = 2f), contentDescription = null, modifier = Modifier.size(18.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.onTonalFill)
    }
}

@Composable
private fun OverlaidTile(
    testTag: String,
    onClick: () -> Unit,
    shape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(8.dp),
    content: @Composable () -> Unit,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .height(56.dp)
            .background(BittrTheme.colors.tonalFill, shape)
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        // Under the content, not over it: a node a later sibling covers entirely is dropped
        // from the accessibility tree, which would hide the label's own test id.
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable(onClick = onClick)
                .testTag(testTag),
        )
        content()
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
    shape: androidx.compose.ui.graphics.Shape = BittrCanvasShapes.field,
    ellipsizeWhenIdle: Boolean = false,
) {
    val colors = BittrTheme.colors
    var focused by remember { mutableStateOf(false) }
    // Not being edited, a long address or invoice shows its two ends on one line rather than
    // clipping mid-string at the field's edge (review, pass 3). The field underneath keeps the
    // whole value, and its test id, for editing and for the flows.
    val idleText = ellipsizeWhenIdle && !focused && value.isNotEmpty()
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = modifier
            .height(56.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, shape)
            .onFocusChanged { focused = it.hasFocus }
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        if (idleText) {
            Text(
                value,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
                modifier = Modifier.clearAndSetSemantics {},
            )
        }
        if (value.isEmpty()) {
            Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(
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

private const val SCAN_PATH = "M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4M4 12h16"
private const val PASTE_PATH = "M9 4h6v3H9zM7 5H5v15h14V5h-2"
