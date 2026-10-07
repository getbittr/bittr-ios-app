package com.bittr.android.feature.buy

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bittr.android.core.designsystem.rememberRetained
import com.bittr.android.core.designsystem.rememberTextClipboard
import com.bittr.android.core.designsystem.BittrIconPaths
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrSpinner
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.CompositionLocalProvider
import com.bittr.android.core.designsystem.BittrDialogTitle
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrInlineAlert
import com.bittr.android.core.designsystem.BittrDialogMessage
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.bittrMarkup
import com.bittr.android.core.designsystem.bittrSwitchColors
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.focusable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.designsystem.BittrSheet
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.Gilroy
import com.bittr.android.core.network.IbanEntity
import com.bittr.android.core.permissions.BittrPermissions
import androidx.compose.foundation.Canvas
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import com.bittr.android.core.designsystem.rememberFillIcon

/**
 * Buy — `BuyViewController`, and the signup container it opens over itself.
 *
 * One destination rather than two: iOS presents `RegisterIbanViewController` modally over Buy
 * and dismisses back to it, and the flows expect `buy.yourCode` the moment the last signup alert
 * is gone. Holding the container as state here is what gives that without a back-stack round trip.
 */
@Composable
fun BuyRoute(
    source: BuySource,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    // Onboarding's bittr signup (`SignupViewController` pages 10–13): opens on the IBAN page and
    // leaves through [onDown] whenever the signup closes, instead of showing the Buy cards.
    onboarding: Boolean = false,
    /** A signup page's article card was tapped (`launchArticle(articleTag:)`). */
    onOpenArticle: (String) -> Unit = {},
) {
    // Onboarding opens on the IBAN page before the first frame, so the page that slides in from
    // Signup7 is Transfer1 rather than an empty canvas that fills in once the effect below runs.
    // Kept on the back-stack entry, not this composition, so a signup left for its email code is
    // still there on return — see [rememberRetained].
    val controller = rememberRetained("buy") { scope ->
        BuyController(source, scope).also { if (onboarding) it.onStartSignupAtIban() }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        controller.onNotificationPermissionResult(granted)
    }

    LaunchedEffect(controller) {
        controller.start()
        controller.effects.collect { effect ->
            when (effect) {
                BuyEffect.RequestNotificationPermission ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        permission.launch(BittrPermissions.NOTIFICATIONS)
                    } else {
                        controller.onNotificationPermissionResult(source.notificationsAuthorized())
                    }
            }
        }
    }

    val state by controller.state.collectAsState()
    BackHandler(enabled = state.signup != null) { controller.onCloseSignup() }

    if (onboarding) {
        // Done, "Go to wallet", Back or the header's down button all end the signup; in
        // onboarding that is the way into the wallet.
        var signupShown by remember { mutableStateOf(false) }
        LaunchedEffect(state.signup == null) {
            if (state.signup != null) signupShown = true else if (signupShown) onDown()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        val signup = state.signup
        if (onboarding) {
            // The last page stays on as the signup leaves, as `hideSignup` slides it up to Home with
            // the rest of SignupViewController. Drawn only while the signup was open, the page went
            // the moment Done or "Go to wallet" closed it, and the destination slid up empty.
            var presented by remember { mutableStateOf<SignupUiState?>(null) }
            if (signup != null && presented != signup) presented = signup
            presented?.let { SignupLayers(it, controller, onOpenArticle, onboarding = true) }
            state.alert?.let { alert -> BuyAlertCard(alert = alert, onAction = controller::onAlertAction) }
        } else {
            BuyCards(state = state, controller = controller, onDown = onDown)
            if (signup == null) {
                state.alert?.let { alert -> BuyAlertCard(alert = alert, onAction = controller::onAlertAction) }
            }
            SignupSheet(state = state, controller = controller, onOpenArticle = onOpenArticle)
        }
    }
}

/**
 * The signup container over Buy — `BuyToRegister`, a modal segue from a page sheet, so a second
 * page sheet rising over the first. It holds the last signup while it slides down, and a close
 * from the sheet itself (Back) closes the signup in the controller once it is down.
 *
 * Its alerts are drawn inside it: in Buy's window they would sit under the sheet.
 */
@Composable
private fun SignupSheet(
    state: BuyUiState,
    controller: BuyController,
    onOpenArticle: (String) -> Unit,
) {
    val signup = state.signup
    var presented by remember { mutableStateOf<SignupUiState?>(null) }
    if (signup != null && presented != signup) presented = signup
    val shown = presented ?: return

    Dialog(onDismissRequest = {}, properties = SheetDialog) {
        BittrSheet(
            onDismissed = {
                presented = null
                if (controller.state.value.signup != null) controller.onCloseSignup()
            },
        ) { dismiss ->
            // Done, "Go to wallet" or the header's down button closed it in the controller.
            LaunchedEffect(signup == null) { if (signup == null) dismiss() }
            Box(Modifier.fillMaxSize()) {
                SignupLayers(shown, controller, onOpenArticle, onboarding = false)
                if (signup != null) {
                    state.alert?.let { alert -> BuyAlertCard(alert = alert, onAction = controller::onAlertAction) }
                }
            }
        }
    }
}

@Composable
private fun SignupLayers(
    signup: SignupUiState,
    controller: BuyController,
    onOpenArticle: (String) -> Unit,
    onboarding: Boolean,
) {
    SignupContainer(
        signup = signup,
        controller = controller,
        onOpenArticle = onOpenArticle,
        onboarding = onboarding,
    )
    if (signup.showInitiative) {
        InitiativeSheet(onConfirm = controller::onInitiativeConfirm, onCancel = controller::onInitiativeCancel)
    }
}

/** Edge to edge, with the window's own dim, animation and Back handling left to [BittrSheet]. */
private val SheetDialog = DialogProperties(
    usePlatformDefaultWidth = false,
    decorFitsSystemWindows = false,
    dismissOnBackPress = false,
    dismissOnClickOutside = false,
)

/**
 * `BuyViewController`: the sheet header over a block centred in the whole sheet — the subtitle
 * 40 in, then 30 below it either the IBAN cards or, with none yet, the bold empty label and 25
 * under that the 200 × 45 black "Check options" button with 13 corners. The labels sit straight
 * on the canvas at Gilroy's own line height, as a UILabel sets them.
 */
@Composable
private fun BuyCards(state: BuyUiState, controller: BuyController, onDown: () -> Unit) {
    val clipboard = rememberTextClipboard()
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown),
    ) {
        val sheetHeight = maxHeight
        val cardWidth = maxWidth - 30.dp
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            Column(
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = sheetHeight)
                    .padding(vertical = 58.dp),
            ) {
                Text(
                    text = BuyStrings.BUY_SUBTITLE,
                    style = BuyLabel,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 40.dp),
                )
                CanvasSpacer(30.dp)
                if (state.cards.isEmpty()) {
                    Text(
                        text = BuyStrings.BUY_EMPTY,
                        style = BuyLabel.copy(fontWeight = FontWeight.Bold, lineHeight = 16.4.sp),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 40.dp),
                    )
                    CanvasSpacer(25.dp)
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(width = 200.dp, height = 45.dp)
                            .clip(RoundedCornerShape(13.dp))
                            .background(Color.Black)
                            .clickable(role = Role.Button, onClick = controller::onStartSignup)
                            .testTag(TestID.Buy.continueButton),
                    ) {
                        Text(
                            text = BuyStrings.CHECK_OPTIONS,
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp),
                            color = Color.White,
                            modifier = Modifier.offset(y = 1.dp),
                        )
                    }
                } else {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 15.dp),
                    ) {
                        items(state.cards, key = { it.id }) { entity ->
                            IbanCard(
                                entity = entity,
                                lightningOn = state.lightningOn(entity),
                                pending = entity.id in state.pendingModes,
                                onCopy = { value ->
                                    clipboard.copy(value)
                                    controller.showCopied(value)
                                },
                                onQuestion = controller::onPaymentModeQuestion,
                                onToggle = { on -> controller.onPaymentModeToggled(entity, on) },
                                modifier = Modifier.width(cardWidth),
                            )
                        }
                    }
                }
            }
        }

        Column(Modifier.fillMaxWidth()) {
            BittrSheetHeader(
                icon = painterResource(R.drawable.buy_header_piggy),
                title = BuyStrings.BUY_BITCOIN,
                onDown = onDown,
                titleTestTag = TestID.Buy.headerLabel,
                downTestTag = TestID.Buy.downButton,
            )
            if (state.refreshing) {
                BittrSpinner(
                    strokeWidth = 2.dp,
                    color = BittrTheme.colors.homeCardTitle,
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .size(20.dp),
                )
            }
        }
    }
}

/**
 * The subtitle's Gilroy-Regular 16 at the 20.8 pt line pitch it has on iOS — the scale's
 * `bodyLarge` spaces it at 24. The empty label's Bold is tighter still, 16.4, off the same
 * screenshot.
 */
private val BuyLabel = TextStyle(
    fontFamily = Gilroy,
    fontWeight = FontWeight.Normal,
    fontSize = 16.sp,
    lineHeight = 20.8.sp,
)

/**
 * `IbanCollectionViewCell`: `cardBackgroundView` in `yelloworblue2` with 20 corners and the iOS
 * shadow, and in it, 10 in and 10 apart, six 45 pt `whiteorblue3` rows with 13 corners — the five
 * details, then Lightning with its switch.
 */
@Composable
private fun IbanCard(
    entity: IbanEntity,
    lightningOn: Boolean,
    pending: Boolean,
    onCopy: (String) -> Unit,
    onQuestion: () -> Unit,
    onToggle: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    BittrCard(
        modifier = modifier,
        horizontalAlignment = Alignment.Start,
        shape = RoundedCornerShape(20.dp),
        fill = colors.levelCard,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(10.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            DetailRow(BuyStrings.YOUR_EMAIL, entity.yourEmail, valueTag = TestID.Buy.yourEmail)
            DetailRow(BuyStrings.YOUR_IBAN, entity.yourIbanNumber, valueTag = TestID.Buy.yourIban)
            DetailRow(BuyStrings.OUR_IBAN, entity.ourIbanNumber, onCopy = { onCopy(entity.ourIbanNumber) })
            DetailRow(BuyStrings.OUR_NAME, entity.ourName, onCopy = { onCopy(entity.ourName) })
            DetailRow(BuyStrings.YOUR_CODE, entity.yourUniqueCode, valueTag = TestID.Buy.yourCode, onCopy = { onCopy(entity.yourUniqueCode) })
            // `paymentModeView`: the 14 pt yellow bolt 15 in, "Lightning" 5 after it and the question
            // mark 7 after that — the three are `paymentModeButton` — and the switch 15 from the end,
            // its spinner 7 before it while the change is in flight.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(RowHeight)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, RowShape)
                    .padding(end = 15.dp),
            ) {
                Box {
                    // Under the title, not over it, so nothing inside loses its place in the tree.
                    Box(
                        modifier = Modifier
                            .matchParentSize()
                            .clip(RowShape)
                            .clickable(role = Role.Button, onClick = onQuestion)
                            .testTag(TestID.Buy.paymentModeButton),
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(start = 15.dp, end = 10.dp, top = 10.dp, bottom = 10.dp),
                    ) {
                        Image(
                            imageVector = rememberFillIcon(BittrIconPaths.BOLT, colors.brandFixed),
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            BuyStrings.LIGHTNING,
                            style = RowStyle,
                            color = colors.brandFixed,
                            modifier = Modifier
                                .padding(start = 5.dp)
                                .offset(y = 1.dp),
                        )
                        Image(
                            imageVector = rememberFillIcon(BittrIconPaths.HELP, colors.brandFixed),
                            contentDescription = "More information",
                            modifier = Modifier
                                .padding(start = 7.dp)
                                .size(16.dp),
                        )
                    }
                }
                Box(Modifier.weight(1f))
                if (pending) {
                    BittrSpinner(
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier
                            .padding(end = 7.dp)
                            .size(20.dp),
                    )
                }
                Switch(
                    checked = lightningOn,
                    onCheckedChange = onToggle,
                    enabled = !pending,
                    colors = bittrSwitchColors(),
                    modifier = Modifier.testTag(TestID.Buy.paymentModeSwitch),
                )
            }
        }
    }
}

/**
 * One of the card's detail rows: 45 tall, `whiteorblue3` with 13 corners, the title in yellow
 * Gilroy-Bold 16 in a 100 pt column 15 in, and the value in black or white 15 after it. A row
 * with [onCopy] is its own copy button, as on iOS, with `doc.on.doc.fill` at 80 % 15 from the
 * end. The tap layer is under the labels, so the value keeps its own id.
 */
@Composable
internal fun DetailRow(
    label: String,
    value: String,
    valueTag: String? = null,
    onCopy: (() -> Unit)? = null,
    copyTag: String? = null,
) {
    val colors = BittrTheme.colors
    val ink = MaterialTheme.colorScheme.onSurface
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = RowHeight)
            .clip(RowShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        if (onCopy != null) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clickable(role = Role.Button, onClickLabel = "Copy", onClick = onCopy)
                    .then(copyTag?.let { Modifier.testTag(it) } ?: Modifier),
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxWidth()
                .padding(start = 15.dp, end = 15.dp, top = 12.dp, bottom = 12.dp),
        ) {
            Text(
                label,
                style = RowStyle,
                color = colors.brandFixed,
                modifier = Modifier
                    .width(100.dp)
                    .offset(y = 1.dp),
            )
            Text(
                text = value,
                style = RowStyle,
                color = ink,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 15.dp, end = if (onCopy != null) 15.dp else 0.dp)
                    .offset(y = 1.dp)
                    .then(valueTag?.let { Modifier.testTag(it) } ?: Modifier),
            )
            if (onCopy != null) CopySymbol(ink.copy(alpha = 0.8f))
        }
    }
}

/** SF Symbols' `doc.on.doc.fill` at 13 pt: the back page, a gap round the front page, the front page. */
@Composable
private fun CopySymbol(color: Color) {
    Canvas(
        modifier = Modifier
            .size(13.dp)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        val u = size.width / 16f
        drawRoundRect(color, Offset(5.5f * u, 0f), Size(8.5f * u, 11.5f * u), CornerRadius(2f * u))
        drawRoundRect(Color.Black, Offset(1f * u, 3.5f * u), Size(10.5f * u, 12.5f * u), CornerRadius(2.8f * u), blendMode = BlendMode.Clear)
        drawRoundRect(color, Offset(2f * u, 4.5f * u), Size(8.5f * u, 11.5f * u), CornerRadius(2f * u))
    }
}

private val RowHeight = 45.dp
private val RowShape = RoundedCornerShape(13.dp)
private val RowStyle = TextStyle(fontFamily = Gilroy, fontWeight = FontWeight.Bold, fontSize = 16.sp, lineHeight = 18.sp)

/**
 * `AlertManager.showAlert`, drawn in the screen's own window — the shared [BittrInlineAlert], with
 * the alert's id on the card and its [BuyAction]s on the buttons. "Copied" echoes the value
 * (review S19); everything else is a sentence with markup.
 */
@Composable
internal fun BuyAlertCard(alert: BuyAlert, onAction: (BuyAction) -> Unit) {
    BittrInlineAlert(
        title = alert.title,
        message = alert.message,
        buttons = alert.buttons.map { button ->
            BittrAlertButton(
                label = button.label,
                dismissesAlert = button.action == BuyAction.Dismiss || button.action == BuyAction.CancelLoading,
                onClick = { onAction(button.action) },
            )
        },
        cardTestTag = alert.id,
        messageIsValue = alert.id == TestID.Alert.copied,
    )
}

/** `showConfirmationSheet` for the exclusive-initiative confirmation (`Transfer1ViewController:175`). */
@Composable
private fun InitiativeSheet(onConfirm: () -> Unit, onCancel: () -> Unit) {
    // iOS's `nextButtonTapped` ends editing before the sheet goes up. Verify's clearFocus()
    // is not enough here: after a hardware Enter the window is in non-touch mode, and
    // Android hands focus straight back to the IBAN field, whose keyboard then covers the
    // confirm button. The sheet takes focus itself, so no field behind it holds it.
    val sheetFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) {
        runCatching { sheetFocus.requestFocus() }
        keyboard?.hide()
    }
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.45f))
            .pointerInput(Unit) { detectTapGestures { } }
            .focusRequester(sheetFocus)
            .focusable(),
    ) {
        // An opaque dialog, like every other alert. It painted the card wash — white at 9 % —
        // over the signup page, so the page read straight through the sentence the user is
        // being asked to confirm (Ruben, 2026-09-22).
        Column(
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.lg, vertical = BittrTokens.Spacing.xxl)
                .fillMaxWidth()
                .background(BittrTheme.colors.dialogContainer, BittrCanvasShapes.card)
                .testTag(TestID.Alert.exclusiveInitiative)
                .padding(24.dp),
        ) {
            CompositionLocalProvider(LocalContentColor provides BittrTheme.colors.onDialogContainer) {
                BittrDialogTitle(BuyStrings.INITIATIVE_TITLE)
                CanvasSpacer(BittrTokens.Spacing.md)
                Column(
                    Modifier
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState()),
                ) {
                    BittrDialogMessage(BuyStrings.INITIATIVE_MESSAGE)
                }
                CanvasSpacer(BittrTokens.Spacing.lg)
                BittrPrimaryButton(
                    text = BuyStrings.INITIATIVE_CONFIRM,
                    onClick = onConfirm,
                    arrow = false,
                    // A sentence, not a label: the pill grows to hold it.
                    wrapLabel = true,
                    modifier = Modifier.testTag(TestID.Signup.Bittr.Initiative.confirmButton),
                )
                TextButton(
                    onClick = onCancel,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(TestID.Signup.Bittr.Initiative.cancelButton),
                ) {
                    Text(
                        BuyStrings.CANCEL,
                        style = MaterialTheme.typography.labelLarge,
                        color = BittrTheme.colors.onDialogContainer,
                    )
                }
            }
        }
    }
}

/** Clears focus when tapped — iOS's `backgroundButtonTapped`, which the flows use to drop the keyboard. */
internal fun Modifier.tapToClearFocus(clear: () -> Unit): Modifier =
    pointerInput(Unit) { detectTapGestures { clear() } }
