package com.bittr.android.feature.scanner

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScannerCameraAvailabilityTest {

    @Test
    fun `a declared camera with no camera device is no camera`() {
        // The CI emulator with -camera-back none: every camera feature declared, zero devices.
        assertFalse(ScannerPermissionFlow.hasCamera(declaresFeature = true, cameraCount = 0))
        assertEquals(
            ScannerUiState.NoCamera,
            ScannerPermissionFlow.initial(hasCamera = ScannerPermissionFlow.hasCamera(true, 0), granted = true),
        )
    }

    @Test
    fun `a camera needs both the feature and a device`() {
        assertTrue(ScannerPermissionFlow.hasCamera(declaresFeature = true, cameraCount = 1))
        assertFalse(ScannerPermissionFlow.hasCamera(declaresFeature = false, cameraCount = 1))
    }
}
