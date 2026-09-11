package com.bittr.android.feature.scanner

/**
 * What the scanner is showing.
 *
 * Four states, and three of them are alerts over the same screen — on iOS the
 * scanner view is always there and the alert sits on top of it
 * (`ScannerViewController.viewDidAppear`), which is why
 * `shared/flows/features/send_onchain.yaml:78-81` asserts `scanner.scannerView` and
 * `alert.button.0` in the same breath. The Android screen keeps that shape.
 */
internal sealed interface ScannerUiState {

    /** Camera running, frames going to the analyser. The only state that scans. */
    data object Scanning : ScannerUiState

    /**
     * Explaining why the camera is needed, before asking the system for it.
     *
     * Buttons: *Cancel* / *Continue*. Continue is what triggers the real request.
     */
    data object Rationale : ScannerUiState

    /**
     * Asking again would return the same denial without showing anything.
     *
     * Buttons: *Cancel* / *Settings*.
     */
    data object PermanentlyDenied : ScannerUiState

    /** No camera on this device at all. Button: *Okay*, which closes the scanner. */
    data object NoCamera : ScannerUiState
}

/**
 * Which state the scanner opens in, and where a permission answer moves it to.
 *
 * Kept apart from the composable because the interesting half of this screen is the
 * half an emulator is needed to exercise, and this way it isn't. The rules below are
 * two lines each and each one has a wrong version that ships and looks fine.
 */
internal object ScannerPermissionFlow {

    /**
     * The state to open in.
     *
     * Hardware first: a device with no camera cannot be helped by a permission, and
     * asking for one before saying so would be a dialog the user cannot act on.
     */
    fun initial(hasCamera: Boolean, granted: Boolean): ScannerUiState = when {
        !hasCamera -> ScannerUiState.NoCamera
        granted -> ScannerUiState.Scanning
        else -> ScannerUiState.Rationale
    }

    /**
     * Where the system's answer leaves us.
     *
     * [canAskAgain] is `shouldShowRequestPermissionRationale`, read **after** the
     * request returns. Reading it before is the trap: it is `false` both for an app
     * that has never asked and for one that has been permanently denied, so an
     * opening screen that consults it sends every first-time user to a dead end
     * telling them to go to Settings — and the bug is invisible to anyone whose
     * device has already granted the permission, which includes every developer who
     * has run the app once.
     *
     * Asked and refused, but askable again, goes back to [ScannerUiState.Rationale]
     * rather than to a dead end: on Android the first refusal is one tap and is
     * often a misfire, and the second refusal is the one that means it.
     */
    fun afterRequest(granted: Boolean, canAskAgain: Boolean): ScannerUiState = when {
        granted -> ScannerUiState.Scanning
        canAskAgain -> ScannerUiState.Rationale
        else -> ScannerUiState.PermanentlyDenied
    }
}
