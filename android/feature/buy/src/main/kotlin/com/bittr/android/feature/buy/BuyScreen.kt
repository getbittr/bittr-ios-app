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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bittr.android.core.designsystem.rememberStrokeIcon
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
import androidx.compose.foundation.layout.RowScope
import com.bittr.android.core.designsystem.BittrHelpButton
import com.bittr.android.core.designsystem.BittrCopyButton
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.CompositionLocalProvider
import com.bittr.android.core.designsystem.BittrDialogTitle
import com.bittr.android.core.designsystem.BittrDialogValue
import com.bittr.android.core.designsystem.BittrDialogMessage
import com.bittr.android.core.designsystem.BittrDialogButtonHeight
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
    val scope = rememberCoroutineScope()
    // Onboarding opens on the IBAN page before the first frame, so the page that slides in from
    // Signup7 is Transfer1 rather than an empty canvas that fills in once the effect below runs.
    val controller = remember(source) {
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
            signup?.let { SignupLayers(it, controller, onOpenArticle, onboarding = true) }
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

/** `IbanCollectionViewCell`. */
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
    BittrCard(modifier = modifier, horizontalAlignment = Alignment.Start) {
        DetailRow(BuyStrings.YOUR_EMAIL, entity.yourEmail, valueTag = TestID.Buy.yourEmail)
        DetailRow(BuyStrings.YOUR_IBAN, entity.yourIbanNumber, valueTag = TestID.Buy.yourIban)
        DetailRow(BuyStrings.OUR_IBAN, entity.ourIbanNumber, onCopy = { onCopy(entity.ourIbanNumber) })
        DetailRow(BuyStrings.OUR_NAME, entity.ourName, onCopy = { onCopy(entity.ourName) })
        DetailRow(BuyStrings.YOUR_CODE, entity.yourUniqueCode, valueTag = TestID.Buy.yourCode, onCopy = { onCopy(entity.yourUniqueCode) })
        DetailRowSurface {
            Image(
                imageVector = rememberStrokeIcon(BittrIconPaths.BOLT, MaterialTheme.colorScheme.onSurface, strokeWidth = 2f),
                contentDescription = null,
                modifier = Modifier
                    .padding(end = 8.dp)
                    .size(18.dp),
            )
            Text(BuyStrings.LIGHTNING, style = MaterialTheme.typography.labelLarge)
            BittrHelpButton(
                onClick = onQuestion,
                modifier = Modifier.testTag(TestID.Buy.paymentModeButton),
            )
            Box(Modifier.weight(1f))
            if (pending) {
                BittrSpinner(
                    strokeWidth = 2.dp,
                    modifier = Modifier
                        .padding(end = BittrTokens.Spacing.sm)
                        .size(18.dp),
                )
            }
            Switch(
                checked = lightningOn,
                onCheckedChange = onToggle,
                enabled = !pending,
                colors = bittrSwitchColors(),
                modifier = Modifier
                    .padding(end = 12.dp)
                    .testTag(TestID.Buy.paymentModeSwitch),
            )
        }
    }
}

/**
 * A label and a value on a white row, with a copy button at the row's end when [onCopy] is
 * given (review S4: the "Copy" text button was pale yellow on the yellow card and could not be
 * seen). The copy control is a sibling of the value rather than a layer over it, so the value
 * keeps its own id.
 *
 * The label stays [BittrColors.rowLabel] rather than the proposal's `#EFA900`: that yellow is
 * about 2 : 1 on white, and `rowLabel` is the darkened one signed off for exactly this (DEV-40).
 */
@Composable
internal fun DetailRow(
    label: String,
    value: String,
    valueTag: String? = null,
    onCopy: (() -> Unit)? = null,
    copyTag: String? = null,
) {
    DetailRowSurface {
        Column(Modifier.weight(1f)) {
            Text(
                label,
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = BittrTheme.colors.rowLabel,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                modifier = valueTag?.let { Modifier.testTag(it) } ?: Modifier,
            )
        }
        if (onCopy != null) {
            BittrCopyButton(
                onClick = onCopy,
                modifier = copyTag?.let { Modifier.testTag(it) } ?: Modifier,
            )
        }
    }
}

/** The white 64 dp row [DetailRow] and the Lightning toggle sit on, 8 dp apart. */
@Composable
private fun DetailRowSurface(content: @Composable RowScope.() -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(vertical = 4.dp)
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, BittrCanvasShapes.field)
            .padding(start = 16.dp, end = 4.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            content()
        }
    }
}

/**
 * `AlertManager.showAlert`, drawn in the screen's own window. A dialog window would put the
 * alert where Maestro does not look — see `BittrInlineAlert`. Its own card rather than that
 * one because the message carries markup and the buttons carry [BuyAction]s; the look is the
 * design system's dialog, piece by piece.
 */
@Composable
internal fun BuyAlertCard(alert: BuyAlert, onAction: (BuyAction) -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.45f))
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.xl)
                .fillMaxWidth()
                .background(BittrTheme.colors.dialogContainer, BittrCanvasShapes.card)
                .then(alert.id?.let { Modifier.testTag(it) } ?: Modifier)
                .padding(24.dp),
        ) {
            CompositionLocalProvider(LocalContentColor provides BittrTheme.colors.onDialogContainer) {
                if (alert.title.isNotEmpty()) BittrDialogTitle(alert.title)
                // "Copied" echoes the value (review S19); everything else is a sentence.
                if (alert.id == TestID.Alert.copied) BittrDialogValue(alert.message) else BittrDialogMessage(bittrMarkup(alert.message))
            }
            alert.buttons.forEachIndexed { position, button ->
                val tag = Modifier
                    .fillMaxWidth()
                    .testTag(TestID.Alert.buttonAt(position))
                val quiet = alert.buttons.size > 1 && position == 0 &&
                    (button.action == BuyAction.Dismiss || button.action == BuyAction.CancelLoading)
                if (quiet) {
                    TextButton(onClick = { onAction(button.action) }, modifier = tag) {
                        Text(
                            button.label,
                            style = MaterialTheme.typography.labelLarge,
                            color = BittrTheme.colors.onDialogContainer,
                        )
                    }
                } else {
                    BittrPrimaryButton(
                        text = button.label,
                        onClick = { onAction(button.action) },
                        modifier = tag.height(BittrDialogButtonHeight),
                        arrow = false,
                        fullWidth = true,
                    )
                }
            }
        }
    }
}

/** `showConfirmationSheet` for the exclusive-initiative confirmation (`Transfer1ViewController:175`). */
@Composable
private fun InitiativeSheet(onConfirm: () -> Unit, onCancel: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.45f))
            .pointerInput(Unit) { detectTapGestures { } },
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
