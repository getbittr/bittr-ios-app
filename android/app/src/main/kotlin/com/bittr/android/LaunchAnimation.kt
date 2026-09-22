package com.bittr.android

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
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
 * 3. **The logo rises into the app bar** — `logoSlidesToTop`: 0.7 s after 0.3 s, while the
 *    cover fades and the screen appears behind it. This one does not bounce: see [RISE_MS].
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
        reveal.animateTo(1f, spring(dampingRatio = DAMPING, stiffness = REVEAL_STIFFNESS))
        delay(RISE_DELAY_MS)
        rise.animateTo(1f, tween(durationMillis = RISE_MS, easing = FastOutSlowInEasing))
        onFinished()
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            // The splash's yellow, carried on without a seam and fading as the app arrives.
            // Full-bleed, behind the status bar as the splash was.
            .background(BittrTheme.colors.canvas.copy(alpha = 1f - rise.value)),
    ) {
        // **The same box the app bar is laid out in.** `BittrCanvas` puts its column inside
        // these two insets and hangs the 56 dp bar off the top of it, so measuring the landing
        // here means measuring it in the app bar's own coordinates. Reading the status-bar inset
        // and subtracting it by hand instead left the logo 22 dp below the bar's real one, which
        // is the sort of arithmetic that is wrong on exactly the devices nobody tests on.
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
            contentAlignment = Alignment.Center,
        ) {
            val logoHeight = lerp(LOGO_HEIGHT, APP_BAR_LOGO_HEIGHT, rise.value)
            val travel = maxHeight / 2 - logoHeight / 2 - APP_BAR_LOGO_TOP
            // The logo does not fade: it lands *on* the app bar's own logo, at that logo's height
            // and position, and is taken away with the cover. Fading it out instead showed both at
            // once for a frame or two, slightly out of line — iOS has no such moment because there
            // the logo that rises is the app bar's.
            Logo(
                logoHeight = logoHeight,
                slide = slide.value,
                reveal = reveal.value,
                modifier = Modifier.offset(y = lerp(0.dp, -travel, rise.value)),
            )
        }
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

/**
 * `BittrAppBar`'s logo, and how far below the status bar it sits — where stage 3 lands. The bar
 * is 56 dp with the logo centred in it, so the logo's top is (56 − 19) / 2 below the status bar.
 */
private val APP_BAR_LOGO_HEIGHT = 19.dp
private val APP_BAR_LOGO_TOP = 18.5.dp

private const val COIN_DELAY_MS = 300L
private const val COIN_MS = 600
private const val RISE_DELAY_MS = 300L
private const val DAMPING = 0.65f

/**
 * iOS gives its springs a duration — 0.6 s to widen, 0.7 s to rise — and Compose's take theirs
 * from stiffness instead. A spring settles in about `4 / (damping × √stiffness)` seconds, so
 * these are the stiffnesses that land on iOS's two durations. The stock constants are far too
 * brisk for this: `StiffnessMediumLow` settles in 0.31 s and `StiffnessLow` in 0.2 s, which read
 * as the logo snapping into place rather than travelling there.
 */
private const val REVEAL_STIFFNESS = 105f

/**
 * **The rise is a 0.7 s ease, not a spring, and this is a deliberate departure from iOS.**
 *
 * iOS springs it at [DAMPING], and a spring has no duration: it overshoots and then takes as
 * long as it takes. Both halves of that hurt here, because ours is a *second* logo that has to
 * land on the app bar's own and then be taken away at a known moment — `core.launchComplete`
 * gates every flow on it. Sprung, it overshot the bar by some 25 dp and hung above the real
 * logo for half a second; damped so it would not overshoot, it was still 34 dp short when the
 * hand-off came and vanished in mid-air (both measured on Ruben's phone, 2026-09-22). A tween
 * of exactly iOS's 0.7 s lands on the bar on the frame the cover goes, and the swap is invisible.
 */
private const val RISE_MS = 700
