package com.bittr.android.feature.scanner

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The four states and the two decisions that pick between them.
 *
 * Every case below is one a user reaches by doing something ordinary, and the three
 * marked ones are the states a developer's own device can no longer produce once it
 * has granted the permission — which is exactly why they are asserted here rather
 * than checked by opening the app.
 */
class ScannerPermissionFlowTest {

    @Test
    fun `a granted permission opens straight into scanning`() {
        assertEquals(
            ScannerUiState.Scanning,
            ScannerPermissionFlow.initial(hasCamera = true, granted = true),
        )
    }

    @Test
    fun `an ungranted permission explains itself before asking`() {
        assertEquals(
            ScannerUiState.Rationale,
            ScannerPermissionFlow.initial(hasCamera = true, granted = false),
        )
    }

    /**
     * Hardware is checked before permission, both ways round.
     *
     * A device with no camera cannot be helped by granting one, and the second case
     * is the one that catches a reordered `when`: a permission that has somehow been
     * granted on a camera-less device must still land on the no-camera state, not on
     * a viewfinder that will never receive a frame.
     */
    @Test
    fun `no camera wins over the permission either way`() {
        assertEquals(
            ScannerUiState.NoCamera,
            ScannerPermissionFlow.initial(hasCamera = false, granted = false),
        )
        assertEquals(
            ScannerUiState.NoCamera,
            ScannerPermissionFlow.initial(hasCamera = false, granted = true),
        )
    }

    @Test
    fun `granting the permission starts the camera`() {
        assertEquals(
            ScannerUiState.Scanning,
            ScannerPermissionFlow.afterRequest(granted = true, canAskAgain = true),
        )
        assertEquals(
            ScannerUiState.Scanning,
            ScannerPermissionFlow.afterRequest(granted = true, canAskAgain = false),
        )
    }

    /**
     * One refusal is not a permanent one.
     *
     * Android's first denial is a single tap and is frequently a misfire. Sending
     * that user to a screen telling them to go to Settings — when the app can simply
     * ask again — is a dead end they did not choose.
     */
    @Test
    fun `a refusal that can be asked again goes back to the explanation`() {
        assertEquals(
            ScannerUiState.Rationale,
            ScannerPermissionFlow.afterRequest(granted = false, canAskAgain = true),
        )
    }

    @Test
    fun `a refusal that cannot be asked again offers settings`() {
        assertEquals(
            ScannerUiState.PermanentlyDenied,
            ScannerPermissionFlow.afterRequest(granted = false, canAskAgain = false),
        )
    }
}
