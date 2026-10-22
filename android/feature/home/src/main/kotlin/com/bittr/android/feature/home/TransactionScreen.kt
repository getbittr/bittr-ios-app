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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.SYSTEM_CONFIRMS_COPY
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrIconPaths
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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.Gilroy
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.BittrSheetHeader
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.drawscope.Stroke

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
        // The last prices Home read stand in until the live ones land, so a payout summary opened
        // the moment the payment arrives doesn't show a current value and profit of 0.00.
        price.value = cache.cached.value?.price(prices.currentSymbol())
        viewModelScope.launch { prices.current()?.let { price.value = it } }
        viewModelScope.launch {
            purchases.purchases.map { it[id]?.currency }.distinctUntilChanged().collect { currency ->
                purchasePrice.value = currency?.let { cachedPricePerBitcoin(it) }
                purchasePrice.value = currency?.let { purchases.pricePerBitcoin(it) ?: cachedPricePerBitcoin(it) }
            }
        }
    }

    /** The cached price for a purchase's currency code; the cache keys prices by display symbol. */
    private fun cachedPricePerBitcoin(currencyCode: String): Double? =
        cache.cached.value?.price(if (currencyCode == "EUR") "€" else currencyCode)?.pricePerBitcoin

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
    val clipboard = rememberTextClipboard()
    var copied by remember { mutableStateOf<String?>(null) }
    var editingNote by remember { mutableStateOf(false) }
    // `bittrFeesTapped`: a fee's explanation, as (title, body).
    var feeExplanation by remember { mutableStateOf<Pair<String, String>?>(null) }

    copied?.let {
        BittrAlertDialog(
            title = HomeStrings.COPIED,
            message = it,
            messageIsValue = true,
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

    // As `TransactionViewController` lays it out: `addHeader` with the piggy over `mainCenterView`,
    // centred in the whole sheet — for a bittr payout the piggy and "Good job", then `yellowCard` 15
    // in with 13 corners and the shadow, then the reminder.
    Box(modifier = modifier) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(BittrTheme.colors.canvas)
                .dismissOnPullDown(onDown),
        ) {
            val sheetHeight = maxHeight
            // The hearts fall behind the cards, not over the figures (review, `buy_more/05`).
            Box(modifier = Modifier.fillMaxSize()) {
                if (detail?.confetti == true) {
                    HeartsConfetti(modifier = Modifier.matchParentSize())
                }
                Column(
                    verticalArrangement = Arrangement.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .heightIn(min = sheetHeight)
                        // The header's 58 above, and as much below so the block centres on the sheet,
                        // clear of the gesture bar.
                        .padding(horizontal = 15.dp, vertical = 58.dp)
                        .navigationBarsPadding(),
                ) {
                    val shown = detail ?: return@Column
                    fun copy(text: String) {
                        clipboard.copy(text)
                        // Android 13 and up show their own clipboard confirmation; below it,
                        // this alert is the only feedback there is. See SYSTEM_CONFIRMS_COPY.
                        if (!SYSTEM_CONFIRMS_COPY) copied = text
                    }
                    if (shown.confetti) {
                        PayoutHeader()
                    }
                    // `yellowCard`: the date, then the rows 10 in and 10 apart. The date's band and, at the
                    // bottom, "Add a note"'s are both 55 from the card's edge to the nearest row, as on
                    // iOS, with each label centred in its band — iOS sets the date 8 from its band's
                    // bottom and "Add a note" 6 below its row's middle, both off-centre (Tom, 2026-10-06).
                    val addNoteLast = !shown.confetti && shown.note == null
                    BittrCard(
                        fill = BittrTheme.colors.levelCard,
                        // "Add a note" is 45 tall and the column's 10 above it make its 55.
                        contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = if (addNoteLast) 0.dp else 10.dp),
                        modifier = Modifier.testTag(TestID.Transaction.yellowCard),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            // 45 here and the column's 10 make the 55 band; the offset centres the date on it.
                            Box(
                                contentAlignment = Alignment.Center,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(45.dp)
                                    .offset(y = 5.dp),
                            ) {
                                Text(
                                    text = shown.date,
                                    style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
                                    color = MaterialTheme.colorScheme.onSurface,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag(TestID.Transaction.labelDate),
                                )
                            }
                            DetailRow(HomeStrings.AMOUNT, shown.amount, valueTag = TestID.Transaction.labelAmount)
                            if (!shown.confetti) {
                                DetailRow(HomeStrings.TYPE, shown.type, bolt = shown.typeBolt)
                            }
                            // `swapStack` comes before the fees in the storyboard, as one card.
                            shown.swap?.let { swap ->
                                SwapCard(
                                    swapId = swap.swapIdLabel,
                                    status = swap.status,
                                    onClick = swap.boltzId?.let { boltzId -> { onOpenSwapStatus(boltzId) } },
                                )
                            }
                            shown.fees?.let { DetailRow(HomeStrings.FEES_PAID, it) }
                            shown.confirmations?.let { DetailRow(HomeStrings.CONFIRMATIONS, it) }
                            // `descriptionStack` sits between Confirmations and the ids in the card (Main.storyboard).
                            shown.description?.let { description ->
                                DescriptionRow(
                                    description = description,
                                    singleLine = shown.bittr != null,
                                    onClick = { copy(description) },
                                )
                            }
                            if (!shown.confetti) {
                                val swap = shown.swap
                                val bottomId = swap?.bottomId.orEmpty()
                                IdCard(
                                    top = IdLine(
                                        title = shown.idTitle,
                                        id = shown.id,
                                        onCopy = { copy(shown.id) },
                                        copyTag = TestID.Transaction.copyIdButton,
                                        onExplorer = shown.explorerId?.let { explorerId -> { onOpenExplorer(explorerId) } },
                                        explorerTag = TestID.Transaction.urlIdButton,
                                    ),
                                    bottom = swap?.bottomIdTitle?.let { title ->
                                        IdLine(
                                            title = title,
                                            id = bottomId,
                                            onCopy = if (swap.bottomIdCopyable) ({ copy(bottomId) }) else null,
                                            copyTag = TestID.Transaction.copyBottomIdButton,
                                            onExplorer = swap.bottomExplorerId?.let { explorerId -> { onOpenExplorer(explorerId) } },
                                            explorerTag = null,
                                        )
                                    },
                                )
                            }
                            shown.currentValue?.let { DetailRow(HomeStrings.CURRENT_VALUE, it) }
                            shown.bittr?.let { bittr ->
                                BittrSection(bittr = bittr, onExplain = { title, body -> feeExplanation = title to body })
                            }
                            // `noteStack` / `addANoteStack`, the card's last rows. The payout summary
                            // offers no note (`addANoteStack` hidden under `showConfetti`).
                            if (!shown.confetti) {
                                val note = shown.note
                                if (note != null) {
                                    Box(modifier = Modifier.bringIntoViewRequester(noteRequester)) {
                                        TextRow(
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
                                    AddNoteRow(onClick = { editingNote = true })
                                }
                            }
                        }
                    }
                    if (shown.confetti) {
                        ReminderCard()
                    }
                }
            }
        }

        BittrSheetHeader(
            icon = painterResource(R.drawable.home_piggy_white),
            title = HomeStrings.TRANSACTION,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
    }
}

/**
 * `bittrPayoutStack`: `bittrpiggy2` at 150 by 100, and 25 under it "Good job, …" in Gilroy-Bold 16,
 * 40 in, with 30 to the card.
 */
@Composable
private fun PayoutHeader() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 30.dp),
    ) {
        Image(
            painter = painterResource(R.drawable.bittr_piggy),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(width = 150.dp, height = 100.dp),
        )
        Spacer(Modifier.height(25.dp))
        Text(
            text = HomeStrings.GOOD_JOB,
            style = RowStyle.copy(lineHeight = 16.4.sp),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 25.dp),
        )
    }
}

/**
 * `alertStack`: 20 under the card, `whiteorblue2` with 13 corners and the shadow; "Reminder" in yellow
 * Gilroy-Bold 16 18 from the top, and 7 under it the reminder in Regular 15, both centred, 20 in.
 */
@Composable
private fun ReminderCard() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .padding(top = 20.dp)
            .fillMaxWidth()
            .iosShadow(IosCardShape)
            .background(MaterialTheme.colorScheme.surfaceContainer, IosCardShape)
            .padding(start = 20.dp, end = 20.dp, top = 17.dp, bottom = 16.dp),
    ) {
        Text(HomeStrings.REMINDER, style = RowStyle, color = BittrTheme.colors.brandFixed, textAlign = TextAlign.Center)
        Spacer(Modifier.height(7.dp))
        Text(
            HomeStrings.REMINDER_BODY,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 15.6.sp),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * `bittrFeesStack`: one card — `whiteorblue3` with 8 corners — of 28 pt lines 15 in, the title in
 * yellow and the figure in black or white on each. Received, the surcharge when there is one, the bittr
 * fee and the transfer fee, then a 70 by 2 sum line at the right and, 9 under it, purchase value,
 * exchange rate, current value and profit. The surcharge and the two fees carry a question mark and
 * explain themselves when tapped (`bittrFeesTapped`); the fees keep iOS's `bittrFeeButton` and
 * `transferFeeButton` ids.
 */
@Composable
private fun BittrSection(bittr: BittrDetail, onExplain: (String, String) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RowShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(start = 15.dp, end = 15.dp, top = 10.dp, bottom = 7.dp),
    ) {
        FeeLine(HomeStrings.RECEIVED_AT_BITTR, bittr.receivedAtBittr)
        bittr.surcharge?.let { surcharge ->
            FeeLine(HomeStrings.SURCHARGE, surcharge, testTag = null) { onExplain(HomeStrings.SURCHARGE, HomeStrings.SURCHARGE_1) }
        }
        FeeLine(HomeStrings.BITTR_FEE, bittr.bittrFee, testTag = TestID.Transaction.bittrFeeButton) {
            onExplain(HomeStrings.BITTR_FEE, HomeStrings.BITTR_FEE_1)
        }
        FeeLine(HomeStrings.TRANSFER_FEE, bittr.transferFee, testTag = TestID.Transaction.transferFeeButton) {
            onExplain(HomeStrings.TRANSFER_FEE, bittr.transferFeeExplanation)
        }
        Box(
            modifier = Modifier
                .padding(top = 6.dp, bottom = 9.dp)
                .align(Alignment.End)
                .size(width = 70.dp, height = 2.dp)
                .background(MaterialTheme.colorScheme.onSurface, RoundedCornerShape(1.dp)),
        )
        FeeLine(HomeStrings.PURCHASE_VALUE, bittr.purchaseValue)
        FeeLine(HomeStrings.EXCHANGE_RATE, bittr.exchangeRate)
        FeeLine(HomeStrings.CURRENT_VALUE, bittr.currentValue)
        FeeLine(
            HomeStrings.PROFIT,
            bittr.profit,
            valueColor = if (bittr.isLoss) BittrTheme.colors.loss else BittrTheme.colors.profit,
        )
    }
}

/**
 * One 28 pt line of [BittrSection], its labels 6 from its top. With [onClick] the line is a button —
 * the tap layer under the labels, so they keep their place in the tree — and the title has the yellow
 * `questionmark.circle.fill` 8 after it.
 */
@Composable
private fun FeeLine(
    title: String,
    value: String,
    testTag: String? = null,
    valueColor: Color = Color.Unspecified,
    onClick: (() -> Unit)? = null,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 28.dp),
    ) {
        if (onClick != null) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable(role = Role.Button, onClick = onClick)
                    .then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 5.dp, bottom = 5.dp),
        ) {
            RowTitle(title)
            if (onClick != null) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .padding(start = 8.dp)
                        .offset(y = (-1).dp)
                        .size(16.dp)
                        .background(BittrTheme.colors.brandFixed.copy(alpha = 0.8f), CircleShape),
                ) {
                    Text(
                        "?",
                        style = RowStyle.copy(fontSize = 11.sp, lineHeight = 11.sp),
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                text = value,
                style = RowStyle,
                color = if (valueColor == Color.Unspecified) MaterialTheme.colorScheme.onSurface else valueColor,
                textAlign = TextAlign.End,
                modifier = Modifier
                    .padding(start = 15.dp)
                    .offset(y = 1.dp),
            )
        }
    }
}

/** The rows' titles: Gilroy-Bold 16 in yellow, as every title on iOS's transaction card is. */
@Composable
private fun RowTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = RowStyle, color = BittrTheme.colors.brandFixed, modifier = modifier.offset(y = 1.dp))
}

private val RowShape = RoundedCornerShape(8.dp)
private val RowStyle = TextStyle(fontFamily = Gilroy, fontWeight = FontWeight.Bold, fontSize = 16.sp, lineHeight = 18.sp)

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

@Composable
private fun DetailRow(
    title: String,
    value: String,
    valueTag: String? = null,
    bolt: Boolean = false,
    valueColor: Color = Color.Unspecified,
) {
    // `cardAmount` and its siblings: 45 tall, `whiteorblue3` with 8 corners, title and figure in
    // Gilroy-Bold 16, 15 in.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 45.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RowShape)
            .padding(horizontal = 15.dp, vertical = 12.dp),
    ) {
        RowTitle(title, modifier = Modifier.weight(1f))
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
            style = RowStyle,
            color = if (valueColor == Color.Unspecified) MaterialTheme.colorScheme.onSurface else valueColor,
            modifier = Modifier
                .offset(y = 1.dp)
                .then(if (valueTag != null) Modifier.testTag(valueTag) else Modifier),
        )
    }
}

/**
 * `descriptionStack`: "Description" and its text in a row like the others, copied when tapped. A bittr
 * purchase's description (the payout's notification id) is one line, truncated in the middle, as iOS
 * sets it; any other wraps.
 */
@Composable
private fun DescriptionRow(description: String, singleLine: Boolean, onClick: () -> Unit) {
    TextRow(
        title = HomeStrings.DESCRIPTION,
        text = description,
        textTag = TestID.Transaction.descriptionLabel,
        buttonTag = TestID.Transaction.descriptionButton,
        onClick = onClick,
        singleLine = singleLine,
    )
}

/**
 * The Description and Note rows: at least 45 tall, the title 15 in and the text right-aligned 30
 * after it, wrapping, 15 from the end. The whole row is the tap target, drawn under the text so the
 * text keeps its own id (a clickable parent would merge it away).
 */
@Composable
private fun TextRow(
    title: String,
    text: String,
    textTag: String,
    buttonTag: String?,
    onClick: () -> Unit,
    singleLine: Boolean = false,
) {
    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(RowShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .clickable(onClick = onClick)
                .then(if (buttonTag != null) Modifier.testTag(buttonTag) else Modifier),
        )
        Row(
            verticalAlignment = Alignment.Top,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 45.dp)
                .padding(start = 15.dp, end = 15.dp, top = 13.dp, bottom = 12.dp),
        ) {
            RowTitle(title)
            Text(
                text = text,
                style = RowStyle,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.End,
                maxLines = if (singleLine) 1 else Int.MAX_VALUE,
                overflow = if (singleLine) TextOverflow.MiddleEllipsis else TextOverflow.Clip,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 30.dp)
                    .offset(y = 1.dp)
                    .testTag(textTag),
            )
        }
    }
}

/**
 * `addANoteStack`: 45 tall in the card with no plate of its own, `pencil.circle.fill` at 80 % and
 * "Add a note" in Gilroy-Regular 16 6 after it. The card's last row, with the 10 above it its band
 * is 55; the pair sits 5 above the row's middle so it is centred on all of it.
 */
@Composable
private fun AddNoteRow(onClick: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(45.dp)
            .clip(RowShape)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(TestID.Transaction.addNoteButton),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.offset(y = (-5).dp)) {
            Canvas(
                modifier = Modifier
                    .offset(y = (-1.5).dp)
                    .size(16.dp)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
            ) {
                val u = size.width / 16f
                drawCircle(ink.copy(alpha = 0.8f), radius = 8f * u)
                // The pencil, cut out of the disc.
                drawLine(Color.Black, Offset(5f * u, 11f * u), Offset(10.6f * u, 5.4f * u), strokeWidth = 2.4f * u, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
            }
            Text(
                HomeStrings.ADD_A_NOTE,
                style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 16.sp),
                color = ink,
                modifier = Modifier.padding(start = 6.dp),
            )
        }
    }
}

/**
 * `swapStack`: one 77 pt card, "Swap ID" and its id on the first line, "Swap status" and the status on
 * the second, 28 apart, titles in yellow and values in Gilroy-Bold 16; the status has
 * `arrow.right.circle.fill` at 80 % 6 after it when the swap can be opened, drawn at the 13 pt the
 * symbol occupies in its 16 pt frame. `buttonSwapStatus` covers
 * the card on iOS; here the tap layer is drawn under the labels so they stay readable to the flows,
 * and it carries `transaction.swapStatusButton`.
 */
@Composable
private fun SwapCard(swapId: String, status: String, onClick: (() -> Unit)?) {
    val ink = MaterialTheme.colorScheme.onSurface
    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(RowShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
                .testTag(TestID.Transaction.swapStatusButton),
        )
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 15.dp, end = 15.dp, top = 17.dp, bottom = 14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                RowTitle(HomeStrings.SWAP_ID, modifier = Modifier.weight(1f))
                Text(text = swapId, style = RowStyle, color = ink, maxLines = 1, modifier = Modifier.offset(y = 1.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                RowTitle(HomeStrings.SWAP_STATUS, modifier = Modifier.weight(1f))
                Text(text = status, style = RowStyle, color = ink, maxLines = 1, modifier = Modifier.offset(y = 1.dp))
                if (onClick != null) {
                    Canvas(
                        modifier = Modifier
                            .padding(start = 6.dp)
                            .size(13.dp)
                            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
                    ) {
                        val u = size.width / 16f
                        drawCircle(ink.copy(alpha = 0.8f), radius = 8f * u)
                        // The arrow, cut out of the disc.
                        val arrow = Stroke(width = 1.8f * u, cap = StrokeCap.Round)
                        drawLine(Color.Black, Offset(4.5f * u, 8f * u), Offset(11.3f * u, 8f * u), strokeWidth = arrow.width, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
                        drawLine(Color.Black, Offset(8.3f * u, 5f * u), Offset(11.3f * u, 8f * u), strokeWidth = arrow.width, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
                        drawLine(Color.Black, Offset(8.3f * u, 11f * u), Offset(11.3f * u, 8f * u), strokeWidth = arrow.width, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
                    }
                }
            }
        }
    }
}

/** One line of [IdCard]: its title and id, and what tapping it and its explorer link do. */
private class IdLine(
    val title: String,
    val id: String,
    val onCopy: (() -> Unit)?,
    val copyTag: String,
    val onExplorer: (() -> Unit)?,
    val explorerTag: String?,
)

/**
 * `idStack`: one 45 pt row, and for a swap a second line 6 under the first and 7 from the bottom.
 * On each line the yellow title 15 in, the id in Gilroy-Bold 16 right-aligned 20 after it and
 * truncated in the middle — a hash is checked by its two ends (review S29) — and, for an on-chain
 * id, `rectangle.portrait.and.arrow.right.fill` at 80 % in a 22 pt slot 15 from the end. The line up
 * to that slot is its copy button, as on iOS.
 */
@Composable
private fun IdCard(top: IdLine, bottom: IdLine?) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RowShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        if (bottom == null) {
            IdLineRow(top, Modifier.heightIn(min = 45.dp), PaddingValues(top = 13.dp, bottom = 12.dp))
        } else {
            // Two lines 28 apart, 17 from the top and 14 from the bottom: the swap card's spacing, and
            // the 77 pt iOS's two-id card comes to on screen.
            IdLineRow(top, Modifier, PaddingValues(top = 17.dp, bottom = 5.dp))
            IdLineRow(bottom, Modifier, PaddingValues(top = 5.dp, bottom = 14.dp))
        }
    }
}

@Composable
private fun IdLineRow(line: IdLine, modifier: Modifier, padding: PaddingValues) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        Box(modifier = Modifier.weight(1f)) {
            if (line.onCopy != null) {
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clickable(onClickLabel = "Copy", onClick = line.onCopy)
                        .testTag(line.copyTag),
                )
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(padding)
                    .padding(start = 15.dp, end = if (line.onExplorer == null) 15.dp else 0.dp),
            ) {
                RowTitle(line.title)
                Text(
                    text = line.id,
                    style = RowStyle,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.End,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 20.dp)
                        .offset(y = 1.dp),
                )
            }
        }
        if (line.onExplorer != null) {
            ExplorerLink(onClick = line.onExplorer, testTag = line.explorerTag, padding = padding)
        }
    }
}

/**
 * `rectangle.portrait.and.arrow.right.fill` at 80 %, right-aligned in its 22 pt slot 15 from the row's
 * end, level with its id — 1.5 above the label's centre, as the storyboard has it.
 */
@Composable
private fun ExplorerLink(onClick: () -> Unit, testTag: String?, padding: PaddingValues) {
    val ink = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
    Box(
        contentAlignment = Alignment.CenterEnd,
        modifier = Modifier
            .padding(end = 15.dp)
            // As tall as its line: 45 for one id, the line's own height for two.
            .width(22.dp)
            .fillMaxHeight()
            .clickable(role = Role.Button, onClickLabel = "Open in explorer", onClick = onClick)
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
            // The line's own padding, so the icon centres on the id beside it rather than on the
            // line's whole height (whose padding differs above and below on a two-id card).
            .padding(padding),
    ) {
        Canvas(
            modifier = Modifier
                .offset(y = (-0.5).dp)
                .size(16.dp)
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
        ) {
            val u = size.width / 16f
            // The page, with the arrow's shaft cut out of it, and the arrow carrying on to the right.
            drawRoundRect(ink, Offset(1f * u, 1f * u), Size(8.5f * u, 14f * u), CornerRadius(1.8f * u))
            drawLine(Color.Black, Offset(5f * u, 8f * u), Offset(9.5f * u, 8f * u), strokeWidth = 1.8f * u, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
            drawLine(ink, Offset(9.5f * u, 8f * u), Offset(14.8f * u, 8f * u), strokeWidth = 1.6f * u, cap = StrokeCap.Round)
            drawLine(ink, Offset(12.3f * u, 5.5f * u), Offset(14.8f * u, 8f * u), strokeWidth = 1.6f * u, cap = StrokeCap.Round)
            drawLine(ink, Offset(12.3f * u, 10.5f * u), Offset(14.8f * u, 8f * u), strokeWidth = 1.6f * u, cap = StrokeCap.Round)
        }
    }
}


/** `SPConfetti.startAnimating(…, duration: 2)`. */
private const val CONFETTI_MILLIS = 1_500
private const val HEART_COUNT = 40
