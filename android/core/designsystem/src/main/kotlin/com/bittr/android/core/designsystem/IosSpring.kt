package com.bittr.android.core.designsystem

import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import kotlin.math.floor
import kotlin.math.pow

/**
 * iOS's `UIView.animate(withDuration:delay:usingSpringWithDamping:…)` as a Compose spring.
 *
 * UIKit turns the duration into a unit-mass `CASpringAnimation` whose natural frequency is a
 * function of the damping divided by the duration, and Compose takes that stiffness directly.
 */
fun <T> iosSpring(durationSeconds: Float, dampingRatio: Float, visibilityThreshold: T? = null): SpringSpec<T> =
    spring(dampingRatio = dampingRatio, stiffness = iosSpringStiffness(durationSeconds, dampingRatio), visibilityThreshold = visibilityThreshold)

/**
 * The stiffness UIKit gives a spring of [durationSeconds] at [dampingRatio]: (ω·d / d)², with ω·d
 * read from [UIKIT_OMEGA_TIMES_DURATION] and interpolated between its steps.
 */
fun iosSpringStiffness(durationSeconds: Float, dampingRatio: Float): Float {
    val position = ((dampingRatio.coerceIn(0.3f, 1f) - 0.3f) / 0.05f).toDouble()
    val index = floor(position).toInt().coerceAtMost(UIKIT_OMEGA_TIMES_DURATION.lastIndex - 1)
    val fraction = position - index
    val omegaTimesDuration = UIKIT_OMEGA_TIMES_DURATION[index] * (1 - fraction) + UIKIT_OMEGA_TIMES_DURATION[index + 1] * fraction
    return (omegaTimesDuration / durationSeconds).pow(2).toFloat()
}

/**
 * √stiffness × duration of the `CASpringAnimation` UIKit creates, at damping 0.30, 0.35 … 1.00.
 * Read from `UIView.animate(withDuration:usingSpringWithDamping:)` in a Mac Catalyst build: UIKit
 * solves for it numerically, so there is no closed form to port.
 */
private val UIKIT_OMEGA_TIMES_DURATION = doubleArrayOf(
    19.1698, 16.9236, 15.1966, 13.8275, 12.7169, 11.8001, 11.0335, 10.3869,
    9.8396, 9.3779, 8.9943, 8.6897, 8.4808, 8.4425, 9.2334,
)
