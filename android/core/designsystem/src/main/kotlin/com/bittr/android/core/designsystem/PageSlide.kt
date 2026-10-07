package com.bittr.android.core.designsystem

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.ui.unit.IntOffset

/**
 * iOS's signup page slide, `SignupViewController.moveToPage`. iOS lays every signup page side by
 * side in one strip and moves the strip to `-width × page`, so going from page `from` to page `to`
 * slides both pages `to − from` screen widths: forward comes in from the right, back from the left,
 * and a jump over several pages travels that many widths. The move is a 0.7 s spring at damping
 * 0.65 — the same bounce as the launch animation's rise, and the same stiffness rule: a spring
 * settles in about `4 / (damping × √stiffness)` seconds, which puts 0.7 s at 77.
 */
val PageSlideSpec: FiniteAnimationSpec<IntOffset> = spring(
    dampingRatio = 0.65f,
    stiffness = 77f,
    visibilityThreshold = IntOffset.VisibilityThreshold,
)

/** The page arriving at [to], coming from [from]. */
fun pageSlideIn(from: Int, to: Int): EnterTransition =
    slideInHorizontally(PageSlideSpec) { width -> width * (to - from) }

/** The page at [from] leaving for [to]. */
fun pageSlideOut(from: Int, to: Int): ExitTransition =
    slideOutHorizontally(PageSlideSpec) { width -> -width * (to - from) }

/** Both halves, for an `AnimatedContent` whose states are pages. */
fun pageSlide(from: Int, to: Int): ContentTransform = pageSlideIn(from, to) togetherWith pageSlideOut(from, to)

/**
 * iOS's `CoreViewController` stack: the PIN, Signup and Home containers sit one above the other —
 * PIN on top, Signup below it, Home at the bottom — and `showPin`, `showSignup` and
 * `hidePinAndSignup` move them together by one screen height on a 0.8 s spring at damping 0.75.
 * Going down the stack, the page leaves upwards and the next rises from below; going up, the
 * page drops away and the next comes down from above. Stiffness by the same rule as
 * [PageSlideSpec]: 4 / (0.75 × 0.8) squared is 44.
 */
val StackSlideSpec: FiniteAnimationSpec<IntOffset> = spring(
    dampingRatio = 0.75f,
    stiffness = 44f,
    visibilityThreshold = IntOffset.VisibilityThreshold,
)

/** The page arriving at stack level [to] from level [from]; a higher level sits lower on screen. */
fun stackSlideIn(from: Int, to: Int): EnterTransition =
    slideInVertically(StackSlideSpec) { height -> if (to > from) height else -height }

/** The page at stack level [from] leaving for level [to]. */
fun stackSlideOut(from: Int, to: Int): ExitTransition =
    slideOutVertically(StackSlideSpec) { height -> if (to > from) -height else height }
