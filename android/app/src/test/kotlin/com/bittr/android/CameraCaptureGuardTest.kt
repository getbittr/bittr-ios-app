package com.bittr.android

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Keeps the scanner's approved copy true: **nothing is recorded.**
 *
 * The shipped camera rationale (DEV-37, BIT-15 → `decision-brief` §D1) is:
 *
 * > The camera is used only to read the code in front of it. Nothing is recorded.
 *
 * Compliance signed that off as binding on the build rather than on preferences
 * (BIT-36, BIT-57). It is a factual claim about the app, and it is true on iOS by
 * construction: the scanner attaches an `AVCaptureMetadataOutput` restricted to
 * `[.qr]` and nothing else — no `AVCapturePhotoOutput`, no
 * `AVCaptureMovieFileOutput`, no retained buffer
 * (`ScannerViewController.swift:89-95`).
 *
 * The Android equivalent is CameraX **`ImageAnalysis` only**. `ImageAnalysis`
 * hands each frame to a barcode analyser and closes it; nothing is written and
 * nothing outlives the frame. `ImageCapture` and `VideoCapture` are the two use
 * cases that change that answer, and adding either is a one-line change to a
 * `bindToLifecycle` call.
 *
 * ### Why a guard and not a code review
 *
 * This is the rare rule where the code keeps working perfectly when it breaks. A
 * scanner with an `ImageCapture` bound alongside the analyser scans exactly as
 * well, passes every flow, and looks right on screen. The only thing that changed
 * is that a sentence bittr has shipped to users, and had reviewed for compliance,
 * stopped being true. Nothing else in the build can notice that.
 *
 * ### If you need one of these
 *
 * Say so on the issue *before* the screen ships. The copy has to change first, and
 * changed copy goes back through compliance — the order matters, because the
 * alternative is shipping a false statement and correcting it afterwards. Do not
 * add a name to [ALLOWED_FILES] to get past this test; the list is for files that
 * quote the API names in prose, not for files that call them.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class CameraCaptureGuardTest {

    private companion object {

        /**
         * CameraX use cases and platform APIs that persist a frame.
         *
         * `ImageAnalysis` is deliberately absent — it is the path this rule steers
         * towards. `takePicture` covers the `ImageCapture` call site even if the use
         * case arrives under an import alias, and `ACTION_IMAGE_CAPTURE` /
         * `ACTION_VIDEO_CAPTURE` cover handing the job to the system camera app,
         * which records to shared storage and is no better for this claim.
         */
        val RECORDING_SYMBOLS = listOf(
            "ImageCapture",
            "VideoCapture",
            "androidx.camera.video",
            "MediaRecorder",
            "takePicture",
            "ACTION_IMAGE_CAPTURE",
            "ACTION_VIDEO_CAPTURE",
        )

        /** Gradle coordinates that bring a capture use case in as a dependency. */
        val RECORDING_ARTEFACTS = listOf("camera-video", "camera-extensions")

        /**
         * The only file allowed to name these APIs, because it is the one that
         * bans them.
         *
         * Kept to one entry deliberately. `BittrPermissions.kt` documents the same
         * rule and is *not* here — it describes the capture use cases rather than
         * naming them, so the ban stays total everywhere the ban is not defined.
         */
        val ALLOWED_FILES = setOf("CameraCaptureGuardTest.kt")

        const val APP_MANIFEST = "app/src/main/AndroidManifest.xml"
    }

    @Test
    fun `no camera capture use case is reachable from the app`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val text = file.readText()
                val hit = RECORDING_SYMBOLS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (references $hit)"
            }

        assertTrue(
            "The scanner's approved copy says \"Nothing is recorded\" (DEV-37). The camera " +
                "path must be analysis-only — CameraX ImageAnalysis plus barcode scanning, " +
                "with no ImageCapture and no VideoCapture bound alongside it. A capture use " +
                "case scans just as well and passes every flow, so nothing but this test can " +
                "tell you the sentence stopped being true.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "If a capture path is genuinely needed, raise it on BIT-57 before the screen " +
                "ships: the copy changes first, and changed copy goes back through compliance.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `no capture-only CameraX artefact is on the dependency graph`() {
        val offenders = SourceTree.buildFiles()
            .mapNotNull { file ->
                val text = file.readText()
                val hit = RECORDING_ARTEFACTS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (declares $hit)"
            }

        assertTrue(
            "androidx.camera:camera-video exists to record video, and camera-extensions " +
                "exists to post-process stills — neither has a use in a barcode scanner, and " +
                "camera-video declares RECORD_AUDIO in its own manifest, which would put a " +
                "recording capability on the Play listing before any code called it. " +
                "camera-core, camera-camera2 and camera-lifecycle are the artefacts an " +
                "analysis-only scanner needs.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the app manifest holds RECORD_AUDIO out of the merge`() {
        val manifest = SourceTree.root.resolve(APP_MANIFEST)
        assertTrue("$APP_MANIFEST does not exist.", manifest.isFile)

        assertTrue(
            "$APP_MANIFEST no longer removes android.permission.RECORD_AUDIO. The manifest " +
                "merger unions permissions across every dependency, so a library that " +
                "declares RECORD_AUDIO puts it in the APK and on the store listing without " +
                "anyone in this repo typing it — and \"nothing is recorded\" is hard to read " +
                "next to a microphone permission. Restore:\n" +
                "  <uses-permission android:name=\"android.permission.RECORD_AUDIO\" " +
                "tools:node=\"remove\" />",
            Regex(
                """RECORD_AUDIO"\s+tools:node="remove"""",
            ).containsMatchIn(manifest.readText()),
        )
    }

    /**
     * The other half of the manifest claim: what the merger actually produced.
     *
     * The source check above proves the removal directive is written down. This
     * proves it won — Robolectric's `PackageManager` reads the *merged* manifest,
     * the one that ships. A `tools:replace` in a dependency, or a merger rule
     * nobody expected, would pass the first test and fail this one.
     */
    @Test
    fun `the merged manifest requests no recording permission`() {
        val context = RuntimeEnvironment.getApplication()
        val requested = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toList()
            .orEmpty()

        assertFalse(
            "The merged manifest requests android.permission.RECORD_AUDIO. The scanner's " +
                "approved copy (DEV-37) says nothing is recorded, and a microphone " +
                "permission on the listing contradicts it whether or not any code uses it. " +
                "Merged permission set: $requested",
            "android.permission.RECORD_AUDIO" in requested,
        )
    }
}
