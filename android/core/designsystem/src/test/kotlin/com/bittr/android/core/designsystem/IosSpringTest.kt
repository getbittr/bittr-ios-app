package com.bittr.android.core.designsystem

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [iosSpringStiffness] against the `CASpringAnimation.stiffness` UIKit itself creates for every iOS
 * spring the app ports, read from a Mac Catalyst build of `UIView.animate(…usingSpringWithDamping…)`.
 */
class IosSpringTest {

    private fun assertMatchesUiKit(what: String, seconds: Float, damping: Float, uiKit: Float) {
        val stiffness = iosSpringStiffness(seconds, damping)
        assertEquals("$what: stiffness $stiffness, UIKit $uiKit", uiKit, stiffness, uiKit * 0.001f)
    }

    @Test
    fun `the ported iOS springs are as stiff as UIKit makes them`() {
        assertMatchesUiKit("signup page slide, launch rise", 0.7f, 0.65f, 220.180f)
        assertMatchesUiKit("launch widen", 0.6f, 0.65f, 299.689f)
        assertMatchesUiKit("PIN, Signup and Home stack", 0.8f, 0.75f, 137.414f)
        assertMatchesUiKit("Settings and map place pop-up", 0.6f, 0.7f, 268.941f)
        assertMatchesUiKit("alert slide-in", 0.5f, 0.7f, 387.275f)
    }
}
