package com.bittr.android.core.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider

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

    Box(Modifier.fillMaxSize()) {
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
