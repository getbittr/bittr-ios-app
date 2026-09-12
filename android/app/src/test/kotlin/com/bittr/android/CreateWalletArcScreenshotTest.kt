package com.bittr.android

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.seed.SeedChallenge
import com.bittr.android.feature.signup.ConfirmScreen
import com.bittr.android.feature.signup.MnemonicScreen
import com.bittr.android.feature.signup.PinScreen
import com.bittr.android.feature.signup.ReadyScreen
import com.bittr.android.feature.signup.SignupStartScreen
import com.bittr.android.feature.signup.VerifyScreen
import com.bittr.android.feature.home.HomeNoFunds
import java.io.File
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders every screen of the create-wallet arc to a PNG, light and dark, on the JVM.
 *
 * Same reasoning as [ScaffoldScreenshotTest], applied to the thing BIT-93 actually
 * asks about: "a working Android app, in the bittr design". Whether the arc is in the
 * bittr design is a question about pixels, and answering it should not require
 * installing Android Studio or booting an emulator — especially while the Android CI
 * runner is still waiting to be stood up.
 *
 * It renders the screens directly rather than driving the arc, because the phrase a
 * real run would produce is a real seed, and this writes PNGs to disk. The phrase
 * below is the public BIP-39 test vector instead.
 *
 * **This test cannot fail the build.** Capture needs Robolectric's native graphics; on
 * a host without them it reports as skipped, never red. Nothing here asserts pixels —
 * see [ScaffoldScreenshotTest] for why a golden-image diff would be the wrong tool.
 *
 * It goes through [MainActivity] rather than `createComposeRule()` because the bare
 * rule needs `ComponentActivity` in the manifest, which only
 * `debugImplementation(ui-test-manifest)` provides — so the plain rule passes on the
 * debug variant and fails on the release one.
 *
 * Output: `app/build/screenshots/<variant>/arc-*.png`.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CreateWalletArcScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private companion object {
        /**
         * The BIP-39 all-zero-entropy test vector — public, worthless, and the same
         * phrase `StubWalletService` uses. Deliberately not a generated one.
         */
        val PHRASE = Mnemonic(
            listOf(
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about",
            ),
        )

        val SCREENS: List<Pair<String, @Composable () -> Unit>> = listOf(
            "1-start" to { SignupStartScreen() },
            "2-confirm" to { ConfirmScreen(onUnderstood = {}, onBack = {}) },
            "3-phrase" to { MnemonicScreen(mnemonic = PHRASE, onNext = {}) },
            "4-verify" to {
                VerifyScreen(
                    challenge = SeedChallenge(PHRASE, listOf(1, 4, 11)),
                    onSubmit = {},
                    onBack = {},
                )
            },
            "5-pin-set" to {
                PinScreen(title = "Set a PIN for secure access to your wallet", onSubmit = {})
            },
            "6-pin-confirm" to {
                PinScreen(
                    title = "Confirm your PIN",
                    onSubmit = {},
                    onBack = {},
                )
            },
            "7-ready" to { ReadyScreen(onContinue = {}, onSkip = {}) },
            // Where the arc lands: Home in its no-funds state (BIT-98).
            "8-home" to { HomeNoFunds() },
        )
    }

    @Test
    fun `renders the create-wallet arc to PNGs`() {
        val outputDir = System.getProperty("bittr.screenshot.dir")
            ?: error("bittr.screenshot.dir is not set — see testOptions in app/build.gradle.kts")

        // The screen under the camera is state the test drives, rather than a fresh
        // composition per capture: the rule's own setContent refuses to run because
        // MainActivity has already set its content, so this replaces the activity's
        // content once and then swaps what that content draws.
        val index = mutableIntStateOf(0)
        val dark = mutableStateOf(false)
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                val isDark by dark
                BittrTheme(darkTheme = isDark) {
                    // The Surface is what `BittrApp` puts under every screen — it
                    // carries both the background and `LocalContentColor`. Rendering
                    // without it would show black text on a dark surface and blame the
                    // screens for a defect the harness introduced.
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
                    .resolve("arc-$name${if (isDark) "-dark" else ""}.png")
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                written += "${file.name} (${bitmap.width}x${bitmap.height})"
            }
        }

        println("Create-wallet arc screenshots in $outputDir:\n  " + written.joinToString("\n  "))
    }
}
