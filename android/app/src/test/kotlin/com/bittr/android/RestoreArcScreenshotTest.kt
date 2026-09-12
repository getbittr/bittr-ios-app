package com.bittr.android

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.feature.signup.RestoreScreen
import java.io.File
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders the one screen the restore arc adds, light and dark, on the JVM.
 *
 * Restore2 and Restore3 are [com.bittr.android.feature.signup.PinScreen] in different
 * embeddings and are already captured as `arc-5-pin-set` / `arc-6-pin-confirm` by
 * [CreateWalletArcScreenshotTest]; capturing them again under a second name would
 * suggest there is a second thing to look at. Home is `arc-8-home` there too.
 *
 * So this covers the genuinely new question: **twelve numbered fields, stacked inside
 * the mock's card, on a phone.** Three fit on Verify with room to spare. Twelve is the
 * case where the card can run past the screen, and looking is the only way to know.
 *
 * **This test cannot fail the build** — capture needs Robolectric's native graphics
 * and reports as skipped without them. Nothing here asserts pixels; see
 * [ScaffoldScreenshotTest] for why a golden-image diff would be the wrong tool.
 *
 * Output: `app/build/screenshots/<variant>/restore-*.png`.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RestoreArcScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun `renders the restore screen to PNGs`() {
        val outputDir = System.getProperty("bittr.screenshot.dir")
            ?: error("bittr.screenshot.dir is not set — see testOptions in app/build.gradle.kts")

        val dark = mutableStateOf(false)
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                val isDark by dark
                BittrTheme(darkTheme = isDark) {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        RestoreScreen(onSubmit = {}, onCancel = {})
                    }
                }
            }
        }
        composeRule.waitForIdle()

        val written = mutableListOf<String>()
        listOf(false, true).forEach { isDark ->
            composeRule.runOnIdle { dark.value = isDark }
            composeRule.waitForIdle()

            val bitmap = try {
                composeRule.onRoot().captureToImage().asAndroidBitmap()
            } catch (e: Throwable) {
                assumeNoException("Screenshot capture unavailable on this host", e)
                return
            }

            val file = File(outputDir).apply { mkdirs() }
                .resolve("restore-1-phrase${if (isDark) "-dark" else ""}.png")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            written += "${file.name} (${bitmap.width}x${bitmap.height})"
        }

        println("Restore arc screenshots in $outputDir:\n  " + written.joinToString("\n  "))
    }
}
