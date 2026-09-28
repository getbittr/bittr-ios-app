package com.bittr.android.core.designsystem

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
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
