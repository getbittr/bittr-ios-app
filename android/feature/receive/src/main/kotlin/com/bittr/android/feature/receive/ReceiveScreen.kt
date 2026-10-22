package com.bittr.android.feature.receive

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bittr.android.core.designsystem.rememberRetained
import com.bittr.android.core.designsystem.MiddleEllipsisText
import com.bittr.android.core.designsystem.GroupsOfFourText
import androidx.compose.ui.text.font.FontFamily
import com.bittr.android.core.designsystem.rememberFillIcon
import androidx.compose.ui.graphics.Color
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrMark
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.R as DesignR

/**
 * Receive — `ios/bittr/Move, Send, Receive/ReceiveVC/ReceiveViewController`.
 *
 * The QR in a white box, the address box under it, a row of cards (copy, renew, add amount,
 * more) and, when opened, the amount stack. Behaviour lives in [ReceiveController]; this
 * draws its state and forwards taps.
 *
 * Two things differ from iOS because the platform does:
 *
 * - **"Done" is the keyboard's ✓.** iOS puts a Done button on a toolbar above the keyboard;
 *   Android keyboards carry the action key themselves, and the fields answer it the same way.
 *   It is not in the app's hierarchy, so the flows press Enter for it (`helpers/amount_done.yaml`).
 * - **The QR's long-press menu is a dropdown**, with the same two items — Copy and Share —
 *   and Share opens the system share sheet with the copyable text.
 */
@Composable
fun ReceiveRoute(source: ReceiveSource, onDown: () -> Unit, modifier: Modifier = Modifier) {
    // Kept on the sheet's back-stack entry, not this composition — see [rememberRetained].
    val controller = rememberRetained("receive") { scope -> ReceiveController(source, scope) }
    LaunchedEffect(controller) { controller.start() }
    val state by controller.state.collectAsState()
    ReceiveScreen(state = state, controller = controller, onDown = onDown, modifier = modifier)
}

@Composable
internal fun ReceiveScreen(
    state: ReceiveUiState,
    controller: ReceiveController,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val clipboard = rememberTextClipboard()
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current

    fun copy() {
        controller.onCopy()?.let(clipboard::copy)
    }

    fun share() {
        val text = state.display?.copyText ?: return
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    state.alert?.let { alert ->
        BittrAlert(
            title = alert.title,
            message = alert.message,
            messageIsValue = alert.messageIsValue,
            identity = alert,
            buttons = alert.buttons.mapIndexed { position, button ->
                BittrAlertButton(
                    label = button.label,
                    dismissesAlert = position == 0,
                    onClick = { controller.onAlertButton(position) },
                )
            },
        )
    }

    // As `ReceiveViewController` lays it out: `addHeader` with the piggy over `yellowCard`, centred
    // in the whole sheet, 15 in, `yelloworblue2` with 13 corners and the iOS shadow. Inside it, 15
    // in, the QR, the address 15 under it, the cards 14 under that and, when opened, the amount
    // stack 14 under those. A tap beside the fields closes the keyboard (`contentBackgroundButton`).
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown)
            // Before the scroll, so the visible area ends at the keyboard.
            .imePadding()
            .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } },
    ) {
        val sheetHeight = maxHeight
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = sheetHeight)
                .padding(vertical = 58.dp),
        ) {
            Column(
                modifier = Modifier
                    .padding(horizontal = 15.dp)
                    .fillMaxWidth()
                    .iosShadow(YellowCardShape)
                    .background(BittrTheme.colors.levelCard, YellowCardShape)
                    .padding(15.dp),
            ) {
                QrBox(
                    payload = state.display?.qrPayload,
                    loading = state.loading,
                    onCopy = ::copy,
                    onShare = ::share,
                )
                Spacer(15.dp)
                AddressBox(state = state, onQuestion = controller::onQuestion)
                Spacer(14.dp)
                CardsRow(
                    cards = state.cards,
                    onCopy = ::copy,
                    onRefresh = {
                        focusManager.clearFocus()
                        controller.onRefresh()
                    },
                    onEdit = {
                        focusManager.clearFocus()
                        controller.onEdit()
                    },
                    onMore = {
                        focusManager.clearFocus()
                        controller.onMore()
                    },
                )
                if (state.amountOpen) {
                    Spacer(14.dp)
                    AmountStack(
                        state = state,
                        onAmountChange = controller::onAmountChange,
                        onDescriptionChange = controller::onDescriptionChange,
                        onCurrency = {
                            focusManager.clearFocus()
                            controller.onCurrencyButton()
                        },
                        onDone = {
                            focusManager.clearFocus()
                            controller.onDone()
                        },
                    )
                }
            }
        }

        BittrSheetHeader(
            icon = painterResource(DesignR.drawable.bittr_piggy_icon),
            title = ReceiveStrings.RECEIVE_BITCOIN,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun QrBox(payload: String?, loading: Boolean, onCopy: () -> Unit, onShare: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    val code by produceState<Pair<QrCode, ImageBitmap>?>(initialValue = null, payload) {
        value = payload?.let { withContext(Dispatchers.Default) { qrCode(it).let { code -> code to code.bitmap.asImageBitmap() } } }
    }

    // `qrWhiteView`: square, white in both schemes (a QR reads dark on light), 8 corners and the
    // iOS shadow, the code 15 in.
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .iosShadow(PlateShape)
            .background(Color.White, PlateShape)
            .padding(15.dp),
    ) {
        val shown = code
        if (!loading && shown != null) {
            val (qr, bitmap) = shown
            Box {
                Image(
                    bitmap = bitmap,
                    contentDescription = "QR code",
                    modifier = Modifier
                        .fillMaxSize()
                        .combinedClickable(onClick = {}, onLongClick = { menuOpen = true })
                        .testTag(TestID.Receive.qrImageView),
                )
                // The bittr mark at the centre, in a square white box of whole modules as iOS draws it.
                // The box covers about 2 % of the modules, well inside what level H (30 %) recovers.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .fillMaxSize(qr.logoBox)
                        .background(Color.White),
                ) {
                    BittrMark(
                        ink = Color.Black,
                        arc = BittrTheme.colors.brandFixed,
                        modifier = Modifier.fillMaxSize(qr.logoMark),
                    )
                }
                // The dialog's cream, 16 dp and a glyph per item, rather than Material's bare
                // white list (review, `receive_onchain/03a`).
                DropdownMenu(
                    expanded = menuOpen,
                    onDismissRequest = { menuOpen = false },
                    shape = RoundedCornerShape(16.dp),
                    containerColor = BittrTheme.colors.dialogContainer,
                    tonalElevation = 0.dp,
                    shadowElevation = 2.dp,
                ) {
                    val ink = BittrTheme.colors.onDialogContainer
                    DropdownMenuItem(
                        text = { Text(ReceiveStrings.MENU_COPY, style = MaterialTheme.typography.labelLarge, color = ink) },
                        leadingIcon = {
                            Image(rememberFillIcon(BittrIconPaths.COPY, ink), contentDescription = null, modifier = Modifier.size(20.dp))
                        },
                        onClick = {
                            menuOpen = false
                            onCopy()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(ReceiveStrings.MENU_SHARE, style = MaterialTheme.typography.labelLarge, color = ink) },
                        leadingIcon = {
                            Image(rememberFillIcon(SHARE_PATH, ink), contentDescription = null, modifier = Modifier.size(20.dp))
                        },
                        onClick = {
                            menuOpen = false
                            onShare()
                        },
                    )
                }
            }
        }
        if (loading) {
            BittrSpinner(
                color = BittrTheme.colors.emphasis,
                modifier = Modifier.testTag(TestID.Receive.qrSpinner),
            )
        }
    }
}

/**
 * `addressView`: `whiteorblue3` with 8 corners and the iOS shadow, at least 45 tall. The title in
 * yellow Gilroy-Bold 16 15 in — after the 14 pt bolt for Lightning — with `questionmark.circle` 7
 * after it. Under it, for every type, the label in black or white: an address or invoice
 * monospaced in groups of four, an invoice shortened to three lines between whole groups.
 * `questionButton` is the title and its question mark, as on iOS.
 */
@Composable
private fun AddressBox(state: ReceiveUiState, onQuestion: () -> Unit) {
    val display = state.display
    val colors = BittrTheme.colors
    val style = MaterialTheme.typography.labelLarge.copy(lineHeight = 18.sp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 45.dp)
            .iosShadow(PlateShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape)
            .padding(start = 15.dp, end = 15.dp, top = 15.dp, bottom = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, modifier = Modifier.fillMaxWidth()) {
            Box {
                // Under the title, not over it: a node a later sibling covers entirely is dropped
                // from the accessibility tree, which would hide the title's own test id.
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clickable(role = Role.Button, onClick = onQuestion)
                        .testTag(TestID.Receive.questionButton),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (display?.showBolt == true && !state.loading) {
                        Image(
                            imageVector = rememberFillIcon(BittrIconPaths.BOLT, colors.brandFixed),
                            contentDescription = null,
                            modifier = Modifier
                                .padding(end = 5.dp)
                                .size(14.dp),
                        )
                    }
                    Text(
                        text = if (state.loading) "" else display?.title.orEmpty(),
                        style = style,
                        color = colors.brandFixed,
                        modifier = Modifier.testTag(TestID.Receive.addressTitle),
                    )
                    if (!state.loading) {
                        Image(
                            imageVector = rememberFillIcon(BittrIconPaths.HELP, colors.brandFixed),
                            contentDescription = "More information",
                            modifier = Modifier
                                .padding(start = 7.dp)
                                .offset(y = (-1).dp)
                                .size(16.dp),
                        )
                    }
                }
            }
        }
        val label = if (state.loading) "" else display?.label.orEmpty()
        if (label.isNotEmpty()) {
            val labelModifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp)
                .testTag(TestID.Receive.addressLabel)
            when {
                // An invoice is shortened between whole groups, as iOS shortens only invoices.
                display?.monospaced == true && state.type == ReceiveType.Lightning -> GroupsOfFourText(
                    text = label,
                    readAs = display.copyText,
                    style = style.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    modifier = labelModifier,
                )
                // An address wraps between groups and, as iOS's label does, gives way in the middle only when three lines are not enough.
                display?.monospaced == true -> MiddleEllipsisText(
                    text = label,
                    readAs = display.copyText,
                    style = style.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    modifier = labelModifier,
                )
                // A Lightning address is read aloud and typed, so it is never elided (review, pass 2,
                // `receive/02`): it wraps, breaking before the `@` rather than inside the domain. The
                // zero-width space is display only — the copy action reads the model.
                '@' in label -> Text(
                    text = label.replace("@", "\u200B@"),
                    style = style,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = labelModifier,
                )
                // `lowerAddressLabel`: three lines, truncated in the middle, so the end can be checked.
                else -> MiddleEllipsisText(
                    text = label,
                    style = style,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    modifier = labelModifier,
                )
            }
        }
    }
}

/**
 * `cardsStack`, sized as `updateCards(for:)` sizes it: 12 apart across the card's width, 35 tall.
 * On the address Copy is a 35 square with its icon alone; elsewhere it is labelled. Around the
 * even share, Add amount takes 22 more, and Copy, Renew and More give up 10, 10 and 12 — Renew 22
 * when there is no More — so the row still fills the width exactly.
 */
@Composable
private fun CardsRow(
    cards: ReceiveCards,
    onCopy: () -> Unit,
    onRefresh: () -> Unit,
    onEdit: () -> Unit,
    onMore: () -> Unit,
) {
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val gap = 12.dp
        val count = listOf(true, cards.refresh, cards.edit, cards.more).count { it }
        val share = if (cards.copyLabel) {
            (maxWidth - gap * (count - 1)) / count
        } else {
            (maxWidth - CardHeight - gap * (count - 1)) / (count - 1)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            ReceiveCard(
                label = if (cards.copyLabel) ReceiveStrings.COPY else null,
                symbol = CardSymbol.Copy,
                contentDescription = ReceiveStrings.COPY,
                onClick = onCopy,
                testTag = TestID.Receive.copyButton,
                modifier = Modifier.width(
                    when {
                        !cards.copyLabel -> CardHeight
                        cards.edit -> share - 10.dp
                        else -> share
                    },
                ),
            )
            if (cards.refresh) {
                ReceiveCard(
                    label = ReceiveStrings.RENEW,
                    symbol = CardSymbol.Renew,
                    contentDescription = ReceiveStrings.RENEW,
                    onClick = onRefresh,
                    testTag = TestID.Receive.refreshButton,
                    modifier = Modifier.width(if (cards.more) share - 10.dp else share - 22.dp),
                )
            }
            if (cards.edit) {
                ReceiveCard(
                    label = ReceiveStrings.ADD_AMOUNT,
                    symbol = CardSymbol.Edit,
                    contentDescription = ReceiveStrings.ADD_AMOUNT,
                    onClick = onEdit,
                    testTag = TestID.Receive.editButton,
                    modifier = Modifier.width(share + 22.dp),
                )
            }
            if (cards.more) {
                ReceiveCard(
                    label = ReceiveStrings.MORE,
                    symbol = CardSymbol.More,
                    contentDescription = ReceiveStrings.MORE,
                    onClick = onMore,
                    testTag = TestID.Receive.moreButton,
                    modifier = Modifier.width(if (cards.edit) share - 12.dp else share),
                )
            }
        }
    }
}

/**
 * One card: `white0.7orblue3` with 8 corners and the iOS shadow, its SF-style symbol and the
 * Gilroy-Bold 14 label 6 after it, centred. A label that does not fit — a narrow phone at a large
 * font scale — is dropped rather than cut, and the symbol carries the name for TalkBack.
 */
@Composable
private fun ReceiveCard(
    label: String?,
    symbol: CardSymbol,
    contentDescription: String,
    onClick: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    val ink = MaterialTheme.colorScheme.onSurface
    var labelFits by remember(label) { mutableStateOf(true) }
    val showLabel = label != null && labelFits
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .height(CardHeight)
            .iosShadow(PlateShape)
            .clip(PlateShape)
            .background(colors.scrim3)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(testTag)
            .padding(horizontal = 6.dp),
    ) {
        CardIcon(symbol, ink, contentDescription = if (showLabel) null else contentDescription)
        if (label != null && labelFits) {
            Text(
                label,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp),
                color = ink,
                maxLines = 1,
                softWrap = false,
                onTextLayout = { if (it.hasVisualOverflow) labelFits = false },
                modifier = Modifier
                    .padding(start = 6.dp)
                    .offset(y = 1.dp),
            )
        }
    }
}

private enum class CardSymbol { Copy, Renew, Edit, More }

/**
 * The cards' SF Symbols, drawn on a 16 pt square: `doc.on.doc.fill`,
 * `arrow.counterclockwise.circle.fill`, `pencil.line` and `arrowtriangle.down.circle.fill`. The
 * filled ones have their arrow, gap or triangle cut out, so the card shows through as on iOS.
 */
@Composable
private fun CardIcon(symbol: CardSymbol, color: Color, contentDescription: String?) {
    Canvas(
        modifier = Modifier
            .size(16.dp)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier),
    ) {
        val u = size.width / 16f
        val center = Offset(8f * u, 8f * u)
        when (symbol) {
            CardSymbol.Copy -> {
                // The back page, a 1 pt gap round the front page, and the front page.
                drawRoundRect(color, Offset(5.5f * u, 0f), Size(8.5f * u, 11.5f * u), CornerRadius(2f * u))
                drawRoundRect(Color.Black, Offset(1f * u, 3.5f * u), Size(10.5f * u, 12.5f * u), CornerRadius(2.8f * u), blendMode = BlendMode.Clear)
                drawRoundRect(color, Offset(2f * u, 4.5f * u), Size(8.5f * u, 11.5f * u), CornerRadius(2f * u))
            }
            CardSymbol.Renew -> {
                drawCircle(color, radius = 7f * u, center = center)
                // The arc, open at the upper left, and its head at the top pointing back along it.
                drawArc(
                    Color.Black,
                    startAngle = -70f,
                    sweepAngle = 280f,
                    useCenter = false,
                    topLeft = Offset(4.3f * u, 4.3f * u),
                    size = Size(7.4f * u, 7.4f * u),
                    style = Stroke(width = 1.5f * u, cap = StrokeCap.Round),
                    blendMode = BlendMode.Clear,
                )
                val head = Path().apply {
                    moveTo(6f * u, 4.6f * u)
                    lineTo(8.6f * u, 2.6f * u)
                    lineTo(8.6f * u, 6.6f * u)
                    close()
                }
                drawPath(head, Color.Black, blendMode = BlendMode.Clear)
            }
            CardSymbol.Edit -> {
                val stroke = Stroke(width = 1.3f * u, cap = StrokeCap.Round, join = StrokeJoin.Round)
                val pencil = Path().apply {
                    moveTo(2.5f * u, 13.5f * u)
                    lineTo(3f * u, 10.5f * u)
                    lineTo(10.8f * u, 2.7f * u)
                    lineTo(13.3f * u, 5.2f * u)
                    lineTo(5.5f * u, 13f * u)
                    close()
                    moveTo(9.3f * u, 4.2f * u)
                    lineTo(11.8f * u, 6.7f * u)
                }
                drawPath(pencil, color, style = stroke)
                drawLine(color, Offset(8.5f * u, 15f * u), Offset(14.5f * u, 15f * u), strokeWidth = 1.3f * u, cap = StrokeCap.Round)
            }
            CardSymbol.More -> {
                drawCircle(color, radius = 7f * u, center = center)
                val triangle = Path().apply {
                    moveTo(4.9f * u, 6.4f * u)
                    lineTo(11.1f * u, 6.4f * u)
                    lineTo(8f * u, 10.6f * u)
                    close()
                }
                drawPath(triangle, Color.Black, blendMode = BlendMode.Clear)
            }
        }
    }
}

/**
 * `amountStack`: the amount field and, 10 after it, `btcView` — a 45 square in `whiteorblue3` with
 * the iOS shadow; for an invoice or a Bitcoin QR the description field 10 under them. Both fields
 * are 45 tall, `white0.7orblue1` with 8 corners and their text centred.
 */
@Composable
private fun AmountStack(
    state: ReceiveUiState,
    onAmountChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onCurrency: () -> Unit,
    onDone: () -> Unit,
) {
    // The keyboard's ✓ is iOS's toolbar Done on both fields: it commits the amount and note.
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            EntryField(
                value = state.amountText,
                placeholder = ReceiveStrings.ENTER_AMOUNT,
                onValueChange = onAmountChange,
                // Digits only for satoshis: `Number` still offers `,` `.` and `-` on Gboard and
                // Samsung's keyboard; `NumberPassword` is the digit pad, unmasked in a BasicTextField.
                keyboardType = if (state.currency == ReceiveCurrency.Satoshis) KeyboardType.NumberPassword else KeyboardType.Decimal,
                onDone = onDone,
                testTag = TestID.Receive.amountTextField,
                modifier = Modifier.weight(1f),
            )
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(FieldHeight)
                    .widthIn(min = FieldHeight)
                    .iosShadow(PlateShape)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape),
            ) {
                // Under the label, not over it, so the label keeps its own test id.
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clip(PlateShape)
                        .clickable(onClick = onCurrency)
                        .testTag(TestID.Receive.currencyButton),
                )
                Text(
                    text = state.currencyLabel,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp),
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .padding(horizontal = 6.dp)
                        .offset(y = 1.dp)
                        .testTag(TestID.Receive.currencyLabel),
                )
            }
        }
        if (state.showsDescription) {
            EntryField(
                value = state.descriptionText,
                placeholder = ReceiveStrings.ADD_A_NOTE,
                onValueChange = onDescriptionChange,
                keyboardType = KeyboardType.Text,
                onDone = onDone,
                testTag = null,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun EntryField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    keyboardType: KeyboardType,
    onDone: () -> Unit,
    testTag: String?,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    val style = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(FieldHeight)
            .background(colors.scrim1, PlateShape)
            .padding(horizontal = 15.dp),
    ) {
        if (value.isEmpty()) {
            Text(
                placeholder,
                style = style,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = style.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(colors.onTonalFill),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onDone() }),
            modifier = Modifier
                .fillMaxWidth()
                .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
        )
    }
}

@Composable
private fun Spacer(height: androidx.compose.ui.unit.Dp) =
    androidx.compose.foundation.layout.Spacer(Modifier.height(height))

private val YellowCardShape = RoundedCornerShape(13.dp)
private val PlateShape = RoundedCornerShape(8.dp)
private val CardHeight = 35.dp
private val FieldHeight = 45.dp

/** Material's filled `share` (Apache 2.0). */
private const val SHARE_PATH =
    "M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"
