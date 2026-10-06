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
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.dismissOnPullDown
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

/**
 * `SwapStatusViewController`'s `confirmCard`: `yelloworblue2` with 13 corners and the iOS shadow. Its
 * header 20 in — `iconswapwhite` (`iconswap` in dark) at 18 and "swap status" in Gilroy-Bold 18,
 * `whiteoryellow`, 10 after it — then, 20 under that and 10 in, four 45 pt rows 10 apart, and the
 * download line 10 under them and 10 from the bottom.
 */
@Composable
private fun StatusCard(status: SwapStatusState, controller: SwapController) {
    val swap = status.swap
    val colors = BittrTheme.colors
    val dark = BittrTheme.isDark
    BittrCard(
        horizontalAlignment = Alignment.Start,
        fill = colors.levelCard,
        contentPadding = PaddingValues(start = 10.dp, end = 10.dp, top = 20.dp, bottom = 10.dp),
        modifier = Modifier.testTag(TestID.SwapStatus.confirmCard),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 10.dp)) {
            Image(
                painter = painterResource(if (dark) R.drawable.swap_icon_yellow else R.drawable.swap_header_icon),
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Text(
                SwapCopy.SWAP_STATUS_HEADER.lowercase(),
                style = MaterialTheme.typography.titleMedium.copy(lineHeight = 18.sp),
                color = colors.homeCardTitle,
                modifier = Modifier
                    .padding(start = 10.dp)
                    .offset(y = 1.dp),
            )
        }
        Gap(20.dp)
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            InfoRow(SwapCopy.DIRECTION) { Text(swap.direction.label(), style = RowValue, color = MaterialTheme.colorScheme.onSurface) }
            InfoRow(SwapCopy.AMOUNT) { Text("${SwapAmounts.group(swap.satoshisAmount)} sats", style = RowValue, color = MaterialTheme.colorScheme.onSurface) }
            InfoRow(SwapCopy.FEES) { Text("${swap.formattedTotalFees()} sats", style = RowValue, color = MaterialTheme.colorScheme.onSurface) }
            // `confirmStatus`: the spinner 8 after the title; at the end the 12 pt reset icon, the
            // status 8 after it and the question mark 8 after that, 15 from the end.
            InfoRow(SwapCopy.STATUS, endPadding = 7.dp, titleTrailing = {
                if (status.spinning) Spinner(Modifier.padding(start = 8.dp))
            }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(width = 32.dp, height = RowHeight)
                            .clickable(role = Role.Button, onClickLabel = "Refresh", onClick = controller::onRefresh)
                            .testTag(TestID.SwapStatus.refreshButton),
                    ) {
                        Image(
                            painter = painterResource(if (dark) R.drawable.swap_reset_white else R.drawable.swap_reset_black),
                            contentDescription = "Refresh",
                            modifier = Modifier
                                .offset(y = (-1).dp)
                                .size(12.dp),
                        )
                    }
                    Text(
                        status.statusText,
                        style = RowValue,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .testTag(TestID.SwapStatus.confirmStatusLabel),
                    )
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(width = 32.dp, height = RowHeight)
                            .clickable(role = Role.Button, onClickLabel = "More information", onClick = controller::onStatusQuestion),
                    ) {
                        Image(
                            rememberFillIcon(BittrIconPaths.HELP, MaterialTheme.colorScheme.onSurface),
                            contentDescription = "More information",
                            modifier = Modifier
                                .offset(y = (-1).dp)
                                .size(16.dp),
                        )
                    }
                }
            }
        }
        Gap(10.dp)
        // `downloadView`: 35 tall with no plate, `icondownloadblack` (`icondownload` in dark) at 12 and
        // "Download details" in Gilroy-Regular 16 8 after it, centred.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
            modifier = Modifier
                .fillMaxWidth()
                .height(35.dp)
                .clip(PlateShape)
                .clickable(role = Role.Button, onClick = controller::onDownload),
        ) {
            Image(
                painter = painterResource(if (dark) R.drawable.swap_download_white else R.drawable.swap_download_black),
                contentDescription = null,
                modifier = Modifier
                    .offset(y = (-1).dp)
                    .size(12.dp),
            )
            Text(
                SwapCopy.DOWNLOAD_DETAILS,
                style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(start = 8.dp),
            )
        }
    }
}

/**
 * One of the status card's rows: 45 tall, `whiteorblue3` with 8 corners, the title in yellow
 * Gilroy-Bold 16 15 in and the value at the end, 15 from it unless [endPadding] says otherwise.
 */
@Composable
private fun InfoRow(
    title: String,
    endPadding: Dp = 15.dp,
    titleTrailing: @Composable () -> Unit = {},
    value: @Composable () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(RowHeight)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, PlateShape)
            .padding(start = 15.dp, end = endPadding),
    ) {
        Text(title, style = RowValue, color = BittrTheme.colors.brandFixed, modifier = Modifier.offset(y = 1.dp))
        titleTrailing()
        Spacer(Modifier.weight(1f))
        Box(modifier = Modifier.offset(y = 1.dp)) { value() }
    }
}

private val RowHeight = 45.dp

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
private fun Spinner(modifier: Modifier = Modifier) {
    BittrSpinner(strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onSurface, modifier = modifier.size(16.dp))
}

@Composable
private fun ColumnScope.Gap(height: Dp = BittrTokens.Spacing.md) {
    Spacer(Modifier.height(height))
}


private val PlateShape = RoundedCornerShape(8.dp)
private val Bold14: TextStyle
    @Composable get() = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp)


/** The status rows' titles and values: Gilroy-Bold 16. */
private val RowValue: TextStyle
    @Composable get() = MaterialTheme.typography.labelLarge.copy(lineHeight = 18.sp)
