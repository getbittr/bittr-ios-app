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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.Color
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrMark
import com.bittr.android.core.designsystem.BittrRowLabel
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrHelpButton
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Receive — `ios/bittr/Move, Send, Receive/ReceiveVC/ReceiveViewController`.
 *
 * The QR in a white box, the address box under it, a row of cards (copy, renew, add amount,
 * more) and, when opened, the amount stack. Behaviour lives in [ReceiveController]; this
 * draws its state and forwards taps.
 *
 * Two things differ from iOS because the platform does:
 *
 * - **"Done" is a button on screen.** iOS puts it on a toolbar above the keyboard, and
 *   `receive_onchain.yaml` taps it by its text. A keyboard toolbar is not part of the app's
 *   view hierarchy on Android, so the same button sits beside the amount field instead.
 * - **The QR's long-press menu is a dropdown**, with the same two items — Copy and Share —
 *   and Share opens the system share sheet with the copyable text.
 */
@Composable
fun ReceiveRoute(source: ReceiveSource, onDown: () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val controller = remember(source) { ReceiveController(source, scope) }
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
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current

    fun copy() {
        controller.onCopy()?.let { clipboard.setText(AnnotatedString(it)) }
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
            buttons = alert.buttons.mapIndexed { position, button ->
                BittrAlertButton(
                    label = button.label,
                    dismissesAlert = position == 0,
                    onClick = { controller.onAlertButton(position) },
                )
            },
        )
    }

    BittrCanvas(modifier = modifier.dismissOnPullDown(onDown), appBar = false) {
        BittrModalHeader(
            title = ReceiveStrings.RECEIVE_BITCOIN,
            onDown = onDown,
            icon = BittrIconPaths.PIGGY,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                // Before the scroll, so the visible area ends at the keyboard.
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        ) {
            BittrCard {
                QrBox(
                    payload = state.display?.qrPayload,
                    loading = state.loading,
                    onCopy = ::copy,
                    onShare = ::share,
                )
                Spacer(BittrTokens.Spacing.md)
                AddressBox(state = state, onQuestion = controller::onQuestion)
                Spacer(BittrTokens.Spacing.md)
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
                    Spacer(BittrTokens.Spacing.md)
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
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun QrBox(payload: String?, loading: Boolean, onCopy: () -> Unit, onShare: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    val bitmap by produceState<ImageBitmap?>(initialValue = null, payload) {
        value = payload?.let { withContext(Dispatchers.Default) { qrBitmap(it).asImageBitmap() } }
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(24.dp))
            .padding(16.dp),
    ) {
        val shown = bitmap
        if (!loading && shown != null) {
            Box {
                Image(
                    bitmap = shown,
                    contentDescription = "QR code",
                    modifier = Modifier
                        .fillMaxSize()
                        .combinedClickable(onClick = {}, onLongClick = { menuOpen = true })
                        .testTag(TestID.Receive.qrImageView),
                )
                // The bittr mark at the centre, on a white keyline (review, `receive_invoice/02`).
                // 18 % of the width covers about 3 % of the modules, well inside what the
                // code's level-H error correction (30 %) recovers.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .fillMaxSize(0.18f)
                        .background(Color.White, RoundedCornerShape(8.dp))
                        .padding(4.dp),
                ) {
                    BittrMark(
                        ink = Color.Black,
                        arc = BittrTheme.colors.brandFixed,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(ReceiveStrings.MENU_COPY) },
                        onClick = {
                            menuOpen = false
                            onCopy()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(ReceiveStrings.MENU_SHARE) },
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

@Composable
private fun AddressBox(state: ReceiveUiState, onQuestion: () -> Unit) {
    val display = state.display
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp))
            .padding(horizontal = BittrTokens.Spacing.lg, vertical = BittrTokens.Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            if (display?.showBolt == true) {
                Image(
                    imageVector = rememberStrokeIcon(BittrIconPaths.BOLT, BittrTheme.colors.rowLabel),
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
            }
            BittrRowLabel(
                text = if (state.loading) "" else display?.title.orEmpty(),
                modifier = Modifier
                    .padding(start = if (display?.showBolt == true) BittrTokens.Spacing.xs else 0.dp)
                    .testTag(TestID.Receive.addressTitle),
            )
            BittrHelpButton(onClick = onQuestion, modifier = Modifier.testTag(TestID.Receive.questionButton))
            val address = if (state.loading) "" else display?.addressLabel.orEmpty()
            // A Lightning address is read aloud and typed, so it is never elided (review, pass 2,
            // `receive/02`): up to two lines, breaking before the `@` rather than inside the
            // domain. The zero-width space is display only — the copy action reads the model.
            val lightningAddress = '@' in address
            Text(
                text = if (lightningAddress) address.replace("@", "\u200B@") else address,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                textAlign = TextAlign.End,
                modifier = Modifier
                    .weight(1f)
                    .testTag(TestID.Receive.addressLabel),
            )
        }
        val lower = if (state.loading) "" else display?.lowerLabel.orEmpty()
        if (lower.isNotEmpty()) {
            Text(
                text = lower,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 3,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = BittrTokens.Spacing.xs)
                    .testTag(TestID.Receive.invoiceLabel),
            )
        }
    }
}

@Composable
private fun CardsRow(
    cards: ReceiveCards,
    onCopy: () -> Unit,
    onRefresh: () -> Unit,
    onEdit: () -> Unit,
    onMore: () -> Unit,
) {
    // Two actions sit icon-beside-label at 52 dp; three or four stack the icon above the label so
    // none truncates (review S8). Every action is labelled either way (review S16).
    val stacked = listOf(true, cards.refresh, cards.edit, cards.more).count { it } > 2
    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm), modifier = Modifier.fillMaxWidth()) {
        ReceiveCard(
            label = ReceiveStrings.COPY,
            path = COPY_PATH,
            contentDescription = ReceiveStrings.COPY,
            onClick = onCopy,
            testTag = TestID.Receive.copyButton,
            modifier = Modifier.weight(1f),
            stacked = stacked,
        )
        if (cards.refresh) {
            ReceiveCard(ReceiveStrings.RENEW, RENEW_PATH, ReceiveStrings.RENEW, onRefresh, TestID.Receive.refreshButton, Modifier.weight(1f), stacked)
        }
        if (cards.edit) {
            ReceiveCard(ReceiveStrings.ADD_AMOUNT, EDIT_PATH, ReceiveStrings.ADD_AMOUNT, onEdit, TestID.Receive.editButton, Modifier.weight(1.3f), stacked)
        }
        if (cards.more) {
            ReceiveCard(ReceiveStrings.MORE, MORE_PATH, ReceiveStrings.MORE, onMore, TestID.Receive.moreButton, Modifier.weight(1f), stacked)
        }
    }
}

/**
 * One tonal action: the icon above its label, so the label has the whole width of the button.
 * Side by side they truncated ("Rene", "Add") — review S8. A label that still does not fit, at a
 * large font scale, is dropped rather than cut, and the icon carries the name for TalkBack.
 */
/**
 * One tonal action. Stacked — icon above label — when the row holds three or four, so the label
 * has the button's whole width (side by side they truncated, "Rene", "Add": review S8); side by
 * side at 52 dp when it holds two. A label that still does not fit at a large font scale is
 * dropped rather than cut, and the icon carries the name for TalkBack.
 */
@Composable
private fun ReceiveCard(
    label: String?,
    path: String,
    contentDescription: String,
    onClick: () -> Unit,
    testTag: String,
    modifier: Modifier = Modifier,
    stacked: Boolean = true,
) {
    val colors = BittrTheme.colors
    var labelFits by remember(label, stacked) { mutableStateOf(true) }
    val showLabel = label != null && labelFits
    val icon = @Composable {
        Image(
            imageVector = rememberStrokeIcon(path, colors.onTonalFill, strokeWidth = 2f),
            contentDescription = if (showLabel) null else contentDescription,
            modifier = Modifier.size(20.dp),
        )
    }
    val text = @Composable {
        if (label != null && labelFits) {
            Text(
                label,
                style = if (stacked) MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold) else MaterialTheme.typography.labelLarge,
                color = colors.onTonalFill,
                maxLines = 1,
                softWrap = false,
                onTextLayout = { if (it.hasVisualOverflow) labelFits = false },
            )
        }
    }
    val base = modifier
        .widthIn(min = 56.dp)
        .height(if (stacked) 64.dp else 52.dp)
        .clip(if (stacked) RoundedCornerShape(16.dp) else BittrCanvasShapes.pill)
        .background(colors.tonalFill)
        .clickable(role = Role.Button, onClick = onClick)
        .padding(horizontal = if (stacked) 4.dp else BittrTokens.Spacing.md)
        .testTag(testTag)
    if (stacked) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            modifier = base,
        ) {
            icon()
            text()
        }
    } else {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            modifier = base,
        ) {
            icon()
            text()
        }
    }
}

@Composable
private fun AmountStack(
    state: ReceiveUiState,
    onAmountChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onCurrency: () -> Unit,
    onDone: () -> Unit,
) {
    val colors = BittrTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
        Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            EntryField(
                value = state.amountText,
                placeholder = ReceiveStrings.AMOUNT,
                onValueChange = onAmountChange,
                keyboardType = if (state.currency == ReceiveCurrency.Satoshis) KeyboardType.Number else KeyboardType.Decimal,
                onDone = onDone,
                testTag = TestID.Receive.amountTextField,
                modifier = Modifier.weight(1f),
            )
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(52.dp)
                    .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp))
                    .clickable(onClick = onCurrency)
                    .padding(horizontal = BittrTokens.Spacing.md)
                    .testTag(TestID.Receive.currencyButton),
            ) {
                Text(
                    text = state.currencyLabel,
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.testTag(TestID.Receive.currencyLabel),
                )
            }
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(52.dp)
                    .background(colors.actionFill, RoundedCornerShape(12.dp))
                    .clickable(onClick = onDone)
                    .padding(horizontal = BittrTokens.Spacing.md),
            ) {
                Text(ReceiveStrings.DONE, style = MaterialTheme.typography.labelLarge, color = colors.onActionFill)
            }
        }
        if (state.showsDescription) {
            // A labelled white field, as the proposal draws text fields, rather than a bare
            // cream bar (review, `receive_invoice/02`).
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(ReceiveStrings.DESCRIPTION, style = MaterialTheme.typography.labelMedium)
                EntryField(
                    value = state.descriptionText,
                    placeholder = ReceiveStrings.DESCRIPTION,
                    onValueChange = onDescriptionChange,
                    keyboardType = KeyboardType.Text,
                    onDone = onDone,
                    testTag = null,
                    modifier = Modifier.fillMaxWidth(),
                    white = true,
                )
            }
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
    white: Boolean = false,
) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = if (white) Alignment.CenterStart else Alignment.Center,
        modifier = modifier
            .height(if (white) 56.dp else 52.dp)
            .background(
                if (white) MaterialTheme.colorScheme.surfaceContainer else colors.tonalFill,
                if (white) BittrCanvasShapes.field else RoundedCornerShape(12.dp),
            )
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        if (value.isEmpty()) {
            Text(
                placeholder,
                style = MaterialTheme.typography.bodyLarge,
                color = if (white) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f) else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = if (white) MaterialTheme.colorScheme.onSurface else colors.onTonalFill,
                textAlign = if (white) TextAlign.Start else TextAlign.Center,
            ),
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

// Glyphs for the four cards, as stroke paths on the design system's 24-unit grid.
private const val COPY_PATH = "M9 9h11v11H9zM5 15V4h11"
private const val RENEW_PATH = "M4 12a8 8 0 1 0 2.4-5.7M4 4v5h5"
private const val EDIT_PATH = "M4 20h4L19 9l-4-4L4 16zM14 6l4 4"
private const val MORE_PATH = "M6 9l6 6 6-6"
