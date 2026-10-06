package com.bittr.android.feature.swap

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import com.bittr.android.core.designsystem.BittrIconPaths
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrRowLabel
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrHelpButton
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.swaps.SwapAmounts
import com.bittr.android.core.swaps.SwapCopy
import com.bittr.android.core.swaps.SwapCoordinator
import com.bittr.android.core.swaps.SwapStatusState
import java.io.File
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.draw.alpha
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.rememberFillIcon

/**
 * Swap funds — `SwapViewController`, with `SwapStatusViewController` taking the card's place once
 * a swap is under way (on iOS it slides in over the same controller).
 *
 * iOS's keyboard-toolbar Done is the keyboard's own ✓ here, as on Send and Receive; the flows press
 * Enter for it (`helpers/amount_done.yaml`). Pulling the screen down closes it, like the iOS sheet
 * the flows swipe away.
 */
@Composable
fun SwapRoute(
    coordinator: SwapCoordinator,
    fiat: SwapFiat,
    launch: SwapLaunch,
    onDown: () -> Unit,
    onOpenTransaction: (String) -> Unit,
    onRequestNotifications: () -> Unit,
    onShareFile: (File) -> Unit,
    modifier: Modifier = Modifier,
    /**
     * Held by the caller so it outlives this composition: a completed swap opens the transaction
     * screen over this one, and a controller remembered here would be rebuilt when that screen
     * closes — losing the status card that swap.yaml then looks for, where iOS keeps `SwapStatusVC`
     * embedded under the modal transaction.
     */
    heldController: SwapController? = null,
) {
    val scope = rememberCoroutineScope()
    val controller = heldController ?: remember(coordinator, launch) { SwapController(coordinator, fiat, scope, launch) }
    val openTransaction by rememberUpdatedState(onOpenTransaction)
    val requestNotifications by rememberUpdatedState(onRequestNotifications)
    val shareFile by rememberUpdatedState(onShareFile)

    LaunchedEffect(controller) {
        controller.start()
        controller.effects.collect { effect ->
            when (effect) {
                is SwapUiEffect.OpenTransaction -> openTransaction(effect.id)
                SwapUiEffect.RequestNotifications -> requestNotifications()
                is SwapUiEffect.ShareFile -> shareFile(effect.file)
            }
        }
    }

    val state by controller.state.collectAsState()
    SwapScreen(state, controller, onDown, modifier)
}

@Composable
internal fun SwapScreen(state: SwapUiState, controller: SwapController, onDown: () -> Unit, modifier: Modifier = Modifier) {
    val focusManager = LocalFocusManager.current

    state.alert?.let { alert ->
        BittrAlert(
            title = alert.title,
            message = alert.message,
            buttons = alert.buttons.mapIndexed { position, button ->
                BittrAlertButton(label = button.label, dismissesAlert = position == 0, onClick = button.onClick)
            },
            modifier = if (alert.tag != null) Modifier.testTag(alert.tag) else Modifier,
        )
    }

    // `addHeader` with `iconswapwhite` over a block centred in the whole sheet: `centerCard`, 15 in
    // with 13 corners and the iOS shadow, and "Powered by" Boltz 25 under it. A tap beside the fields
    // closes the keyboard (`contentBackground`).
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown)
            .imePadding()
            .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } },
    ) {
        val sheetHeight = maxHeight
        Column(
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = sheetHeight)
                .padding(horizontal = 15.dp, vertical = 58.dp),
        ) {
            val status = state.status
            if (status == null) {
                SwapCard(state, controller, clearFocus = { focusManager.clearFocus() })
                PoweredByBoltz(onClick = {
                    focusManager.clearFocus()
                    controller.onBoltzTapped()
                })
            } else {
                StatusCard(status, controller)
            }
        }

        BittrSheetHeader(
            icon = painterResource(R.drawable.swap_header_icon),
            title = SwapCopy.SWAP_FUNDS_HEADER,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

/**
 * `centerCard`: the subtitle in Gilroy-Regular 16 40 from the top and 40 in, "Move" in Gilroy-Bold 16
 * 30 under it, then — 40 in — the amount field 10 under that and the direction button 10 under the
 * field. "Move up to …" with its question mark 15 under those, Next 25 under that, 30 from the bottom.
 */
@Composable
private fun SwapCard(state: SwapUiState, controller: SwapController, clearFocus: () -> Unit) {
    BittrCard(
        fill = BittrTheme.colors.levelCard,
        contentPadding = PaddingValues(start = 40.dp, end = 40.dp, top = 40.dp, bottom = 30.dp),
    ) {
        Text(
            SwapCopy.SUBTITLE,
            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.4.sp),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Swap.subtitleLabel),
        )
        Gap(30.dp)
        Text(
            SwapCopy.MOVE,
            style = MaterialTheme.typography.labelLarge.copy(lineHeight = 16.sp),
            color = BittrTheme.colors.emphasis,
            textAlign = TextAlign.Center,
        )
        Gap(10.dp)
        // The keyboard's ✓ is iOS's toolbar Done: it closes the keyboard.
        AmountField(
            value = state.amountText,
            onValueChange = controller::onAmountChange,
            onDone = clearFocus,
            modifier = Modifier.fillMaxWidth(),
        )

        Gap(10.dp)
        // `fromView`: 40 tall, `whiteorblue3` with 8 corners and the iOS shadow, the direction in
        // Gilroy-Bold 14, centred. The tap layer is under the label so the label keeps its own id.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp)
                .iosShadow(PlateShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape),
        ) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(PlateShape)
                    .clickable {
                        clearFocus()
                        controller.onDirectionTapped()
                    }
                    .testTag(TestID.Swap.fromButton),
            )
            Text(
                state.directionLabel,
                style = Bold14,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .offset(y = 1.dp)
                    .testTag(TestID.Swap.fromLabel),
            )
        }

        Gap(15.dp)
        // `availableView`: the line and its question mark 5 after it, centred; the spinner 10 after.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(PlateShape)
                    .clickable {
                        clearFocus()
                        controller.onAvailableQuestion()
                    }
                    .padding(vertical = 4.dp),
            ) {
                Text(
                    state.available,
                    style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Image(
                    rememberFillIcon(BittrIconPaths.HELP, MaterialTheme.colorScheme.onSurface),
                    contentDescription = "More information",
                    modifier = Modifier
                        .padding(start = 5.dp)
                        .offset(y = (-1).dp)
                        .size(16.dp),
                )
            }
            if (state.availableLoading) Spinner(Modifier.padding(start = 10.dp))
        }

        Gap(25.dp)
        BittrPrimaryButton(
            text = SwapCopy.NEXT,
            onClick = {
                clearFocus()
                controller.onNext()
            },
            modifier = Modifier.testTag(TestID.Swap.nextButton),
            content = if (state.nextLoading) {
                { BittrSpinner(strokeWidth = 2.dp, color = BittrTheme.colors.onActionFill, modifier = Modifier.size(20.dp)) }
            } else {
                null
            },
        )
    }
}

/**
 * Under the card, 25 below it and at half opacity: "Powered by" in Gilroy-Bold 14 and, 5 after it,
 * the Boltz wordmark at 43 by 12 — `boltzblack`, `boltzwhite` in dark. A tap opens Boltz's site.
 */
@Composable
private fun PoweredByBoltz(onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            // 25 to the label on iOS; the 48 dp touch target spends 17 of it.
            .padding(top = 7.dp)
            .heightIn(min = BittrTokens.Size.minTouchTarget)
            .clip(PlateShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp)
            .alpha(0.5f),
    ) {
        Text(
            SwapCopy.POWERED_BY,
            style = Bold14,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.offset(y = 1.5.dp),
        )
        Image(
            painter = painterResource(if (BittrTheme.isDark) R.drawable.swap_boltz_white else R.drawable.swap_boltz_black),
            contentDescription = "Boltz",
            modifier = Modifier
                .padding(start = 5.dp)
                .size(width = 43.dp, height = 12.dp),
        )
    }
}

/** `SwapStatusViewController`'s card: direction, amount, fees, status, download. */
@Composable
private fun StatusCard(status: SwapStatusState, controller: SwapController) {
    val swap = status.swap
    BittrCard(horizontalAlignment = Alignment.Start, modifier = Modifier.testTag(TestID.SwapStatus.confirmCard)) {
        // The card's own header, as the proposal draws it above the rows (review, Swapstatus).
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Image(
                rememberStrokeIcon(SWAP_PATH, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(SwapCopy.SWAP_STATUS_HEADER.lowercase(), style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp))
        }
        Gap(16.dp)
        InfoRow(SwapCopy.DIRECTION) { Text(swap.direction.label(), style = RowValue) }
        Gap(BittrTokens.Spacing.sm)
        InfoRow(SwapCopy.AMOUNT) { Text("${SwapAmounts.group(swap.satoshisAmount)} sats", style = RowValue) }
        Gap(BittrTokens.Spacing.sm)
        InfoRow(SwapCopy.FEES) { Text("${swap.formattedTotalFees()} sats", style = RowValue) }
        Gap(BittrTokens.Spacing.sm)
        InfoRow(SwapCopy.STATUS) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(status.statusText, style = RowValue, modifier = Modifier.weight(1f, fill = false).testTag(TestID.SwapStatus.confirmStatusLabel))
                if (status.spinning) Spinner(Modifier.padding(start = BittrTokens.Spacing.xs))
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(BittrTokens.Size.minTouchTarget)
                        .clickable(onClick = controller::onRefresh)
                        .testTag(TestID.SwapStatus.refreshButton),
                ) {
                    Image(rememberStrokeIcon(REFRESH_PATH, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f), contentDescription = "Refresh", modifier = Modifier.size(18.dp))
                }
                QuestionMark(onClick = controller::onStatusQuestion)
            }
        }
        Gap(16.dp)
        // An action, so a button rather than one more white row that reads as data (review S16).
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(BittrCanvasShapes.pill)
                .background(BittrTheme.colors.tonalFill)
                .clickable(role = Role.Button, onClick = controller::onDownload),
        ) {
            Image(
                rememberStrokeIcon(DOWNLOAD_PATH, BittrTheme.colors.onTonalFill, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(SwapCopy.DOWNLOAD_DETAILS, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.onTonalFill)
        }
    }
}

@Composable
private fun InfoRow(title: String, value: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer, BittrCanvasShapes.field)
            .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.sm),
    ) {
        BittrRowLabel(title)
        value()
    }
}

/**
 * `amountTextField`: 45 tall, `white0.7orblue3` with 8 corners and the iOS shadow, Gilroy-Regular 16
 * centred.
 */
@Composable
private fun AmountField(value: String, onValueChange: (String) -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val style = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(45.dp)
            .iosShadow(PlateShape)
            .background(BittrTheme.colors.scrim3, PlateShape)
            .padding(horizontal = 15.dp),
    ) {
        if (value.isEmpty()) {
            Text(
                SwapCopy.ENTER_AMOUNT_OF_SATOSHIS,
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
            cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
            // Satoshis, so digits only: `Number` still offers `,` `.` and `-` on Gboard and Samsung's
            // keyboard; `NumberPassword` is the digit pad, unmasked in a BasicTextField.
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onDone() }),
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Swap.amountTextField),
        )
    }
}

@Composable
private fun QuestionMark(onClick: () -> Unit) {
    BittrHelpButton(onClick = onClick)
}

@Composable
private fun Spinner(modifier: Modifier = Modifier) {
    BittrSpinner(strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onSurface, modifier = modifier.size(16.dp))
}

@Composable
private fun ColumnScope.Gap(height: Dp = BittrTokens.Spacing.md) {
    Spacer(Modifier.height(height))
}

private const val SWAP_PATH = "M7 4v16M3 8l4-4 4 4M17 20V4M13 16l4 4 4-4"

private val PlateShape = RoundedCornerShape(8.dp)
private val Bold14: TextStyle
    @Composable get() = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp)
private const val REFRESH_PATH = "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5"

private const val DOWNLOAD_PATH = "M12 4v11m0 0l-5-5m5 5l5-5M5 20h14"

/** A detail row's value — 16 sp semibold, under its gold [BittrRowLabel] (review S15). */
private val RowValue: TextStyle
    @Composable get() = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold)
