package com.bittr.android

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import com.bittr.android.core.designsystem.BittrCoin
import com.bittr.android.core.designsystem.BittrMark
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrWordmark
import com.bittr.android.core.designsystem.COIN_HIDDEN
import com.bittr.android.core.designsystem.LOGO_TAIL_RATIO
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The launch animation, ported from `ios/bittr/Core/LogoAnimation.swift`.
 *
 * Three stages, with iOS's durations, easings and spring damping:
 *
 * 1. **The coin slides into its slot** — `coinSlidesIntoSlot`: 0.6 s ease-in-out after a
 *    0.3 s pause. The coin crosses the ring from upper right to lower left and is clipped to
 *    the disc the ring traces, so it is seen only *through* the mark and is gone by the end;
 *    the mark's wedge draws over it, which is what makes the exit read as a slot rather than
 *    a disc drifting off. Both ends of the slide are the plain mark — the same frame the
 *    splash drawable holds, so the hand-off from the splash is invisible.
 * 2. **The logo widens to unveil the word** — `widenLogoView`: 0.6 s, spring damping 0.65.
 *    A right-aligned clip that grows reveals the word from its right end — "tr", "ittr",
 *    "bittr" — and the mark slides left as the pair re-centres, which is what iOS's widening
 *    logo view does and what the recording shows.
 * 3. **The logo rises into the app bar** — `logoSlidesToTop`: 0.7 s after 0.3 s, spring
 *    damping 0.65, while the yellow cover fades and the screen appears behind it.
 *
 * **`core.launchComplete` moves with this.** iOS sets that id when stage 3 finishes and every
 * flow gates on it through `helpers/wait_for_launch.yaml`; [MainActivity] tags the root once
 * [onFinished] has fired, so no flow taps into a cover that still swallows taps.
 *
 * @param onFinished stage 3 is over, the cover is gone and the app is interactive.
 */
@Composable
fun LaunchAnimation(onFinished: () -> Unit, modifier: Modifier = Modifier) {
    val slide = remember { Animatable(0f) }
    val reveal = remember { Animatable(0f) }
    val rise = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        delay(COIN_DELAY_MS)
        slide.animateTo(1f, tween(durationMillis = COIN_MS, easing = FastOutSlowInEasing))
        reveal.animateTo(1f, spring(dampingRatio = DAMPING, stiffness = Spring.StiffnessMediumLow))
        delay(RISE_DELAY_MS)
        launch { rise.animateTo(1f, spring(dampingRatio = DAMPING, stiffness = Spring.StiffnessLow)) }
        // Hand over on iOS's 0.7 s rather than on the spring settling: the tail of a spring is
        // imperceptible and holding the cover for it would add most of a second to every flow.
        delay(RISE_MS)
        onFinished()
    }

    val statusBar = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            // The splash's yellow, carried on without a seam and fading as the app arrives.
            .background(BittrTheme.colors.canvas.copy(alpha = 1f - rise.value)),
        contentAlignment = Alignment.Center,
    ) {
        val logoHeight = lerp(LOGO_HEIGHT, APP_BAR_LOGO_HEIGHT, rise.value)
        val travel = maxHeight / 2 - logoHeight / 2 - statusBar - APP_BAR_LOGO_TOP
        Logo(
            logoHeight = logoHeight,
            slide = slide.value,
            reveal = reveal.value,
            modifier = Modifier
                .offset(y = lerp(0.dp, -travel, rise.value))
                .alpha(1f - rise.value),
        )
    }
}

/** The mark, the coin sliding into it, and the word being unveiled beside them. */
@Composable
private fun Logo(logoHeight: Dp, slide: Float, reveal: Float, modifier: Modifier = Modifier) {
    val colors = BittrTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier,
    ) {
        Box(contentAlignment = Alignment.Center) {
            BittrMark(size = logoHeight, ink = colors.onCanvas, arc = colors.canvasArc)
            BittrCoin(
                size = logoHeight,
                ink = Color.Transparent,
                face = colors.canvasArc,
                // From clear of the ring at the upper right, through it, to clear of it at the
                // lower left: the coin is only ever seen through the ring, and both ends of the
                // slide are the plain mark — the splash's frame, and the app bar's.
                travel = Offset(
                    x = COIN_HIDDEN * (1f - 2f * slide),
                    y = -COIN_HIDDEN * (1f - 2f * slide),
                ),
            )
            // The wedge over the coin: the coin slides *under* the black half, into the slot.
            BittrMark(size = logoHeight, ink = colors.onCanvas, arc = Color.Transparent)
        }
        // What widens is everything past the mark — the artwork's gap and then the word — so
        // the lockup this settles on is the one `BittrLogo` draws, to the unit. Right-aligned,
        // the word comes out of the mark end first: "tr", "ittr", "bittr", and the gap opens
        // last, which is the order the iOS recording shows.
        Box(
            modifier = Modifier
                .width(logoHeight * LOGO_TAIL_RATIO * reveal)
                .clipToBounds(),
            contentAlignment = Alignment.CenterEnd,
        ) {
            BittrWordmark(height = logoHeight, ink = colors.onCanvas)
        }
    }
}

/**
 * iOS's `logoViewWidth = 106` lockup, as the mark's height: 106 / 3.58 (the artwork's ratio).
 * Measured against the recording — the lockup is 26 % of the screen's width on iOS, and this
 * is what puts it there. At 49 dp, the first attempt, it was 38 %.
 */
private val LOGO_HEIGHT = 29.6.dp

/** `BittrAppBar`'s logo, and how far below the status bar it sits — where stage 3 lands. */
private val APP_BAR_LOGO_HEIGHT = 19.dp
private val APP_BAR_LOGO_TOP = 18.dp

private const val COIN_DELAY_MS = 300L
private const val COIN_MS = 600
private const val RISE_DELAY_MS = 300L
private const val RISE_MS = 700L
private const val DAMPING = 0.65f
