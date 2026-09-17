package com.bittr.android.feature.home

import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTextFieldAlert
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.wallet.BittrPurchaseSource
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.TransactionNoteStore
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Reads the transaction named by the route's [ID_ARG] out of the wallet overview, with bittr's record
 * of it when there is one. [CONFETTI_ARG] opens it as the bittr payout summary (`showConfetti`).
 */
@HiltViewModel
class TransactionViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    overview: WalletOverviewSource,
    prices: FiatPriceSource,
    private val notes: TransactionNoteStore,
    private val purchases: BittrPurchaseSource,
    private val cache: HomeCache = HomeCache.None,
) : ViewModel() {

    private val id: String = checkNotNull(savedStateHandle[ID_ARG]) { "transaction route without an id" }
    private val confetti: Boolean = savedStateHandle.get<Boolean>(CONFETTI_ARG) ?: false
    private val price = MutableStateFlow<FiatPrice?>(null)

    /** One bitcoin in the purchase's own currency, for its current value and profit. */
    private val purchasePrice = MutableStateFlow<Double?>(null)

    init {
        viewModelScope.launch { price.value = prices.current() }
        viewModelScope.launch {
            purchases.purchases.map { it[id]?.currency }.distinctUntilChanged().collect { currency ->
                purchasePrice.value = currency?.let { purchases.pricePerBitcoin(it) }
            }
        }
    }

    internal val detail: StateFlow<TransactionDetail?> = combine(
        overview.overview,
        price,
        notes.notes,
        purchases.purchases,
        purchasePrice,
    ) { wallet, price, notes, bought, purchasePrice ->
        val purchase = bought[id]
        // A row Home showed from the cache before the first sync opens too, as on iOS, where
        // `transactionButtonTapped` is not guarded; confirmations count from `cachedHeight`.
        val cached = cache.cached.value?.takeUnless { wallet.hasSynced }
        // The funding purchase is not a row of this wallet's history; bittr's record stands in for it.
        val activity = wallet.transactions.firstOrNull { it.id == id }
            ?: cached?.transactions?.firstOrNull { it.id == id }
            ?: purchase?.let(::purchaseActivity)
        activity?.let {
            transactionDetail(
                activity = it,
                price = price,
                currentHeight = wallet.currentHeight ?: cache.cached.value?.currentHeight,
                closureTxIds = wallet.channelClosureTxIds.ifEmpty { cached?.channelClosureTxIds.orEmpty() },
                note = notes[it.id],
                purchase = purchase,
                confetti = confetti,
                isFunding = purchase != null && purchases.fundingTxId() == id,
                purchasePrice = purchasePrice,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /** `noteButtonTapped`'s save: trimmed and stored, or deleted when cleared. */
    fun saveNote(note: String) = notes.store(id, note)

    companion object {
        const val ID_ARG = "id"
        const val CONFETTI_ARG = "confetti"
    }
}

/**
 * The transaction screen — `TransactionViewController`: date, amount, type, fees, confirmations,
 * the swap's id and status for a swap, the id(s) with copy and explorer buttons, the current value,
 * and a bittr purchase's section.
 *
 * Opened as the bittr payout summary (`showConfetti`) it adds the piggy-bank header ("Good job…"),
 * the reminder not to delete the app, and two seconds of red hearts falling, and hides the type row,
 * the ids, the description and the note.
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
    // `bittrFeesTapped`: a fee's explanation, as (title, body).
    var feeExplanation by remember { mutableStateOf<Pair<String, String>?>(null) }

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
    feeExplanation?.let { (title, body) ->
        BittrAlertDialog(
            title = title,
            message = body,
            confirmLabel = HomeStrings.OKAY,
            onConfirm = { feeExplanation = null },
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }
    // A saved note is scrolled into view: under a bittr purchase's card it lands below the fold.
    val noteRequester = remember { BringIntoViewRequester() }
    var revealNote by remember { mutableStateOf(false) }
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
                revealNote = true
            },
            testTag = TestID.Alert.addNote,
        )
    }

    Box(modifier = modifier) {
        BittrCanvas(modifier = Modifier.fillMaxSize().dismissOnPullDown(onDown), appBar = false) {
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
                if (shown.confetti) {
                    PayoutHeader()
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
                        if (!shown.confetti) {
                            DetailRow(HomeStrings.TYPE, shown.type, bolt = shown.typeBolt)
                        }
                        shown.fees?.let { DetailRow(HomeStrings.FEES_PAID, it) }
                        shown.confirmations?.let { DetailRow(HomeStrings.CONFIRMATIONS, it) }
                        shown.swap?.let { swap ->
                            DetailRow(HomeStrings.SWAP_ID, swap.swapIdLabel)
                            SwapStatusRow(
                                status = swap.status,
                                onClick = swap.boltzId?.let { boltzId -> { onOpenSwapStatus(boltzId) } },
                            )
                        }
                        // `descriptionStack` sits between Confirmations and the ids in the card (Main.storyboard).
                        shown.description?.let { description ->
                            DescriptionRow(
                                description = description,
                                singleLine = shown.bittr != null,
                                onClick = { copy(description) },
                            )
                        }
                        if (!shown.confetti) {
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
                        }
                        shown.currentValue?.let { DetailRow(HomeStrings.CURRENT_VALUE, it) }
                        shown.bittr?.let { bittr ->
                            BittrSection(bittr = bittr, onExplain = { title, body -> feeExplanation = title to body })
                        }
                    }
                }
                if (shown.confetti) {
                    ReminderCard()
                }
                // The payout summary offers no note (`addANoteStack` hidden under `showConfetti`).
                if (!shown.confetti) {
                    val note = shown.note
                    if (note != null) {
                        Box(modifier = Modifier.bringIntoViewRequester(noteRequester)) {
                            TextCard(
                                title = HomeStrings.NOTE,
                                text = note,
                                textTag = TestID.Transaction.labelNote,
                                buttonTag = null,
                                onClick = { editingNote = true },
                            )
                        }
                        LaunchedEffect(note, revealNote) {
                            if (revealNote) {
                                noteRequester.bringIntoView()
                                revealNote = false
                            }
                        }
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
        if (detail?.confetti == true) {
            HeartsConfetti(modifier = Modifier.matchParentSize())
        }
    }
}

/** `bittrPayoutStack`: the `bittrpiggy2` illustration and "Good job, …". */
@Composable
private fun PayoutHeader() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = BittrTokens.Spacing.md),
    ) {
        Image(
            painter = painterResource(R.drawable.bittr_piggy),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.height(120.dp),
        )
        Text(
            text = HomeStrings.GOOD_JOB,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** `alertStack`: the reminder that the lightning funds live only on this device. */
@Composable
private fun ReminderCard() {
    Column(
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs),
        modifier = Modifier
            .padding(top = BittrTokens.Spacing.md)
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
            .padding(BittrTokens.Spacing.md),
    ) {
        Text(HomeStrings.REMINDER, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
        Text(HomeStrings.REMINDER_BODY, style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * `bittrFeesStack`. The three fee rows explain themselves when tapped (`bittrFeesTapped`, tags 0–2);
 * the transfer fee and bittr fee carry iOS's `transferFeeButton` / `bittrFeeButton` ids.
 */
@Composable
private fun BittrSection(bittr: BittrDetail, onExplain: (String, String) -> Unit) {
    DetailRow(HomeStrings.RECEIVED_AT_BITTR, bittr.receivedAtBittr)
    bittr.surcharge?.let { surcharge ->
        TappableRow(HomeStrings.SURCHARGE, surcharge, testTag = null) { onExplain(HomeStrings.SURCHARGE, HomeStrings.SURCHARGE_1) }
    }
    TappableRow(HomeStrings.BITTR_FEE, bittr.bittrFee, testTag = TestID.Transaction.bittrFeeButton) {
        onExplain(HomeStrings.BITTR_FEE, HomeStrings.BITTR_FEE_1)
    }
    TappableRow(HomeStrings.TRANSFER_FEE, bittr.transferFee, testTag = TestID.Transaction.transferFeeButton) {
        onExplain(HomeStrings.TRANSFER_FEE, bittr.transferFeeExplanation)
    }
    DetailRow(HomeStrings.PURCHASE_VALUE, bittr.purchaseValue)
    DetailRow(HomeStrings.EXCHANGE_RATE, bittr.exchangeRate)
    DetailRow(HomeStrings.CURRENT_VALUE, bittr.currentValue)
    DetailRow(
        HomeStrings.PROFIT,
        bittr.profit,
        valueColor = if (bittr.isLoss) BittrTheme.colors.loss else BittrTheme.colors.profit,
    )
}

/** Two seconds of red hearts falling across the screen — iOS's `SPConfetti` `.fullWidthToDown` with `.heart` particles. */
@Composable
private fun HeartsConfetti(modifier: Modifier = Modifier) {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        progress.animateTo(1f, tween(durationMillis = CONFETTI_MILLIS, easing = LinearEasing))
    }
    val hearts = remember {
        List(HEART_COUNT) { index ->
            val random = Random(index * 7919 + 17)
            Heart(
                x = random.nextFloat(),
                delay = random.nextFloat() * 0.35f,
                speed = 0.7f + random.nextFloat() * 0.6f,
                sizeDp = 10f + random.nextFloat() * 10f,
                sway = random.nextFloat() * 2f - 1f,
            )
        }
    }
    if (progress.value >= 1f) return
    Canvas(modifier = modifier) {
        hearts.forEach { heart ->
            val t = ((progress.value - heart.delay) / (1f - heart.delay)).coerceIn(0f, 1f)
            if (t <= 0f) return@forEach
            val side = heart.sizeDp * density
            val x = heart.x * size.width + heart.sway * 24f * density * sin(t * 6f)
            val y = -side + t * heart.speed * (size.height + side * 2)
            val alpha = if (t > 0.8f) (1f - t) / 0.2f else 1f
            translate(left = x, top = y) {
                drawPath(heartPath(side), Color.Red.copy(alpha = alpha))
            }
        }
    }
}

private data class Heart(val x: Float, val delay: Float, val speed: Float, val sizeDp: Float, val sway: Float)

private fun heartPath(side: Float): Path = Path().apply {
    moveTo(side / 2f, side * 0.9f)
    cubicTo(-side * 0.1f, side * 0.45f, side * 0.15f, -side * 0.05f, side / 2f, side * 0.25f)
    cubicTo(side * 0.85f, -side * 0.05f, side * 1.1f, side * 0.45f, side / 2f, side * 0.9f)
    close()
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
private fun DetailRow(
    title: String,
    value: String,
    valueTag: String? = null,
    bolt: Boolean = false,
    valueColor: Color = Color.Unspecified,
) {
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
            color = valueColor,
            modifier = if (valueTag != null) Modifier.testTag(valueTag) else Modifier,
        )
    }
}

/**
 * `descriptionStack`: "Description" and its text in a row like the others, copied when tapped. A bittr
 * purchase's description (the payout's notification id) is one line, truncated in the middle, as iOS
 * sets it; any other wraps. The tap layer sits under the labels so they stay readable to the flows.
 */
@Composable
private fun DescriptionRow(description: String, singleLine: Boolean, onClick: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                .clickable(onClick = onClick)
                .testTag(TestID.Transaction.descriptionButton),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        ) {
            Text(HomeStrings.DESCRIPTION, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis)
            Text(
                text = description,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.End,
                maxLines = if (singleLine) 1 else Int.MAX_VALUE,
                overflow = if (singleLine) TextOverflow.MiddleEllipsis else TextOverflow.Clip,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = BittrTokens.Spacing.md)
                    .testTag(TestID.Transaction.descriptionLabel),
            )
        }
    }
}

/** A detail row that explains itself when tapped. The tap layer sits under the labels so they stay readable to the flows. */
@Composable
private fun TappableRow(title: String, value: String, testTag: String?, onClick: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(MaterialTheme.colorScheme.surfaceContainerLowest, RoundedCornerShape(8.dp))
                .clickable(onClick = onClick)
                .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.md),
        ) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = BittrTheme.colors.emphasis, modifier = Modifier.weight(1f))
            Text(text = value, style = MaterialTheme.typography.bodyLarge)
            Text(" ⓘ", style = MaterialTheme.typography.bodyLarge, color = BittrTheme.colors.emphasis)
        }
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

/** `SPConfetti.startAnimating(…, duration: 2)`. */
private const val CONFETTI_MILLIS = 2_000
private const val HEART_COUNT = 40
