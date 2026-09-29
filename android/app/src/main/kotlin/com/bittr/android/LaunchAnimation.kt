package com.bittr.android

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import com.bittr.android.core.designsystem.BittrTheme
import kotlinx.coroutines.delay

/**
 * The launch animation — `ios/bittr/Core/LogoAnimation.swift`, built as iOS builds it: the logo is
 * a gold coin sliding into a piggy bank's slot, told with a few image pieces moving inside a
 * clipping box and fading in and out at the right moments. The pieces, the box and the cover are
 * iOS's, in the brand yellow in light and dark mode alike; the mode shows only as the cover fades
 * and the PIN or signup page appears.
 *
 * The pieces, back to front, in `logoView` (30 tall, clipping, centred on the screen):
 * - `bittrtext` — the word, pinned to the box's right edge, so widening the box unveils it;
 *   `bittrtextwhite` over it for dark mode's final logo.
 * - `coverView` — yellow, over the coin's width and 5 more: hides the word behind the coin.
 * - `coin1` — the white disc with the black wedge of the slot at its lower left.
 * - `secondCoin` — a yellow disc 40 up and right of `firstCoin`, outside the box, which follows it
 *   into the disc's centre.
 * - `blackCoin` — the wedge alone (`coin2`), under the coin.
 * - `firstCoin` — the yellow disc in the white disc's centre that makes it a ring: the gold coin.
 * - `coin3` — the wedge's shading, over the coin, so it slides *into* the slot.
 * - `logo80` and `logodarkmode80` — the finished mark, faded in as the pieces fade out.
 *
 * Three stages, with iOS's timings:
 * 1. **The coin slides into the slot** (`coinSlidesIntoSlot`): 0.3 s in, 0.6 s ease-in-out, the
 *    coin 40 left and 40 down, under the shading and out of the box, while `secondCoin` takes its
 *    place in the ring.
 * 2. **The logo widens to unveil the word** (`widenLogoView`): the box from 30 to 106 about its
 *    centre, 0.6 s spring at damping 0.65.
 * 3. **The logo rises to the top** (`logoSlidesToTop`): 0.3 s in, 0.7 s spring at damping 0.65,
 *    from the screen's centre to 10 below the status bar — where the app bar's logo is — while the
 *    yellow cover and the pieces fade out and the final logo fades in, white-and-yellow in dark
 *    mode.
 *
 * **`core.launchComplete` moves with this.** iOS sets that id when stage 3 finishes and every flow
 * gates on it through `helpers/wait_for_launch.yaml`; [MainActivity] tags the root once
 * [onFinished] has fired, so no flow taps into a cover that still swallows taps. The app's own
 * logo stays hidden until then (`LocalAppBarLogoVisible`), and this one lands exactly on it.
 *
 * @param onFinished stage 3 is over, the cover is gone and the app is interactive.
 */
@Composable
fun LaunchAnimation(onFinished: () -> Unit, modifier: Modifier = Modifier) {
    val slide = remember { Animatable(0f) }
    val widen = remember { Animatable(0f) }
    val rise = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        delay(COIN_DELAY_MS)
        slide.animateTo(1f, tween(durationMillis = COIN_MS, easing = FastOutSlowInEasing))
        widen.animateTo(1f, spring(dampingRatio = DAMPING, stiffness = WIDEN_STIFFNESS))
        delay(RISE_DELAY_MS)
        rise.animateTo(1f, spring(dampingRatio = DAMPING, stiffness = RISE_STIFFNESS))
        onFinished()
    }

    val yellow = BittrTheme.colors.brandFixed
    val dark = BittrTheme.isDark
    // Alphas follow the rise's spring, clamped: it overshoots, alpha cannot.
    val shown = rise.value.coerceIn(0f, 1f)
    val statusTop = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        // `animationCover`: the splash's yellow, full-bleed, fading as the logo rises.
        Box(
            Modifier
                .fillMaxSize()
                .alpha(1f - shown)
                .background(yellow),
        )

        val logoWidth = LOGO_HEIGHT + (LOGO_WIDE - LOGO_HEIGHT) * widen.value
        // Centred on the whole screen, as the splash's mark is; landing on the app bar's logo.
        val startTop = maxHeight / 2 - LOGO_HEIGHT / 2
        val endTop = statusTop + LOGO_TOP_IN_BAR
        Box(
            modifier = Modifier
                .offset(x = (maxWidth - logoWidth) / 2, y = lerp(startTop, endTop, rise.value))
                .width(logoWidth)
                .height(LOGO_HEIGHT)
                .clipToBounds(),
        ) {
            val coinDx = COIN_TRAVEL * -slide.value
            val coinDy = COIN_TRAVEL * slide.value
            val pieces = 1f - shown

            // `bittrtext` / `bittrtextwhite`: trailing on the box, 0.94 of its height, 0.5 low.
            Piece(R.drawable.launch_text, x = logoWidth - TEXT_WIDTH, y = TEXT_TOP, width = TEXT_WIDTH, height = TEXT_HEIGHT)
            if (dark) {
                Piece(R.drawable.launch_text_dark, x = logoWidth - TEXT_WIDTH, y = TEXT_TOP, width = TEXT_WIDTH, height = TEXT_HEIGHT, alpha = shown)
            }
            // `coverView`.
            Box(
                Modifier
                    .size(width = LOGO_HEIGHT + 5.dp, height = LOGO_HEIGHT)
                    .alpha(pieces)
                    .background(yellow),
            )
            // `coin1`.
            Piece(R.drawable.launch_coin_slot, x = 0.dp, y = 0.dp, width = LOGO_HEIGHT, height = LOGO_HEIGHT, alpha = pieces)
            // `secondCoin`: 40 right and 40 up of `firstCoin`.
            Disc(centreX = COIN_CENTRE + coinDx + COIN_TRAVEL, centreY = COIN_CENTRE + coinDy - COIN_TRAVEL, alpha = pieces)
            // `blackCoin`: the wedge, 0.63 of the disc, at its lower left.
            Piece(R.drawable.launch_coin_wedge, x = 0.dp, y = LOGO_HEIGHT - WEDGE_SIZE, width = WEDGE_SIZE, height = WEDGE_SIZE, alpha = pieces)
            // `firstCoin`: the gold coin.
            Disc(centreX = COIN_CENTRE + coinDx, centreY = COIN_CENTRE + coinDy, alpha = pieces)
            // `coin3`: the slot's shading, over the coin.
            Piece(R.drawable.launch_coin_shade, x = 0.dp, y = LOGO_HEIGHT - WEDGE_SIZE, width = WEDGE_SIZE, height = WEDGE_SIZE, alpha = pieces)
            // `finalLogo` and, in dark mode, `logoIconDarkMode` over it.
            Piece(R.drawable.launch_logo, x = 0.dp, y = 0.dp, width = LOGO_HEIGHT, height = LOGO_HEIGHT, alpha = shown)
            if (dark) {
                Piece(R.drawable.launch_logo_dark, x = 0.dp, y = 0.dp, width = LOGO_HEIGHT, height = LOGO_HEIGHT, alpha = shown)
            }
        }
    }
}

/** One of iOS's image pieces, aspect-fit into its frame in the logo box. */
@Composable
private fun Piece(@DrawableRes image: Int, x: Dp, y: Dp, width: Dp, height: Dp, alpha: Float = 1f) {
    Image(
        painter = painterResource(image),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .offset(x = x, y = y)
            .size(width = width, height = height)
            .alpha(alpha),
    )
}

/** `firstCoin` / `secondCoin`: a yellow disc, 0.7 of the white one, centred on the given point. */
@Composable
private fun Disc(centreX: Dp, centreY: Dp, alpha: Float) {
    Box(
        Modifier
            .offset(x = centreX - COIN_SIZE / 2, y = centreY - COIN_SIZE / 2)
            .size(COIN_SIZE)
            .alpha(alpha)
            .background(BittrTheme.colors.brandFixed, CircleShape),
    )
}

/** `logoView`: 30 tall, 30 wide until it widens to 106 — the app bar's logo box. */
private val LOGO_HEIGHT = 30.dp
private val LOGO_WIDE = 106.dp

/** `logoTopInset`: the logo's top, 10 below the status bar. */
private val LOGO_TOP_IN_BAR = 10.dp

/** `bittrtext`: 2.18 : 1 at 0.94 of the logo's height, its centre 0.5 below the disc's. */
private val TEXT_HEIGHT = LOGO_HEIGHT * 0.94f
private val TEXT_WIDTH = LOGO_HEIGHT * 2.17971f
private val TEXT_TOP = (LOGO_HEIGHT - TEXT_HEIGHT) / 2 + 0.5.dp

/** `firstCoin` and `secondCoin`: 0.7 of the disc, travelling 40 each way. */
private val COIN_SIZE = LOGO_HEIGHT * 0.7f
private val COIN_CENTRE = LOGO_HEIGHT / 2
private val COIN_TRAVEL = 40.dp

/** `blackCoin` and `coin3`: 0.63 of the disc. */
private val WEDGE_SIZE = LOGO_HEIGHT * 0.63f

private const val COIN_DELAY_MS = 300L
private const val COIN_MS = 600
private const val RISE_DELAY_MS = 300L
private const val DAMPING = 0.65f

/**
 * iOS gives its springs a duration — 0.6 s to widen, 0.7 s to rise — and Compose's take theirs
 * from stiffness. A spring settles in about `4 / (damping × √stiffness)` seconds: (4 / (0.65 ×
 * 0.6))² is 105, and (4 / (0.65 × 0.7))² is 77.
 */
private const val WIDEN_STIFFNESS = 105f
private const val RISE_STIFFNESS = 77f
