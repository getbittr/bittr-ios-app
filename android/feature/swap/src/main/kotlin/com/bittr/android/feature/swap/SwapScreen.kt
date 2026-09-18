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
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.focus.onFocusChanged
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
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrModalHeader
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

/**
 * Swap funds — `SwapViewController`, with `SwapStatusViewController` taking the card's place once
 * a swap is under way (on iOS it slides in over the same controller).
 *
 * As on Send, "Done" is a button beside the amount field rather than a keyboard toolbar, because
 * `swap_leg1.yaml` taps it by its text. Pulling the screen down closes it, like the iOS sheet the
 * flows swipe away.
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

    BittrCanvas(modifier = modifier.dismissOnPullDown(onDown), appBar = false) {
        BittrModalHeader(
            title = SwapCopy.SWAP_FUNDS_HEADER,
            onDown = onDown,
            icon = SWAP_PATH,
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
            val status = state.status
            if (status == null) {
                SwapCard(state, controller, clearFocus = { focusManager.clearFocus() })
            } else {
                StatusCard(status, controller)
            }
        }
    }
}

@Composable
private fun SwapCard(state: SwapUiState, controller: SwapController, clearFocus: () -> Unit) {
    var amountFocused by remember { mutableStateOf(false) }
    BittrCard(horizontalAlignment = Alignment.Start) {
        Text(
            SwapCopy.SUBTITLE,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(TestID.Swap.subtitleLabel),
        )
        Gap()
        Text(SwapCopy.MOVE, style = MaterialTheme.typography.titleMedium, color = BittrTheme.colors.emphasis)
        Gap(BittrTokens.Spacing.xs)
        Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            AmountField(
                value = state.amountText,
                onValueChange = controller::onAmountChange,
                onDone = clearFocus,
                modifier = Modifier
                    .weight(1f)
                    .onFocusChanged { amountFocused = it.hasFocus },
            )
            // The keyboard's companion, so only there while the amount is being typed; with the
            // keyboard down it posed as the primary action above Next (review S18).
            if (amountFocused) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .height(56.dp)
                        .clip(BittrCanvasShapes.pill)
                        .background(BittrTheme.colors.actionFill)
                        .clickable(onClick = clearFocus)
                        .padding(horizontal = BittrTokens.Spacing.lg),
                ) {
                    Text(SwapCopy.DONE, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.onActionFill)
                }
            }
        }

        Gap(BittrTokens.Spacing.sm)
        // The direction pill. The tap layer is under the label so the label keeps its own id.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .background(MaterialTheme.colorScheme.surfaceContainer, BittrCanvasShapes.field),
        ) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable {
                        clearFocus()
                        controller.onDirectionTapped()
                    }
                    .testTag(TestID.Swap.fromButton),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(horizontal = BittrTokens.Spacing.md),
            ) {
                Text(state.directionLabel, style = MaterialTheme.typography.labelLarge, modifier = Modifier.testTag(TestID.Swap.fromLabel))
                Spacer(Modifier.size(BittrTokens.Spacing.xs))
                Image(rememberStrokeIcon(SWAP_PATH, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f), contentDescription = null, modifier = Modifier.size(16.dp))
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
                            controller.onAvailableQuestion()
                        },
                )
                Text(state.available, style = MaterialTheme.typography.bodyMedium)
            }
            if (state.availableLoading) Spinner(Modifier.padding(start = BittrTokens.Spacing.xs))
            QuestionMark {
                clearFocus()
                controller.onAvailableQuestion()
            }
        }

        Gap()
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

        Gap(BittrTokens.Spacing.sm)
        Row(
            horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = BittrTokens.Size.minTouchTarget)
                .clickable {
                    clearFocus()
                    controller.onBoltzTapped()
                },
        ) {
            // "Powered by ⚡ Boltz", with the bolt iOS puts before the wordmark (review, `swap/03`).
            Text(
                SwapCopy.POWERED_BY,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.60f),
            )
            Image(
                rememberStrokeIcon(BittrIconPaths.BOLT, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
            Text("Boltz", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        }
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

@Composable
private fun AmountField(value: String, onValueChange: (String) -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = modifier
            .height(52.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, BittrCanvasShapes.field)
            .padding(horizontal = BittrTokens.Spacing.md),
    ) {
        if (value.isEmpty()) {
            Text(SwapCopy.ENTER_AMOUNT_OF_SATOSHIS, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
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
private const val REFRESH_PATH = "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5"

private const val DOWNLOAD_PATH = "M12 4v11m0 0l-5-5m5 5l5-5M5 20h14"

/** A detail row's value — 16 sp semibold, under its gold [BittrRowLabel] (review S15). */
private val RowValue: TextStyle
    @Composable get() = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold)
