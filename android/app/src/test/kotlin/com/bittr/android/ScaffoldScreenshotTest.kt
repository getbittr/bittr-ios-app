package com.bittr.android

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * Renders the launched app to a PNG on the JVM — no emulator, no device, no IDE.
 *
 * This exists because "does the scaffold look right?" was, until now, only
 * answerable by installing Android Studio and waiting for a Gradle sync, or by
 * booting an emulator. Both are a long way to go to look at three widgets, and the
 * Studio route additionally depends on the IDE being new enough for AGP 9.4 — a
 * failure that has nothing to do with this app and reads like the project is broken.
 *
 * What the image is worth: it comes off [MainActivity] through
 * [androidx.compose.ui.test.junit4.v2.createAndroidComposeRule], the same rule
 * [AppLaunchTest] uses, so what it draws is the real Hilt graph, the real
 * `@style/Theme.Bittr`, the real nav start destination and the real `BittrTheme`
 * tokens. It is the app, not a `@Preview` of one composable.
 *
 * What it is NOT: a golden-image test. Nothing here asserts pixels. Layout-level
 * screenshot comparison across renderers, host architectures and font stacks is the
 * classic source of a suite that fails for reasons unrelated to the change, and
 * BIT-5's rule is that a flaky pass is a failure — which cuts both ways. Font
 * rasterisation under Robolectric's native graphics is also not what the device
 * draws, so a diff here would not even be measuring the right thing. The emulator
 * run and Maestro's own `takeScreenshot` are what cover appearance on a device.
 *
 * **This test cannot fail the build.** Capture depends on Robolectric's native
 * graphics, which pulls a platform-specific native library; on a host where that is
 * unavailable this reports as *skipped* via [assumeNoException], never as red. A
 * convenience that breaks `./gradlew test` on someone's laptop would be a bad trade
 * for a picture.
 *
 * Output: `app/build/screenshots/scaffold-launch.png` (see `bittr.screenshot.dir`
 * in `app/build.gradle.kts`). Written on every unit-test run; it costs one
 * already-constructed activity and a bitmap encode.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScaffoldScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun `renders the launched app to a PNG`() {
        val outputDir = System.getProperty("bittr.screenshot.dir")
            ?: error("bittr.screenshot.dir is not set — see testOptions in app/build.gradle.kts")

        val bitmap = try {
            composeRule.onRoot().captureToImage().asAndroidBitmap()
        } catch (e: Throwable) {
            // Native graphics unavailable on this host. Skip; never fail.
            assumeNoException("Screenshot capture unavailable on this host", e)
            return
        }

        val file = File(outputDir).apply { mkdirs() }.resolve("scaffold-launch.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }

        // The path is the point of the test — print it where a human will see it.
        println("Scaffold screenshot: ${file.absolutePath} (${bitmap.width}x${bitmap.height})")
    }
}
