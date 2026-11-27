package com.bittr.android.core.designsystem

import androidx.compose.animation.core.SnapSpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [iosSpringStiffness] against the `CASpringAnimation.stiffness` UIKit itself creates for every iOS
 * spring the app ports, read from a Mac Catalyst build of `UIView.animate(…usingSpringWithDamping…)`.
 */
class IosSpringTest {

    private fun assertMatchesUiKit(what: String, seconds: Float, damping: Float, uiKit: Float, tolerance: Float = 0.001f) {
        val stiffness = iosSpringStiffness(seconds, damping)
        assertEquals("$what: stiffness $stiffness, UIKit $uiKit", uiKit, stiffness, uiKit * tolerance)
    }

    @Test
    fun `the ported iOS springs are as stiff as UIKit makes them`() {
        assertMatchesUiKit("signup page slide, launch rise", 0.7f, 0.65f, 220.180f)
        assertMatchesUiKit("launch widen", 0.6f, 0.65f, 299.689f)
        assertMatchesUiKit("PIN, Signup and Home stack", 0.8f, 0.75f, 137.414f)
        assertMatchesUiKit("Settings and map place pop-up", 0.6f, 0.7f, 268.941f)
        assertMatchesUiKit("alert slide-in", 0.5f, 0.7f, 387.275f)
    }

    @Test
    fun `the table's ends and a damping between its steps match UIKit`() {
        assertMatchesUiKit("damping 0.30", 1f, 0.3f, 367.481f)
        assertMatchesUiKit("damping 1.00", 1f, 1f, 85.2559f)
        // Interpolated between 0.70 and 0.75, so within 0.5 % rather than on UIKit's number.
        assertMatchesUiKit("damping 0.72", 1f, 0.72f, 93.0306f, tolerance = 0.005f)
    }

    @Test
    fun `a damping outside the table or a negative duration is refused`() {
        assertThrows(IllegalArgumentException::class.java) { iosSpringStiffness(1f, 0.29f) }
        assertThrows(IllegalArgumentException::class.java) { iosSpringStiffness(1f, 1.01f) }
        assertThrows(IllegalArgumentException::class.java) { iosSpringStiffness(-1f, 0.7f) }
    }

    @Test
    fun `no duration jumps to the end, as iOS's moveToPage does`() {
        assertTrue(iosSpring<Float>(0f, 0.7f) is SnapSpec)
    }
}
