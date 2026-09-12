package com.bittr.android.feature.scanner

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.BittrTheme
import java.io.File
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog

/**
 * Renders the scanner's states to PNGs on the JVM — no emulator, no device.
 *
 * The Definition of Done asks for screenshot evidence of scanning, rationale and
 * permanently denied. Two of those three cannot be produced on a machine whose
 * camera permission is already granted, and none of them can be produced here at
 * all: emulator CI needs KVM, which the agent environment does not have. So the
 * evidence comes off the same Robolectric path `:app`'s `ScaffoldScreenshotTest`
 * established, driving [ScannerScreenContent] with each state handed to it.
 *
 * ### Why the alert is drawn separately
 *
 * A Compose `Dialog` is its own window. `captureToImage` on a dialog's root node
 * under Robolectric comes back with the *screen's* pixels cropped to the dialog's
 * size — the dialog window has no surface of its own to read — so the obvious
 * version of this test produces three convincing images of the wrong thing. The
 * dialog's decor view is real and does draw, so it is drawn onto the screen capture
 * here at the position the window manager centres it, which is what a device shows.
 *
 * What the images are worth: real Compose layout, real `BittrTheme` tokens, the real
 * approved copy. What they are not: a device. Three differences worth knowing before
 * reading anything into the output —
 *
 * - **No scrim.** The dim behind a dialog is a window attribute, not drawn content,
 *   so `decorView.draw` does not produce it. On a device the screen behind the alert
 *   is darkened and the card reads as a card; here it sits on an undimmed
 *   background.
 * - **No camera.** The scanning state shows the frame empty, because a JVM has no
 *   camera to put in it.
 * - **Different text rasterisation.** Robolectric's native graphics is not Android's
 *   font stack.
 *
 * The emulator run and Maestro's own `takeScreenshot` are what cover appearance on
 * hardware.
 *
 * **This test cannot fail the build.** Capture needs Robolectric's native graphics
 * and its platform-specific native library; where that is unavailable this reports
 * as *skipped*, never red. Breaking `./gradlew test` on someone's laptop would be a
 * bad trade for a picture — the same rule `ScaffoldScreenshotTest` follows.
 *
 * Output: `feature/scanner/build/screenshots/scanner-<state>.png` (see
 * `bittr.screenshot.dir` in this module's `build.gradle.kts`).
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScannerStatesScreenshotTest {

    @get:Rule
    val composeRule = createComposeRule()

    private var state: ScannerUiState by mutableStateOf(ScannerUiState.Scanning)

    @Test
    fun `renders each scanner state to a PNG`() {
        val outputDir = System.getProperty("bittr.screenshot.dir")
            ?: error(
                "bittr.screenshot.dir is not set — see testOptions in " +
                    "feature/scanner/build.gradle.kts",
            )

        composeRule.setContent {
            BittrTheme {
                ScannerScreenContent(
                    state = state,
                    onClose = {},
                    onCancel = {},
                    onContinue = {},
                    onOpenSettings = {},
                )
            }
        }

        val directory = File(outputDir).apply { mkdirs() }

        val states = listOf(
            "scanning" to ScannerUiState.Scanning,
            "rationale" to ScannerUiState.Rationale,
            "permanently-denied" to ScannerUiState.PermanentlyDenied,
            // Not one of the DoD's three, but it is the state the existing
            // send_onchain flow actually meets — the simulator has no camera — so it
            // is the first one an emulator run will produce.
            "no-camera" to ScannerUiState.NoCamera,
        )

        for ((name, scannerState) in states) {
            composeRule.runOnIdle { state = scannerState }

            val screen = try {
                captureScreenWindow()
            } catch (e: Throwable) {
                // Native graphics unavailable on this host. Skip; never fail.
                assumeNoException("Screenshot capture unavailable on this host", e)
                return
            }

            val composited = screen.copy(Bitmap.Config.ARGB_8888, /* isMutable = */ true)
            drawAlertOnto(composited)

            val file = directory.resolve("scanner-$name.png")
            file.outputStream().use { composited.compress(Bitmap.CompressFormat.PNG, 100, it) }

            // The path is the point of the test — print it where a human sees it.
            println(
                "Scanner screenshot ($name): ${file.absolutePath} " +
                    "(${composited.width}x${composited.height})",
            )
        }
    }

    /**
     * The screen behind any alert.
     *
     * Picked by area rather than by `onRoot()`, which resolves to whichever root the
     * framework considers current — the dialog's, once one is up — and so returns
     * the alert twice over instead of the screen underneath it. The screen's window
     * is the full-size one; a dialog's is sized to its own content.
     */
    private fun captureScreenWindow(): Bitmap =
        composeRule.onAllNodes(isRoot()).fetchSemanticsNodes()
            .indices
            .map { composeRule.onAllNodes(isRoot())[it].captureToImage().asAndroidBitmap() }
            .maxBy { it.width.toLong() * it.height }

    /**
     * Draws the alert currently on screen, if there is one, where the window manager
     * puts it: centred.
     *
     * A dialog's decor view is sized to its own content rather than to the screen,
     * so its pixels have to be offset into place by hand. Getting that wrong is
     * visible in the output, which is the whole point of producing output.
     */
    private fun drawAlertOnto(screen: Bitmap) {
        val decor = ShadowDialog.getLatestDialog()?.takeIf { it.isShowing }?.window?.decorView
            ?: return
        if (decor.width == 0 || decor.height == 0) return

        val canvas = Canvas(screen)
        canvas.translate(
            ((screen.width - decor.width) / 2f).coerceAtLeast(0f),
            ((screen.height - decor.height) / 2f).coerceAtLeast(0f),
        )
        decor.draw(canvas)
    }
}
