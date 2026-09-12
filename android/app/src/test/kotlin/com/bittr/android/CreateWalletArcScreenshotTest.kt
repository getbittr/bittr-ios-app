package com.bittr.android

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
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
 * **Capture cannot fail the build.** It needs Robolectric's native graphics; on a host
 * without them this reports as skipped, never red. Nothing here asserts pixels — see
 * [ScaffoldScreenshotTest] for why a golden-image diff would be the wrong tool.
 *
 * A [Shot.prepare] step can still be red, and should be: if the clicks that put the
 * consent toggles into their checked state stop working, the alternative is a PNG named
 * `-on` showing a screen that is off, which is worse than a failure.
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

        val SCREENS: List<Shot> = listOf(
            Shot("1-start") { SignupStartScreen() },
            Shot("2-confirm") { ConfirmScreen(onUnderstood = {}, onBack = {}) },
            /**
             * The same screen with both toggles on — BIT-95.
             *
             * The checked switch had never been in a PNG: this list rendered `ConfirmScreen`
             * at its initial state, which is both toggles off, so BIT-93's and BIT-94's
             * captures showed only the state that was never broken. The checked track's
             * 1.32 : 1 against the card was computed, and stayed computed, because nothing
             * drew it.
             *
             * Driven by clicking the real ids rather than by a parameter: consent is
             * deliberately not hoisted out of `ConfirmScreen` (see its note on
             * `rememberSaveable`), and tapping is also what a user does. It gets the
             * enabled "I understand" into a capture as a side effect, which is the other
             * half of this screen nothing had photographed either.
             */
            Shot(
                "2-confirm-on",
                prepare = {
                    onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).performClick()
                    onNodeWithTag(TestID.Signup.Create.Confirm.switchTwo).performClick()
                    onNodeWithTag(TestID.Signup.Create.Confirm.switchOne).assertIsOn()
                    onNodeWithTag(TestID.Signup.Create.Confirm.switchTwo).assertIsOn()
                },
            ) { ConfirmScreen(onUnderstood = {}, onBack = {}) },
            Shot("3-phrase") { MnemonicScreen(mnemonic = PHRASE, onNext = {}) },
            Shot("4-verify") {
                VerifyScreen(
                    challenge = SeedChallenge(PHRASE, listOf(1, 4, 11)),
                    onSubmit = {},
                    onBack = {},
                )
            },
            Shot("5-pin-set") {
                PinScreen(title = "Set a PIN for secure access to your wallet", onSubmit = {})
            },
            Shot("6-pin-confirm") {
                PinScreen(
                    title = "Confirm your PIN",
                    onSubmit = {},
                    onBack = {},
                )
            },
            Shot("7-ready") { ReadyScreen(onContinue = {}, onSkip = {}) },
            // Where the arc lands: Home in its no-funds state (BIT-98).
            Shot("8-home") { HomeNoFunds() },
        )
    }

    /**
     * One capture: a file-name stem, the screen, and anything that has to happen to it
     * before the shutter.
     *
     * [prepare] runs against the live composition after the screen is on screen. It is
     * how a screen whose interesting state is internal — the consent toggles — gets
     * photographed in that state without the screen growing a parameter it only has for
     * the benefit of a test.
     */
    data class Shot(
        val name: String,
        val prepare: ComposeTestRule.() -> Unit = {},
        val content: @Composable () -> Unit,
    )

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
                        val shot = SCREENS[index.intValue]
                        // Keyed so that swapping the screen under the camera discards the
                        // previous one's state. Checked by removing it: the two
                        // `ConfirmScreen` shots are the same composable at the same call
                        // site, the `2-confirm` toggles survive into `2-confirm-on`, and
                        // the clicks there turn consent back *off*. `prepare`'s
                        // `assertIsOn` catches that rather than writing a PNG named `-on`
                        // of the state it exists to contrast — but the key is what stops
                        // it happening, and the assertion is the backstop.
                        key(shot.name, isDark) { shot.content() }
                    }
                }
            }
        }
        composeRule.waitForIdle()

        val written = mutableListOf<String>()
        SCREENS.forEachIndexed { i, shot ->
            val name = shot.name
            listOf(false, true).forEach { isDark ->
                composeRule.runOnIdle {
                    index.intValue = i
                    dark.value = isDark
                }
                composeRule.waitForIdle()
                shot.prepare(composeRule)
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
