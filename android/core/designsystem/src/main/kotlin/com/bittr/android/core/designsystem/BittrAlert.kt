package com.bittr.android.core.designsystem

import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.RememberObserver
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.runtime.SideEffect
import com.bittr.android.core.common.TestID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * One button on a [BittrAlert]. Position in the list is what numbers its test ID.
 *
 * [dismissesAlert] marks a button that only closes the alert — iOS's `AlertButton.dismiss`.
 * Back and the card's X do what it does, and the X is shown only when there is one.
 */
data class BittrAlertButton(
    val label: String,
    val dismissesAlert: Boolean = false,
    /** Kept for callers; iOS draws a destructive action like any other, and so does this. */
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/**
 * The app's alert — iOS's `AlertManager.showAlert`, drawn as iOS draws it.
 *
 * - **The card:** `yelloworblue2`, 13 corners and the iOS shadow, 10 from the screen's sides,
 *   its bottom on the safe area. It springs up from below the screen in 0.5 s at damping 0.7
 *   while the screen dims to 50 % black, and a button slides it back down in 0.3 s before its
 *   action runs.
 * - **The header:** the bell, 17 pt at 19 from the top and 20 in, and the title lower-cased in
 *   Gilroy-Bold 18, 10 after it, both in `whiteoryellow`; the 14 pt X 20 from the right when a
 *   button only closes the alert.
 * - **The message** 25 under the bell and 20 in: iOS's `attributed()`, Gilroy-Regular 16 at a
 *   1.28 line height, centred, `<b>` bold. It scrolls when the card would otherwise rise past
 *   10 under the safe area's top.
 * - **The buttons** 25 under that, 15 in and 15 from the bottom, 10 apart: side by side for one
 *   or two whose titles are shorter than 16 characters, stacked otherwise, with the first button
 *   at the bottom. Each is at least 40 tall, `white0.7orblue1` at 8 corners with the shadow, its
 *   title Gilroy-Bold 16, wrapping 10 in when it doesn't fit on one line.
 *
 * Two things here are load-bearing for the Maestro suite. **The button ids are applied here, by
 * index** — `alert.button.0`, `alert.button.1`, … from [TestID.Alert.buttonAt], as
 * `AlertManager.swift` does — and **position 0 is the way out**, Cancel-first, as the shared copy
 * orders the pairs. A stacked alert draws that first button at the bottom, as iOS does, and the
 * ids keep the caller's order wherever the button lands.
 *
 * Its own window: a full-screen dialog whose dim and motion are this card's.
 *
 * [identity] is the caller's alert, when it has one: a new one gets its own card even with the same
 * words, rather than the card of one that is sliding away — see [rememberAlertMotion].
 */
@Composable
fun BittrAlert(
    title: String,
    message: String,
    buttons: List<BittrAlertButton>,
    modifier: Modifier = Modifier,
    messageIsValue: Boolean = false,
    valueWraps: Boolean = false,
    identity: Any? = null,
) {
    require(buttons.isNotEmpty()) {
        "A BittrAlert with no buttons cannot be dismissed — it would trap the user on " +
            "the screen underneath it."
    }
    val motion = rememberAlertMotion(AlertIdentity.of(identity), title, message, buttons.map { it.label })
    if (motion.gone) return
    // Out here, in the screen's composition: inside the dialog the focus and keyboard are the
    // dialog window's, not the field's that has the keyboard up.
    CloseKeyboardOnShow(motion)
    Dialog(onDismissRequest = {}, properties = AlertDialogProperties) {
        AlertWindowSetup()
        AlertOverlay(
            motion = motion,
            onBack = buttons.firstOrNull { it.dismissesAlert }?.onClick,
            cardModifier = modifier,
        ) {
            AlertCardContent(
                title = title,
                message = { AlertMessage(message, messageIsValue, valueWraps) },
                buttons = buttons,
                motion = motion,
            )
        }
    }
}

/**
 * [BittrAlert] drawn inside the current window instead of in a dialog window.
 *
 * For a flow that asserts on the screen *behind* the alert while the alert is up. Maestro reads
 * only the focused window, so with a dialog the screen underneath disappears from the hierarchy —
 * `send_onchain.yaml` checks `scanner.scannerView` and `alert.button.0` together, as iOS allows
 * because its alert lives in the same view hierarchy. The same card, buttons and ids; the dim
 * swallows taps meant for the screen beneath, and Back does what the closing button does.
 */
@Composable
fun BittrInlineAlert(
    title: String,
    message: String,
    buttons: List<BittrAlertButton>,
    modifier: Modifier = Modifier,
    // iOS `showAlert(id:)` puts the id on the card — `alert.incomingPayment`, for one.
    cardTestTag: String? = null,
    messageIsValue: Boolean = false,
    valueWraps: Boolean = false,
    // See [BittrAlert].
    identity: Any? = null,
) {
    require(buttons.isNotEmpty()) {
        "A BittrInlineAlert with no buttons cannot be dismissed — it would trap the user on " +
            "the screen underneath it."
    }
    val motion = rememberAlertMotion(AlertIdentity.of(identity), title, message, buttons.map { it.label })
    if (motion.gone) return
    CloseKeyboardOnShow(motion)
    AlertOverlay(
        motion = motion,
        onBack = buttons.firstOrNull { it.dismissesAlert }?.onClick,
        cardModifier = modifier.then(if (cardTestTag != null) Modifier.testTag(cardTestTag) else Modifier),
    ) {
        AlertCardContent(
            title = title,
            message = { AlertMessage(message, messageIsValue, valueWraps) },
            buttons = buttons,
            motion = motion,
        )
    }
}

/**
 * iOS's `showLoading(message:)`: the same card on `whiteorblue3`, with the spinner and the
 * message — Gilroy-Bold 16, `blackorwhite` — side by side, 11 apart and centred, 25 from the
 * card's top and bottom. Nothing on it to tap and no way to dismiss it: the dim swallows taps and
 * Back. Drawn in the current window, so the screen underneath stays in Maestro's view.
 */
@Composable
fun BittrLoadingCard(
    message: String,
    modifier: Modifier = Modifier,
    testTag: String? = null,
) {
    val motion = rememberAlertMotion()
    CloseKeyboardOnShow(motion)
    AlertOverlay(
        motion = motion,
        onBack = {},
        cardColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        cardModifier = modifier.then(if (testTag != null) Modifier.testTag(testTag) else Modifier),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(11.dp, Alignment.CenterHorizontally),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 25.dp, vertical = 25.dp),
        ) {
            BittrSpinner(
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = message,
                style = AlertMessageStyle.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// The chrome every alert shares
// ---------------------------------------------------------------------------

/**
 * The card's motion: 0 below the screen, 1 in place. [close] slides it out, then marks it
 * [gone] — so its window or dim stops catching touches — and only then runs what closed it.
 *
 * Only if this is still the card on screen. The slide takes [AlertCloseMs], and a newer alert can
 * replace this one meanwhile — a push, a status that arrived — which forgets this motion. Run then,
 * the tap would act on that newer alert instead: clear it, or press its button at the same
 * position. The tap belonged to an alert that is gone, so it does nothing.
 */
@Stable
internal class AlertMotion(private val scope: CoroutineScope) : RememberObserver {
    val progress = Animatable(0f)
    var closing by mutableStateOf(false)
        private set
    var gone by mutableStateOf(false)
        private set
    private var current = true

    fun close(after: () -> Unit) {
        if (closing) return
        closing = true
        scope.launch {
            progress.animateTo(0f, tween(AlertCloseMs, easing = FastOutSlowInEasing))
            gone = true
            if (current) after()
        }
    }

    override fun onRemembered() = Unit

    override fun onForgotten() {
        current = false
    }

    override fun onAbandoned() {
        current = false
    }
}

/**
 * A caller's alert as a key, by reference: two alerts with the same words are still two alerts.
 * Null without one, which leaves the card to its words.
 */
internal class AlertIdentity private constructor(private val alert: Any) {
    override fun equals(other: Any?) = other is AlertIdentity && other.alert === alert

    override fun hashCode() = System.identityHashCode(alert)

    companion object {
        fun of(alert: Any?): AlertIdentity? = alert?.let(::AlertIdentity)
    }
}

/**
 * A fresh motion whenever [keys] change: a different alert slides in anew, as iOS rebuilds its card.
 * Without the caller's alert among them, a new alert with the same words as one sliding away
 * would take that card — gone, so never drawn — rather than one of its own.
 */
@Composable
internal fun rememberAlertMotion(vararg keys: Any?): AlertMotion {
    val scope = rememberCoroutineScope()
    return remember(*keys) { AlertMotion(scope) }
}

/**
 * iOS's `view.endEditing(true)` before an alert: the field gives up focus and the keyboard goes
 * down, once per alert. The card sits on the navigation bar, so with the keyboard up it would slide
 * in behind the keyboard and never be seen. [BittrTextFieldAlert] does not call this — its own
 * field wants the keyboard, and its card rides on top of it.
 */
@Composable
internal fun CloseKeyboardOnShow(motion: AlertMotion) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(motion) {
        focus.clearFocus(force = true)
        keyboard?.hide()
    }
}

/** Full screen and edge to edge, with Back and outside taps left to the card. */
internal val AlertDialogProperties = DialogProperties(
    usePlatformDefaultWidth = false,
    decorFitsSystemWindows = false,
    dismissOnBackPress = false,
    dismissOnClickOutside = false,
)

/** Switches off the dialog window's own dim and animation; the card's replace them. */
@Composable
internal fun AlertWindowSetup() {
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
    SideEffect {
        window?.setDimAmount(0f)
        window?.setWindowAnimations(0)
    }
}

/**
 * The dim and the card sliding up inside it. [onBack] is what Back does, after the card has gone
 * down; null leaves Back to whatever is underneath. [bottomInsets] is what the card's bottom sits
 * on — the navigation bar, or the keyboard as well for a text field.
 */
@Composable
internal fun AlertOverlay(
    motion: AlertMotion,
    onBack: (() -> Unit)?,
    cardModifier: Modifier = Modifier,
    cardColor: Color = BittrTheme.colors.levelCard,
    bottomInsets: WindowInsets = WindowInsets.navigationBars,
    content: @Composable ColumnScope.() -> Unit,
) {
    LaunchedEffect(motion) {
        motion.progress.animateTo(1f, spring(dampingRatio = 0.7f, stiffness = AlertStiffness))
    }
    if (onBack != null) BackHandler { motion.close(onBack) }

    val shown = motion.progress.value.coerceIn(0f, 1f)
    // A dialog window is its own semantics root and does not inherit the app's
    // `testTagsAsResourceId`: without this, Maestro sees none of the ids inside.
    Box(Modifier.fillMaxSize().exposeTestTags()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f * shown))
                // Taps on the dim go nowhere, as on iOS.
                .pointerInput(Unit) { detectTapGestures { } },
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .windowInsetsPadding(bottomInsets)
                // A message too long for the screen scrolls instead of pushing the card off the top.
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
                .padding(top = 10.dp)
                .padding(horizontal = 10.dp)
                .fillMaxWidth()
                // Below the screen by its own height and the inset it sits on, until the spring
                // brings it up. The layer's size is known before the first frame is drawn.
                .graphicsLayer {
                    translationY = (1f - motion.progress.value) * (size.height + 200.dp.toPx())
                }
                .iosShadow(IosCardShape)
                .background(cardColor, IosCardShape)
                .clip(IosCardShape)
                .then(cardModifier),
            content = content,
        )
    }
}

/** The header, the message, and the buttons, as `showAlert` lays them out. */
@Composable
internal fun AlertCardContent(
    title: String,
    message: (@Composable () -> Unit)?,
    buttons: List<BittrAlertButton>,
    motion: AlertMotion,
    field: (@Composable () -> Unit)? = null,
) {
    val closer = buttons.firstOrNull { it.dismissesAlert }
    Box(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            Spacer(Modifier.height(19.dp))
            AlertHeader(title)
            if (message != null) {
                Spacer(Modifier.height(25.dp))
                // It takes only the room the header and buttons leave, and scrolls within it.
                // A text field's message stays 40 in, as iOS's showTextFieldAlert has it.
                Box(
                    Modifier
                        .weight(1f, fill = false)
                        .padding(horizontal = if (field != null) 40.dp else 20.dp),
                ) { message() }
            }
            if (field != null) {
                Spacer(Modifier.height(25.dp))
                Box(Modifier.padding(horizontal = 20.dp)) { field() }
                Spacer(Modifier.height(20.dp))
            } else {
                Spacer(Modifier.height(25.dp))
            }
            AlertButtons(buttons, motion, stackable = field == null)
            Spacer(Modifier.height(15.dp))
        }
        if (closer != null && field == null) {
            // The 14 pt X, 20 from the right and level with the bell, in a 40 pt button.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 7.5.dp, end = 7.dp)
                    .size(40.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                    ) { motion.close(closer.onClick) }
                    .semantics { contentDescription = "Close" },
            ) {
                Image(
                    painter = painterResource(R.drawable.alert_close),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(BittrTheme.colors.homeCardTitle),
                    modifier = Modifier.size(14.dp),
                )
            }
        }
    }
}

/** `addAlertHeader`: the bell and the lower-cased title. */
@Composable
private fun AlertHeader(title: String) {
    val tint = BittrTheme.colors.homeCardTitle
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(start = 20.dp, end = 54.dp)
            .height(17.dp),
    ) {
        Image(
            painter = painterResource(R.drawable.alert_bell),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(17.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            text = title.lowercase(),
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp, lineHeight = 18.sp),
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.offset(y = 1.dp),
        )
    }
}

/**
 * The message as iOS's `attributed()` sets it, or a value — a key or an invoice — on one line
 * that gives way in the middle unless [valueWraps]. Scrolls rather than clips when the card runs
 * out of screen, faded at the bottom while there is more below.
 */
@Composable
private fun AlertMessage(message: String, isValue: Boolean, valueWraps: Boolean) {
    val scroll = rememberScrollState()
    val fadeInto = BittrTheme.colors.levelCard
    Text(
        text = if (isValue) AnnotatedString(message) else bittrMarkup(message),
        style = AlertMessageStyle,
        color = MaterialTheme.colorScheme.onSurface,
        textAlign = TextAlign.Center,
        maxLines = if (isValue && !valueWraps) 1 else Int.MAX_VALUE,
        overflow = if (isValue && !valueWraps) TextOverflow.MiddleEllipsis else TextOverflow.Clip,
        modifier = Modifier
            .fillMaxWidth()
            .drawWithContent {
                drawContent()
                if (scroll.canScrollForward) {
                    val fade = 24.dp.toPx()
                    drawRect(
                        brush = Brush.verticalGradient(
                            colors = listOf(fadeInto.copy(alpha = 0f), fadeInto),
                            startY = size.height - fade,
                            endY = size.height,
                        ),
                        topLeft = Offset(0f, size.height - fade),
                    )
                }
            }
            .verticalScroll(scroll),
    )
}

/** `attributed()`: Gilroy-Regular 16 at a 1.28 line height. */
internal val AlertMessageStyle = androidx.compose.ui.text.TextStyle(
    fontFamily = Gilroy,
    fontWeight = FontWeight.Normal,
    fontSize = 16.sp,
    lineHeight = 20.48.sp,
)

/**
 * Side by side for one, or two whose titles are shorter than 16 characters; stacked otherwise,
 * the first button at the bottom as iOS's reversed stack has it. [stackable] false keeps a text
 * field's Cancel and Save side by side, as iOS always draws them.
 */
@Composable
private fun AlertButtons(buttons: List<BittrAlertButton>, motion: AlertMotion, stackable: Boolean) {
    val fitSideBySide = buttons.all { it.label.length < 16 }
    val stacked = stackable && (buttons.size > 2 || (buttons.size == 2 && !fitSideBySide))
    val indexed = buttons.withIndex().toList()
    if (stacked) {
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(horizontal = 15.dp),
        ) {
            indexed.reversed().forEach { (position, button) ->
                AlertButton(button, position, motion, Modifier.fillMaxWidth())
            }
        }
    } else {
        // Side by side, the buttons share the tallest one's height.
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .padding(horizontal = 15.dp)
                .height(IntrinsicSize.Min),
        ) {
            indexed.forEach { (position, button) ->
                AlertButton(button, position, motion, Modifier.weight(1f).fillMaxHeight())
            }
        }
    }
}

/**
 * `makeAlertButton`: the rounded, shadowed plate with its centred label. A one-line title keeps the
 * 40 plate, and one that wraps grows it, 10 clear of each edge.
 */
@Composable
private fun AlertButton(button: BittrAlertButton, position: Int, motion: AlertMotion, modifier: Modifier) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .heightIn(min = 40.dp)
            .iosShadow(AlertButtonShape)
            .clip(AlertButtonShape)
            .background(BittrTheme.colors.scrim1)
            .clickable(role = Role.Button) { motion.close(button.onClick) }
            .testTag(TestID.Alert.buttonAt(position)),
    ) {
        Text(
            text = button.label,
            // Wrapped lines sit Gilroy-Bold's own 19.8 apart, as a UILabel sets them. Centred in
            // its line, a single line sits where it did at 16.
            style = MaterialTheme.typography.labelLarge.copy(
                fontSize = 16.sp,
                lineHeight = 20.sp,
                lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
            ),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(horizontal = 10.dp, vertical = 10.dp)
                .offset(y = 1.dp),
        )
    }
}

private val AlertButtonShape = RoundedCornerShape(8.dp)

/** `slideIn`'s 0.5 s spring at damping 0.7: (4 / (0.7 × 0.5))², by [PageSlideSpec]'s settle rule. */
private const val AlertStiffness = 131f

/** `slideOut`'s 0.3 s. */
private const val AlertCloseMs = 300

/**
 * An alert's title: 22 sp bold, centred. Every alert in the app uses it, including the
 * ones a feature draws in its own window, so there is one dialog style (review S2).
 */
@Composable
fun BittrDialogTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleLarge,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

/**
 * A value an alert reports rather than a sentence — the invoice or id a "Copied" alert echoes.
 * 14 sp monospace at 70 %, on one line that gives way in the middle, so the start and the end
 * of the hash — the parts people compare — stay visible (review S19; at body size a Lightning
 * invoice filled the dialog). TalkBack and the flows still read all of it.
 */
@Composable
fun BittrDialogValue(text: String, wrap: Boolean = false) {
    // [wrap] is for a key checked character by character — a node's public key — which must
    // be shown whole; a copied invoice only needs its two ends.
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
        color = LocalContentColor.current.copy(alpha = 0.70f),
        textAlign = TextAlign.Center,
        maxLines = if (wrap) Int.MAX_VALUE else 1,
        overflow = if (wrap) TextOverflow.Clip else TextOverflow.MiddleEllipsis,
        modifier = Modifier.fillMaxWidth(),
    )
}

/**
 * An alert's message: 16 sp on 24, centred, at 80 % of the dialog's content colour.
 *
 * The shared copy's `<b>` spans render bold ([bittrMarkup]), as iOS renders them: the amount,
 * the fee, the balance the user has to check before answering (review S12). Callers pass the
 * copy with its markup rather than stripping it.
 */
@Composable
fun BittrDialogMessage(text: String) = BittrDialogMessage(bittrMarkup(text))

/** [BittrDialogMessage] for a message with markup — bold spans, links. */
@Composable
fun BittrDialogMessage(text: AnnotatedString) {
    // Scrolls rather than clips: the map's BTCMap explainer nearly fills a phone. Capped at
    // 45 % of the screen so the title and the actions never scroll away, and faded at the
    // bottom while there is more below, so the cut reads as "scroll" rather than as the end
    // of the text (review S31, pass 4).
    val scroll = rememberScrollState()
    val fadeInto = BittrTheme.colors.dialogContainer
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.45f).dp
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        color = LocalContentColor.current.copy(alpha = 0.80f),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight)
            .drawWithContent {
                drawContent()
                if (scroll.canScrollForward) {
                    val fade = 24.dp.toPx()
                    drawRect(
                        brush = Brush.verticalGradient(
                            colors = listOf(fadeInto.copy(alpha = 0f), fadeInto),
                            startY = size.height - fade,
                            endY = size.height,
                        ),
                        topLeft = Offset(0f, size.height - fade),
                    )
                }
            }
            .verticalScroll(scroll),
    )
}
