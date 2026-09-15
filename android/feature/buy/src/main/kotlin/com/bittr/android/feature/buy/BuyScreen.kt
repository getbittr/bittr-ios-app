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
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCard
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrPrimaryButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.bittrMarkup
import com.bittr.android.core.designsystem.bittrSwitchColors
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
) {
    val scope = rememberCoroutineScope()
    val controller = remember(source) { BuyController(source, scope) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        controller.onNotificationPermissionResult(granted)
    }

    LaunchedEffect(controller) {
        controller.start()
        if (onboarding) controller.onStartSignupAtIban()
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
        if (signup == null) {
            if (!onboarding) BuyCards(state = state, controller = controller, onDown = onDown)
        } else {
            SignupContainer(signup = signup, controller = controller)
            if (signup.showInitiative) {
                InitiativeSheet(onConfirm = controller::onInitiativeConfirm, onCancel = controller::onInitiativeCancel)
            }
        }
        state.alert?.let { alert -> BuyAlertCard(alert = alert, onAction = controller::onAlertAction) }
    }
}

@Composable
private fun BuyCards(state: BuyUiState, controller: BuyController, onDown: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    BittrCanvas(appBar = false) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BittrModalHeader(
                title = BuyStrings.BUY_BITCOIN,
                onDown = onDown,
                titleTestTag = TestID.Buy.headerLabel,
                downTestTag = TestID.Buy.downButton,
                modifier = Modifier.weight(1f),
            )
        }
        if (state.refreshing) {
            CircularProgressIndicator(
                strokeWidth = 2.dp,
                color = LocalContentColor.current,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(20.dp),
            )
        }

        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
        ) {
            if (state.cards.isEmpty()) {
                BittrCard(modifier = Modifier.padding(horizontal = BittrTokens.Spacing.md)) {
                    BittrBody(BuyStrings.BUY_EMPTY)
                    CanvasSpacer(BittrTokens.Spacing.md)
                    BittrBody(BuyStrings.BUY_SUBTITLE)
                    CanvasSpacer(BittrTokens.Spacing.xl)
                    BittrPrimaryButton(
                        text = BuyStrings.CONTINUE,
                        onClick = controller::onStartSignup,
                        modifier = Modifier.testTag(TestID.Buy.continueButton),
                    )
                }
            } else {
                BittrBody(
                    BuyStrings.BUY_SUBTITLE,
                    modifier = Modifier.padding(horizontal = BittrTokens.Spacing.lg),
                )
                CanvasSpacer(BittrTokens.Spacing.lg)
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val cardWidth = maxWidth - 30.dp
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
                                    clipboard.setText(AnnotatedString(value))
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
    }
}

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
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp),
        ) {
            Text(BuyStrings.LIGHTNING, style = MaterialTheme.typography.labelLarge)
            TextButton(onClick = onQuestion, modifier = Modifier.testTag(TestID.Buy.paymentModeButton)) {
                Text("?", fontWeight = FontWeight.Bold)
            }
            Box(Modifier.weight(1f))
            if (pending) {
                CircularProgressIndicator(
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
                modifier = Modifier.testTag(TestID.Buy.paymentModeSwitch),
            )
        }
    }
}

/**
 * A label and a value, with a copy control beside the value when [onCopy] is given. The copy
 * control is a sibling of the value rather than a layer over it, so the value keeps its own id.
 */
@Composable
internal fun DetailRow(
    label: String,
    value: String,
    valueTag: String? = null,
    onCopy: (() -> Unit)? = null,
    copyTag: String? = null,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = BittrTokens.Spacing.xs),
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = BittrTheme.colors.rowLabel)
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge,
                modifier = valueTag?.let { Modifier.testTag(it) } ?: Modifier,
            )
        }
        if (onCopy != null) {
            TextButton(
                onClick = onCopy,
                modifier = copyTag?.let { Modifier.testTag(it) } ?: Modifier,
            ) {
                Text("Copy")
            }
        }
    }
}

/**
 * `AlertManager.showAlert`, drawn in the screen's own window. A dialog window would put the
 * alert where Maestro does not look — see `BittrInlineAlert` — and this one also needs the
 * card id (`alert.copied`, `alert.resendCode`, …) that the design-system alert does not take.
 */
@Composable
internal fun BuyAlertCard(alert: BuyAlert, onAction: (BuyAction) -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f))
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.md),
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.xl)
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(28.dp))
                .then(alert.id?.let { Modifier.testTag(it) } ?: Modifier)
                .padding(BittrTokens.Spacing.xl),
        ) {
            if (alert.title.isNotEmpty()) {
                Text(
                    text = alert.title,
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Text(
                text = bittrMarkup(alert.message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            alert.buttons.forEachIndexed { position, button ->
                val tag = Modifier
                    .fillMaxWidth()
                    .testTag(TestID.Alert.buttonAt(position))
                val quiet = alert.buttons.size > 1 && position == 0 &&
                    (button.action == BuyAction.Dismiss || button.action == BuyAction.CancelLoading)
                if (quiet) {
                    TextButton(onClick = { onAction(button.action) }, modifier = tag) {
                        Text(button.label, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    BittrPrimaryButton(
                        text = button.label,
                        onClick = { onAction(button.action) },
                        modifier = tag,
                        arrow = false,
                        compact = true,
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
            .background(Color.Black.copy(alpha = 0.4f))
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.lg, vertical = BittrTokens.Spacing.xxl)
                .fillMaxWidth()
                .background(BittrTheme.colors.cardWash, RoundedCornerShape(28.dp))
                .testTag(TestID.Alert.exclusiveInitiative)
                .padding(BittrTokens.Spacing.xl),
        ) {
            Text(
                BuyStrings.INITIATIVE_TITLE,
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.fillMaxWidth(),
            )
            CanvasSpacer(BittrTokens.Spacing.md)
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState()),
            ) {
                Text(BuyStrings.INITIATIVE_MESSAGE, style = MaterialTheme.typography.bodyMedium)
            }
            CanvasSpacer(BittrTokens.Spacing.lg)
            BittrPrimaryButton(
                text = BuyStrings.INITIATIVE_CONFIRM,
                onClick = onConfirm,
                arrow = false,
                modifier = Modifier.testTag(TestID.Signup.Bittr.Initiative.confirmButton),
            )
            TextButton(
                onClick = onCancel,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(TestID.Signup.Bittr.Initiative.cancelButton),
            ) {
                Text(BuyStrings.CANCEL)
            }
        }
    }
}

/** Clears focus when tapped — iOS's `backgroundButtonTapped`, which the flows use to drop the keyboard. */
internal fun Modifier.tapToClearFocus(clear: () -> Unit): Modifier =
    pointerInput(Unit) { detectTapGestures { clear() } }
