package com.bittr.android.core.permissions

import android.Manifest

/**
 * The complete set of runtime permissions this app is allowed to ask for, and the
 * approved copy each one is bound to.
 *
 * Two of these are not engineering choices. The approved permission rationales
 * (BIT-15 → `decision-brief`, §D1 and §D3) make **factual claims about the build**,
 * and compliance signed them off as binding on the implementation rather than as
 * preferences (BIT-36, BIT-57). Changing what the code does here does not make the
 * copy stale, it makes the shipped copy false — and corrected copy goes back through
 * compliance before it can ship.
 *
 * ### Camera — "Nothing is recorded"
 *
 * > The camera is used only to read the code in front of it. Nothing is recorded.
 *
 * True on iOS because the scanner attaches an `AVCaptureMetadataOutput` limited to
 * `[.qr]` and nothing else — no `AVCapturePhotoOutput`, no `AVCaptureMovieFileOutput`,
 * no retained buffer (`ScannerViewController.swift:89-95`). The Android equivalent is
 * CameraX `ImageAnalysis` plus barcode scanning, and **no capture use case** — no
 * stills, no video. Binding one alongside the analyser turns a shipped sentence into
 * a false statement. Enforced by `CameraCaptureGuardTest` in `:app`, which is also
 * why this file names the capture use cases by description rather than by symbol.
 *
 * ### Location — "approximate"
 *
 * > To centre the map on where you are, bittr needs your approximate location.
 *
 * True on iOS because the map asks for `kCLLocationAccuracyHundredMeters`
 * (`Map/MapViewController.swift:80`). The Android equivalent is
 * [Manifest.permission.ACCESS_COARSE_LOCATION] **only**. This is not merely about
 * which value the app reads: requesting the fine-location permission changes the
 * system dialog itself, adding the *Precise / Approximate* toggle and defaulting it
 * to precise. Coarse alone can only ever grant approximate, which is what makes the
 * sentence true no matter what the user taps. Enforced by
 * `LocationPrecisionGuardTest` in `:app`, which is why the precise permission is
 * described here rather than named — [LOCATION] below is the only location
 * permission this repo is allowed to spell out.
 *
 * ### Notifications
 *
 * `POST_NOTIFICATIONS` carries no accuracy or retention claim, so it is listed here
 * for completeness rather than as a constraint. Its permanently-denied copy does
 * bind something — see [AppSettings].
 */
object BittrPermissions {

    /**
     * The scanner (DEV-37). Grants frames for analysis. It also *would* grant
     * recording — the permission does not distinguish — which is exactly why the
     * "nothing is recorded" claim rests on the use cases the scanner binds rather
     * than on what the user was asked for.
     */
    const val CAMERA: String = Manifest.permission.CAMERA

    /**
     * The map (DEV-54). **Coarse only** — see the class doc. There is deliberately
     * no `FINE` constant here: the single approved place to name a location
     * permission is this line, so the guard test can treat every other mention as a
     * regression.
     */
    const val LOCATION: String = Manifest.permission.ACCESS_COARSE_LOCATION

    /** Receive-payment alerts (DEV-63). API 33+; a no-op request below that. */
    const val NOTIFICATIONS: String = Manifest.permission.POST_NOTIFICATIONS
}
