package com.bittr.android.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTextFieldAlert
import com.bittr.android.core.wallet.TransactionNoteStore
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Reads the transaction named by the route's [ID_ARG] out of the wallet overview. */
@HiltViewModel
class TransactionViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    overview: WalletOverviewSource,
    prices: FiatPriceSource,
    private val notes: TransactionNoteStore,
) : ViewModel() {

    private val id: String = checkNotNull(savedStateHandle[ID_ARG]) { "transaction route without an id" }
    private val price = MutableStateFlow<FiatPrice?>(null)

    init {
        viewModelScope.launch { price.value = prices.current() }
    }

    internal val detail: StateFlow<TransactionDetail?> = combine(overview.overview, price, notes.notes) { wallet, price, notes ->
        wallet.transactions.firstOrNull { it.id == id }?.let {
            transactionDetail(
                activity = it,
                price = price,
                currentHeight = wallet.currentHeight,
                closureTxIds = wallet.channelClosureTxIds,
                note = notes[it.id],
            )
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /** `noteButtonTapped`'s save: trimmed and stored, or deleted when cleared. */
    fun saveNote(note: String) = notes.store(id, note)

    companion object {
        const val ID_ARG = "id"
    }
}

/**
 * The transaction screen — `TransactionViewController`: date, amount, type, fees, confirmations,
 * the swap's id and status for a swap, the id(s) with copy and explorer buttons, and the current
 * value.
 *
 * @param onOpenExplorer opens the block explorer on the given transaction id.
 * @param onOpenSwapStatus `openSwapTapped` → `TransactionToSwapStatus`, with the Boltz swap id.
 */
@Composable
fun TransactionScreen(
    onDown: () -> Unit,
    onOpenExplorer: (String) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSwapStatus: (String) -> Unit = {},
    viewModel: TransactionViewModel = hiltViewModel(),
) {
    val detail by viewModel.detail.collectAsState()
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf<String?>(null) }
    var editingNote by remember { mutableStateOf(false) }

    copied?.let {
        BittrAlertDialog(
            title = HomeStrings.COPIED,
            message = it,
            confirmLabel = HomeStrings.OKAY,
            onConfirm = { copied = null },
            confirmTestTag = TestID.Alert.buttonAt(0),
            modifier = Modifier.testTag(TestID.Alert.copied),
        )
    }
    if (editingNote) {
        BittrTextFieldAlert(
            title = HomeStrings.ADD_A_NOTE,
            initialText = detail?.note.orEmpty(),
            placeholder = HomeStrings.ADD_A_NOTE,
            cancelLabel = HomeStrings.CANCEL,
            saveLabel = HomeStrings.SAVE,
            onCancel = { editingNote = false },
            onSave = { note ->
                viewModel.saveNote(note)
                editingNote = false
            },
            testTag = TestID.Alert.addNote,
        )
    }

    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = HomeStrings.TRANSACTION,
            onDown = onDown,
            icon = BittrIconPaths.PIGGY,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(BittrTokens.Spacing.md),
        ) {
            val shown = detail ?: return@Column
            fun copy(text: String) {
                clipboard.setText(AnnotatedString(text))
                copied = text
            }
            BittrCard(modifier = Modifier.testTag(TestID.Transaction.yellowCard)) {
                Column(verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm)) {
                    Text(
                        text = shown.date,
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = BittrTokens.Spacing.xs)
                            .testTag(TestID.Transaction.labelDate),
                    )
                    DetailRow(HomeStrings.AMOUNT, shown.amount, valueTag = TestID.Transaction.labelAmount)
                    DetailRow(HomeStrings.TYPE, if (shown.isLightning) HomeStrings.INSTANT else HomeStrings.REGULAR, bolt = shown.isLightning)
                    shown.fees?.let { DetailRow(HomeStrings.FEES_PAID, it) }
                    shown.confirmations?.let { DetailRow(HomeStrings.CONFIRMATIONS, it) }
                    shown.swap?.let { swap ->
                        DetailRow(HomeStrings.SWAP_ID, swap.swapIdLabel)
                        SwapStatusRow(
                            status = swap.status,
                            onClick = swap.boltzId?.let { boltzId -> { onOpenSwapStatus(boltzId) } },
                        )
                    }
                    IdRow(
                        title = shown.idTitle,
                        id = shown.id,
                        onCopy = { copy(shown.id) },
                        copyTag = TestID.Transaction.copyIdButton,
                        onExplorer = shown.explorerId?.let { explorerId -> { onOpenExplorer(explorerId) } },
                        explorerTag = TestID.Transaction.urlIdButton,
                    )
                    val swap = shown.swap
                    if (swap?.bottomIdTitle != null) {
                        val bottomId = swap.bottomId.orEmpty()
                        IdRow(
                            title = swap.bottomIdTitle,
                            id = bottomId,
                            onCopy = if (swap.bottomIdCopyable) ({ copy(bottomId) }) else null,
                            copyTag = TestID.Transaction.copyBottomIdButton,
                            onExplorer = swap.bottomExplorerId?.let { explorerId -> { onOpenExplorer(explorerId) } },
                            explorerTag = null,
                        )
                    }
                    shown.currentValue?.let { DetailRow(HomeStrings.CURRENT_VALUE, it) }
                }
            }
            shown.description?.let { description ->
                TextCard(
                    title = HomeStrings.DESCRIPTION,
                    text = description,
                    textTag = TestID.Transaction.descriptionLabel,
                    buttonTag = TestID.Transaction.descriptionButton,
                    onClick = { copy(description) },
                )
            }
            val note = shown.note
            if (note != null) {
                TextCard(
                    title = HomeStrings.NOTE,
                    text = note,
                    textTag = TestID.Transaction.labelNote,
                    buttonTag = null,
                    onClick = { editingNote = true },
                )
            } else {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .padding(top = BittrTokens.Spacing.md)
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                        .clickable { editingNote = true }
                        .padding(BittrTokens.Spacing.md)
                        .testTag(TestID.Transaction.addNoteButton),
                ) {
                    Text(HomeStrings.ADD_A_NOTE, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

/**
 * The Description and Note cards. The whole card is the tap target, drawn under the text so
 * the text keeps its own id (a clickable parent would merge it away).
 */
@Composable
private fun TextCard(title: String, text: String, textTag: String, buttonTag: String?, onClick: () -> Unit) {
    Box(modifier = Modifier.padding(top = BittrTokens.Spacing.md)) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                .clickable(onClick = onClick)
                .then(if (buttonTag != null) Modifier.testTag(buttonTag) else Modifier),
        )
        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs),
            modifier = Modifier
                .fillMaxWidth()
                .padding(BittrTokens.Spacing.md),
        ) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
            Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag(textTag))
        }
    }
}

@Composable
private fun DetailRow(title: String, value: String, valueTag: String? = null, bolt: Boolean = false) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
            .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
    ) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis, modifier = Modifier.weight(1f))
        if (bolt) {
            Image(
                imageVector = rememberStrokeIcon(BittrIconPaths.BOLT, BittrTheme.colors.emphasis, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier
                    .padding(end = BittrTokens.Spacing.xs)
                    .size(16.dp),
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            modifier = if (valueTag != null) Modifier.testTag(valueTag) else Modifier,
        )
    }
}

/**
 * The swap status row. `buttonSwapStatus` covers it on iOS; here the tap layer is drawn under the
 * labels so they stay readable to the flows, and it carries `transaction.swapStatusButton`.
 */
@Composable
private fun SwapStatusRow(status: String, onClick: (() -> Unit)?) {
    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
                .testTag(TestID.Transaction.swapStatusButton),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        ) {
            Text(HomeStrings.SWAP_STATUS, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis, modifier = Modifier.weight(1f))
            Text(text = status, style = MaterialTheme.typography.bodyLarge)
            if (onClick != null) {
                Text(" ›", style = MaterialTheme.typography.bodyLarge, color = BittrTheme.colors.emphasis)
            }
        }
    }
}

@Composable
private fun IdRow(
    title: String,
    id: String,
    onCopy: (() -> Unit)?,
    copyTag: String,
    onExplorer: (() -> Unit)?,
    explorerTag: String?,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
            .padding(start = BittrTokens.Spacing.md),
    ) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
        Text(
            text = id,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = BittrTokens.Spacing.sm),
        )
        if (onExplorer != null) {
            IconButton(LINK_PATH, "Open in explorer", onExplorer, explorerTag)
        }
        if (onCopy != null) {
            IconButton(COPY_PATH, HomeStrings.COPIED, onCopy, copyTag)
        }
    }
}

@Composable
private fun IconButton(path: String, label: String, onClick: () -> Unit, testTag: String?) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(BittrTokens.Size.minTouchTarget)
            .clickable(onClick = onClick)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Image(
            imageVector = rememberStrokeIcon(path, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
            contentDescription = label,
            modifier = Modifier.size(18.dp),
        )
    }
}

private const val COPY_PATH = "M9 9h11v11H9zM5 15V4h11"
private const val LINK_PATH = "M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"
