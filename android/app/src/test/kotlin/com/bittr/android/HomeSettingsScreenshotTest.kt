package com.bittr.android

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.feature.home.HomeNoFunds
import com.bittr.android.feature.settings.DeviceNoNode
import com.bittr.android.feature.settings.LightningQuestionScreen
import com.bittr.android.feature.settings.SettingsScreen
import java.io.File
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders BIT-98's four screens to PNGs, light and dark, on the JVM.
 *
 * Same reasoning as [ScaffoldScreenshotTest] and [CreateWalletArcScreenshotTest],
 * applied to the half of this issue's Done that is a question about pixels: "dressed in
 * the BIT-63 tokens" is not something `assembleDebug` can answer and not something a
 * reviewer should need an emulator to check.
 *
 * **This test cannot fail the build.** Capture needs Robolectric's native graphics; on a
 * host without them it reports as skipped, never red. Nothing here asserts pixels — see
 * [ScaffoldScreenshotTest] for why a golden-image diff would be the wrong tool.
 *
 * The website pages are **not** here. A `WebView` under Robolectric is a shadow that
 * loads nothing, so their PNGs would show bittr's header over a blank rectangle and
 * invite the conclusion that the page is broken. [SettingsFlowTest] covers what can
 * honestly be checked off-device about them: that they open and close.
 *
 * Output: `app/build/screenshots/<variant>/settings-*.png`.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HomeSettingsScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private companion object {
        /**
         * The four screens in the order the flow reaches them. Each is the same
         * `@Composable` the app composes, taking its state from its own defaults —
         * which for every one of them is the no-node state this build is always in.
         */
        val SCREENS: List<Pair<String, @Composable () -> Unit>> = listOf(
            "1-home" to { HomeNoFunds() },
            "2-settings" to {
                SettingsScreen(onDown = {}, onOpenWebsite = {}, onOpenDevice = {})
            },
            "3-device" to { DeviceNoNode() },
            "4-lightning-question" to { LightningQuestionScreen(onDown = {}) },
        )
    }

    @Test
    fun `renders Home and the Settings tree to PNGs`() {
        val outputDir = System.getProperty("bittr.screenshot.dir")
            ?: error("bittr.screenshot.dir is not set — see testOptions in app/build.gradle.kts")

        // The screen under the camera is state the test drives rather than a fresh
        // composition per capture — see [CreateWalletArcScreenshotTest] for why the
        // rule's own setContent cannot be used here.
        val index = mutableIntStateOf(0)
        val dark = mutableStateOf(false)
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                val isDark by dark
                BittrTheme(darkTheme = isDark) {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        SCREENS[index.intValue].second()
                    }
                }
            }
        }
        composeRule.waitForIdle()

        val written = mutableListOf<String>()
        SCREENS.forEachIndexed { i, (name, _) ->
            listOf(false, true).forEach { isDark ->
                composeRule.runOnIdle {
                    index.intValue = i
                    dark.value = isDark
                }
                composeRule.waitForIdle()

                val bitmap = try {
                    composeRule.onRoot().captureToImage().asAndroidBitmap()
                } catch (e: Throwable) {
                    // Native graphics unavailable on this host. Skip; never fail.
                    assumeNoException("Screenshot capture unavailable on this host", e)
                    return
                }

                val file = File(outputDir).apply { mkdirs() }
                    .resolve("settings-$name${if (isDark) "-dark" else ""}.png")
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                written += "${file.name} (${bitmap.width}x${bitmap.height})"
            }
        }

        println("Home and Settings screenshots in $outputDir:\n  " + written.joinToString("\n  "))
    }
}
