package com.bittr.android.feature.scanner

/**
 * The scanner's user-visible words, verbatim as approved.
 *
 * Founder-approved 2026-09-11 (BIT-15 -> `decision-brief` D1 - DEV-37), and carried
 * to this platform as a specification rather than a draft. Two of these sentences
 * are **factual claims about this build** and compliance signed them off as binding
 * on the implementation (BIT-36, BIT-57):
 *
 * - *"Nothing is recorded"* is true because [ScannerCameraSession] binds an analysis
 *   use case and a viewfinder and no capture use case. `CameraCaptureGuardTest`
 *   fails the build if that stops being so.
 * - *"You can also paste an address or an invoice instead of scanning it"* is true
 *   because the paste control on Send (`TestID.Send.pasteButton`) routes through the
 *   same entry point a scan does — `handleScannedOrPastedString`
 *   (`AddressParsing.swift:15`) — which handles both an address and an invoice.
 *   Compliance verified that rather than taking it on trust, which is why the
 *   sentence shipped without a caveat.
 *
 * ### Words now, ids when BIT-12 lands
 *
 * [Id] records the string id each block of copy will be read from once BIT-12 moves
 * both platforms onto `shared/strings/`. The words are already approved, so the
 * screen is built against the words and the ids are confirmed after — the two
 * cannot drift, because the id is written down next to the text it names.
 *
 * `scanningnotavailable` and `scanningnotsupported` are the exception: they already
 * ship on iOS (`Language.swift:115-116`) and are reused **unchanged**. Reworded
 * copy that already ships goes back through compliance; that is what happened to
 * the two settings-path strings, and it is why those got their own commit inside
 * BIT-12 rather than being folded into a file move.
 */
internal object ScannerCopy {

    /** The `shared/strings/` ids these words will be looked up by (BIT-12). */
    object Id {
        const val HEADER = "scanner"
        const val CLOSE = "close"
        const val PERMISSION_TITLE = "camerapermission"
        const val RATIONALE_BODY = "camerapermission2"
        const val PERMANENTLY_DENIED_BODY = "camerapermission3"
        const val NO_CAMERA_TITLE = "scanningnotsupported"
        const val NO_CAMERA_BODY = "scanningnotavailable"
        const val CANCEL = "cancel"
        const val CONTINUE = "continue"
        const val SETTINGS = "settings"
        const val OKAY = "okay"
    }

    const val HEADER = "Scanner"
    const val CLOSE = "Close"

    const val PERMISSION_TITLE = "Camera access"

    /**
     * Shown *before* the system dialog, not after a denial.
     *
     * Android gives an app one chance to ask and no way to explain itself inside the
     * system dialog, so the explanation has to come first or not at all. This is
     * also how iOS sequences it, and the *Cancel / Continue* pair is the tell:
     * Continue is what triggers the real request.
     */
    const val RATIONALE_BODY =
        "To scan a bitcoin address or an invoice, bittr needs to use your camera.\n\n" +
            "The camera is used only to read the code in front of it. Nothing is recorded."

    /**
     * Shown once asking again would do nothing.
     *
     * The second sentence names two things that must both be true, and both are:
     * the Settings button navigates ([com.bittr.android.core.permissions.AppSettings]),
     * and paste handles an address and an invoice alike.
     *
     * Note what this copy no longer contains. It used to spell out a settings path
     * for the user to walk; Ruben's `genericise` decision took that out on both
     * platforms, because OEM settings apps disagree about where that page lives and
     * a wrong path is worse than none. The copy now assumes a button that navigates,
     * so the button has to navigate.
     */
    const val PERMANENTLY_DENIED_BODY =
        "bittr doesn't have permission to use your camera, so it can't scan a code.\n\n" +
            "Allow camera access in your device settings, then try again. You can also " +
            "paste an address or an invoice instead of scanning it."

    /** Already ships on iOS. Reused unchanged — see the class doc. */
    const val NO_CAMERA_TITLE = "Scanning not supported"

    /** Already ships on iOS. Reused unchanged — see the class doc. */
    const val NO_CAMERA_BODY =
        "Your device does not support scanning a code from an item. " +
            "Please use a device with a camera."

    const val CANCEL = "Cancel"
    const val CONTINUE = "Continue"
    const val SETTINGS = "Settings"
    const val OKAY = "Okay"
}
