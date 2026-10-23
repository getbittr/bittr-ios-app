package com.bittr.android.core.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/**
 * iOS's page sheet — what a plain modal segue presents on an iPhone, and how `ArticleViewController`
 * arrives: a card that rises from the bottom over the screen it came from, which dims and stays
 * visible above it, and goes back down when dismissed. The Android counterpart is a modal bottom
 * sheet; this one is drawn by hand so its edges, dim and motion are iOS's rather than Material's.
 *
 * Meant to fill a navigation `dialog` destination with a full-screen, edge-to-edge window, so the
 * screen underneath really is still there. The window's own dim and animation are switched off;
 * the dim and the slide here replace them. The sheet's top sits at the bottom of the status bar,
 * as iOS's does below the safe area, with 10 dp rounded corners — iOS's standard page sheet; the
 * 20 % dim is read off a screenshot of the iOS sheet over the yellow canvas.
 *
 * Back, and anything [content] calls its `dismiss` with, slides the sheet down first and only then
 * calls [onDismissed], which pops the destination.
 */
@Composable
fun BittrSheet(
    onDismissed: () -> Unit,
    content: @Composable (dismiss: () -> Unit) -> Unit,
) {
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
    SideEffect {
        window?.setDimAmount(0f)
        window?.setWindowAnimations(0)
    }

    val visible = remember { MutableTransitionState(false).apply { targetState = true } }
    val dismiss = { visible.targetState = false }
    val onDismissedLatest by rememberUpdatedState(onDismissed)
    LaunchedEffect(visible.isIdle, visible.currentState) {
        if (visible.isIdle && !visible.currentState) onDismissedLatest()
    }
    BackHandler(onBack = dismiss)

    // A dialog window is its own semantics root and does not inherit the app's
    // `testTagsAsResourceId`: without this, Maestro sees none of the ids inside.
    Box(Modifier.fillMaxSize().exposeTestTags()) {
        AnimatedVisibility(
            visibleState = visible,
            enter = fadeIn(spring(stiffness = SheetStiffness)),
            exit = fadeOut(spring(stiffness = SheetStiffness)),
        ) {
            Box(Modifier.fillMaxSize().background(SheetScrim))
        }
        AnimatedVisibility(
            visibleState = visible,
            enter = slideInVertically(spring(stiffness = SheetStiffness, visibilityThreshold = IntOffset(1, 1))) { it },
            exit = slideOutVertically(spring(stiffness = SheetStiffness, visibilityThreshold = IntOffset(1, 1))) { it },
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .clip(SheetShape),
            ) {
                content(dismiss)
            }
        }
    }
}

/** iOS's standard page-sheet corners. */
private val SheetShape = RoundedCornerShape(topStart = 10.dp, topEnd = 10.dp)

/** Black at 20 % — the iOS sheet's dim over the yellow canvas, off a screenshot. */
private val SheetScrim = Color.Black.copy(alpha = 0.2f)

/**
 * Critically damped, as iOS's sheet is: it arrives and leaves without a bounce, settling in about
 * 0.4 s.
 */
private const val SheetStiffness = 300f

/**
 * iOS's Settings pop-up — `CoreViewController.showSettings`: a panel as tall as its content that
 * springs up from the bottom over the screen it was opened from, which dims to 50 % black and stays
 * visible above it. The panel's top corners are 20 pt; it reaches down behind the navigation bar.
 *
 * Meant to fill a navigation `dialog` destination with a full-screen, edge-to-edge window, as
 * [BittrSheet] is, and it switches the window's own dim and animation off the same way.
 *
 * - **Opening:** a 0.6 s spring at damping 0.7, 0.2 s after the tap, the dim coming up with it.
 * - **Closing** — the dim, Back, or anything [content] calls its `dismiss` with: 0.3 s ease-in-out
 *   down and out, then [onDismissed], which pops the destination.
 * - **Dragging** it down tracks the finger and fades the dim; let go past a third of its height or
 *   faster than 800 pt/s and it closes, otherwise it eases back up in 0.3 s (`handleSettingsPan`).
 *
 * The panel runs 20 dp past the bottom of the screen, as iOS's container is `+ 20` taller than its
 * content, so the spring's overshoot lifts more canvas into view rather than the panel's bottom edge.
 *
 * [cornerRadius] is the top corners': 20 for Settings, 12 for the map's place panel.
 */
@Composable
fun BittrPopup(
    onDismissed: () -> Unit,
    cornerRadius: Dp = 20.dp,
    content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit,
) {
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
    SideEffect {
        window?.setDimAmount(0f)
        window?.setWindowAnimations(0)
    }

    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val onDismissedLatest by rememberUpdatedState(onDismissed)
    // How far the panel is below its open position, in px; its height when closed.
    val offset = remember { Animatable(Float.MAX_VALUE) }
    // The content's height, without the overshoot filler below it.
    var panelHeight by remember { mutableFloatStateOf(0f) }
    val overshootPx = with(density) { PopupOvershoot.toPx() }
    var closing by remember { mutableStateOf(false) }

    LaunchedEffect(panelHeight > 0f) {
        if (panelHeight <= 0f) return@LaunchedEffect
        offset.snapTo(panelHeight)
        // Counted in frames rather than `delay`, so a test's frame clock carries it as it does the spring.
        val start = withFrameMillis { it }
        while (withFrameMillis { it } - start < PopupOpenDelayMs) Unit
        offset.animateTo(0f, iosSpring(0.6f, 0.7f))
    }

    val dismiss: () -> Unit = {
        if (!closing) {
            closing = true
            scope.launch {
                offset.animateTo(panelHeight, tween(PopupCloseMs, easing = FastOutSlowInEasing))
                onDismissedLatest()
            }
        }
    }
    BackHandler(onBack = dismiss)

    val shown = if (panelHeight > 0f) (1f - offset.value / panelHeight).coerceIn(0f, 1f) else 0f
    // A dialog window is its own semantics root and does not inherit the app's
    // `testTagsAsResourceId`: without this, Maestro sees none of the ids inside.
    Box(Modifier.fillMaxSize().exposeTestTags()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f * shown))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = dismiss,
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                // Off screen until measured, so the first frame is not the panel at the top of its travel.
                .offset {
                    IntOffset(0, if (panelHeight <= 0f) OffScreen else (offset.value + overshootPx).roundToInt())
                }
                .onSizeChanged { panelHeight = it.height - overshootPx }
                .clip(RoundedCornerShape(topStart = cornerRadius, topEnd = cornerRadius))
                .background(BittrTheme.colors.canvas)
                .draggable(
                    orientation = Orientation.Vertical,
                    state = rememberDraggableState { delta ->
                        if (!closing) scope.launch { offset.snapTo((offset.value + delta).coerceAtLeast(0f)) }
                    },
                    onDragStopped = { velocity ->
                        val fast = velocity > with(density) { PopupFlingVelocity.dp.toPx() }
                        if (offset.value > panelHeight / 3 || fast) {
                            dismiss()
                        } else {
                            offset.animateTo(0f, tween(PopupCloseMs, easing = LinearOutSlowInEasing))
                        }
                    },
                )
                .navigationBarsPadding()
                .padding(bottom = PopupOvershoot),
        ) {
            content(dismiss)
        }
    }
}

/** iOS's `+ 20` on the container's height, kept below the screen's edge. */
private val PopupOvershoot = 20.dp

private const val OffScreen = 1_000_000

/** `showSettings`' `delay: 0.2`. */
private const val PopupOpenDelayMs = 200L

/** `hideSettings`' and the snap-back's 0.3 s. */
private const val PopupCloseMs = 300

/** `handleSettingsPan`'s 800 pt/s. */
private const val PopupFlingVelocity = 800
