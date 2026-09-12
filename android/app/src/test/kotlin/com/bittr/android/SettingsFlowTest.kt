package com.bittr.android

import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.preferences.DarkModeSetting
import com.bittr.android.core.wallet.stub.StubWalletService
import com.bittr.android.feature.home.HomeScreen
import com.bittr.android.feature.home.HomeViewModel
import com.bittr.android.feature.settings.DeviceViewModel
import com.bittr.android.navigation.Routes
import com.bittr.android.navigation.settingsArea
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Walks `features/settings.yaml` on the JVM, selecting on the ids Maestro selects on.
 *
 * Sibling of [PinGateFlowTest], and the same reason for existing: the Android Maestro
 * runner is not stood up yet, so without this the claim "the Settings tree is
 * reachable" would rest on reading the source. It runs the **shipping** graph —
 * `settingsArea`, extracted from `BittrNavHost` for exactly this — so the route
 * strings, the `Routes.website` round-trip and the back stack under `header.downButton`
 * are the app's, not the test's.
 *
 * ### What this cannot prove, and what stays red until BIT-6
 *
 * Two blind spots, both shared with [PinGateFlowTest]: Robolectric reads the Compose
 * semantics tree directly, so these pass whether or not `testTagsAsResourceId` bridges
 * the tags onto the accessibility tree Maestro queries (`TestTagsAsResourceIdGuardTest`
 * guards that line), and a `WebView` under Robolectric is a shadow that loads nothing —
 * this proves the page is reachable and dismissible, not that `getbittr.com` renders.
 *
 * Three of the flow's own steps cannot pass on this build, and they are named here
 * rather than quietly skipped — `features/settings.yaml` needs a synced wallet, which
 * is why the issue's Done does not claim it goes green:
 *
 *  1. `home.headerSpinner` — waited on with `notVisible`, which an absent spinner
 *     satisfies vacuously. Green by accident, and correctly so.
 *  2. `assertVisible: text: ".*CHF.*"` on Home after the currency switch — Home has no
 *     conversion label yet, because the amount it converts is wallet-backed.
 *     [`the currency switch persists`] asserts the half that does exist: the preference
 *     is written and survives.
 *  3. `alert.button.1` on the Public-key row — iOS's synced alert offers Copy / Close.
 *     With no node the row takes iOS's *other* branch, the one-button `syncingwallet2`
 *     alert, which is what [`the node-backed rows are reachable`] asserts.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class SettingsFlowTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private val preferences =
        AppPreferences(ApplicationProvider.getApplicationContext())
    private val wallet = StubWalletService()

    /**
     * Home plus the Settings area, started where the flow starts it.
     *
     * It goes through [MainActivity] rather than `createComposeRule()` so the test
     * passes on the release unit-test variant too — `ComponentActivity` reaches the
     * manifest only through `debugImplementation(ui-test-manifest)`. The activity has
     * already set its content by the time the rule hands it over, so this replaces
     * that content rather than adding to it; see [CreateWalletArcScreenshotTest].
     *
     * The two `ViewModel`s are passed in because a unit test has no Hilt graph and
     * `:app` deliberately carries no `hilt-android-testing` dependency.
     */
    private fun launchOnHome() {
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                BittrTheme {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        val navController = rememberNavController()
                        NavHost(
                            navController = navController,
                            startDestination = Routes.HOME,
                        ) {
                            composable(Routes.HOME) {
                                HomeScreen(
                                    onSettings = { navController.navigate(Routes.SETTINGS) },
                                    viewModel = remember { HomeViewModel(wallet) },
                                )
                            }
                            // `remember`, and it is load-bearing rather than tidy:
                            // `hiltViewModel()` — what the app passes here — survives
                            // recomposition, and a plain constructor call does not.
                            // Without it every recomposition would hand Device details
                            // a fresh ViewModel, discarding the open picker or alert
                            // that the tap under test had just set.
                            settingsArea(navController) {
                                remember { DeviceViewModel(preferences, wallet) }
                            }
                        }
                    }
                }
            }
        }
        composeRule.waitForIdle()
    }

    // -----------------------------------------------------------------------
    // Settings → the three website pages → back
    // -----------------------------------------------------------------------

    /**
     * The flow's opening, and the three page round-trips.
     *
     * Each page is entered and left again, which is the part worth asserting: a web
     * view that opened but could not be dismissed would leave every later step of the
     * flow tapping into it.
     */
    @Test
    fun `every Settings item opens and comes back`() {
        launchOnHome()

        // - tapOn: id: "nav.settingsButton"
        composeRule.onNodeWithTag(TestID.Home.headerLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Nav.settingsButton).performClick()
        // - assertVisible: id: "settings.row.support"
        awaitTag(TestID.Settings.Row.support)

        listOf(
            TestID.Settings.Row.support,
            TestID.Settings.Row.privacy,
            TestID.Settings.Row.terms,
        ).forEach { row ->
            composeRule.onNodeWithTag(row).performClick()
            // - assertVisible / tapOn: id: "website.downButton"
            awaitTag(TestID.Website.downButton)
            composeRule.onNodeWithTag(TestID.Website.downButton).performClick()
            // - assertVisible: the row we came from, i.e. back on Settings.
            awaitTag(row)
        }

        // - tapOn: id: "settings.row.device" → assertVisible: device.darkmode.moonButton
        composeRule.onNodeWithTag(TestID.Settings.Row.device).performClick()
        awaitTag(TestID.Device.Darkmode.moonButton)
    }

    // -----------------------------------------------------------------------
    // Device details — the nine rows
    // -----------------------------------------------------------------------

    /**
     * Every row the flow taps is present and reachable, in iOS's order.
     *
     * `device.row.restore` is asserted too even though `settings.yaml` stops short of
     * it: `remove_wallet.yaml` taps it, that flow belongs to BIT-6's wave, and the row
     * being *absent* rather than guarded is the failure that would be found late.
     */
    @Test
    fun `all nine Device-details rows are present`() {
        openDeviceDetails()

        listOf(
            TestID.Device.Row.darkmode,
            TestID.Device.Row.language,
            TestID.Device.Row.currency,
            TestID.Device.Row.devicetoken,
            TestID.Device.Row.publickey,
            TestID.Device.Row.bittrpeer,
            TestID.Device.Row.pendingpayouts,
            TestID.Device.Row.lightningchannels,
            TestID.Device.Row.restore,
        ).forEach { row ->
            composeRule.onNodeWithTag(row).performScrollTo().assertIsDisplayed()
        }
    }

    /**
     * The dark-mode control: moon then sun, as the flow taps them, and the choice is
     * written through to the preference each time.
     *
     * The flow can only screenshot the recolouring. What it cannot see — and what
     * actually has to hold for the recolouring to survive the screen closing — is that
     * the tap reached [AppPreferences] rather than a local `remember`.
     */
    @Test
    fun `the dark-mode buttons write the choice through`() {
        openDeviceDetails()

        composeRule.onNodeWithTag(TestID.Device.Darkmode.moonButton).performClick()
        assertEquals(DarkModeSetting.Dark, preferences.darkMode.value)

        composeRule.onNodeWithTag(TestID.Device.Darkmode.sunButton).performClick()
        assertEquals(DarkModeSetting.Light, preferences.darkMode.value)

        composeRule.onNodeWithTag(TestID.Device.Darkmode.deviceButton).performClick()
        assertEquals(DarkModeSetting.Device, preferences.darkMode.value)
    }

    /** `changeLanguage()` — one option, and Cancel leaves the screen where it was. */
    @Test
    fun `the language picker cancels`() {
        openDeviceDetails()

        composeRule.onNodeWithTag(TestID.Device.Row.language).performClick()
        // - tapOn: text: "Cancel"
        composeRule.onNodeWithText(CANCEL).performClick()
        // - assertVisible: id: "device.row.language"
        composeRule.onNodeWithTag(TestID.Device.Row.language).assertIsDisplayed()
    }

    /**
     * The currency switch, both ways, tapped by the text the flow taps.
     *
     * The option labels are selected by text on purpose: the iOS pickers are native
     * `UIAlertController`s with no identifiers, so the flow has nothing else to go on
     * and these strings are load-bearing. Selecting by label here is what would fail
     * if someone reworded `Currency.label`.
     */
    @Test
    fun `the currency switch persists`() {
        openDeviceDetails()

        // - tapOn: id: "device.row.currency" → tapOn: text: "CHF"
        composeRule.onNodeWithTag(TestID.Device.Row.currency).performClick()
        composeRule.onNodeWithText(Currency.CHF.label).performClick()
        composeRule.onNodeWithTag(TestID.Device.Row.currency).assertIsDisplayed()
        assertEquals(Currency.CHF, preferences.currency.value)

        // The flow then leaves Settings to check Home, reopens it, and switches back.
        // - tapOn: text: ".*EUR.*"
        composeRule.onNodeWithTag(TestID.Device.Row.currency).performClick()
        composeRule.onNodeWithText(Currency.EUR.label).performClick()
        assertEquals(Currency.EUR, preferences.currency.value)
    }

    /**
     * Public key, Bittr peer, Pending payout and Remove wallet — tappable, and each
     * raising the `syncingwallet` alert rather than doing nothing.
     *
     * **Pending payout is the row BIT-7's thread asked specifically not to lose**, and
     * the reason this test names all four instead of trusting the shared handler: the
     * support path BIT-28's playbook sends customers down has to survive a refactor
     * that rewires one row, and the row being silently inert is indistinguishable on a
     * screenshot from the row working.
     *
     * Device details is opened once, above the loop, rather than per row. Dismissing the
     * alert lands back on it — the assertion closing each iteration is what says so — so
     * per-row isolation would only cost a relaunch. It would also not work: a second
     * [launchOnHome] does not start on Home. `rememberNavController()` keeps its back
     * stack in `rememberSaveable`, and the registry belongs to the activity rather than
     * to the composition being replaced, so the new `NavHost` restores the stack the old
     * one left behind and opens on Device details with no `nav.settingsButton` to tap.
     */
    @Test
    fun `the node-backed rows are reachable`() {
        openDeviceDetails()

        listOf(
            TestID.Device.Row.publickey,
            TestID.Device.Row.bittrpeer,
            TestID.Device.Row.pendingpayouts,
            TestID.Device.Row.restore,
        ).forEach { row ->
            composeRule.onNodeWithTag(row).performScrollTo().performClick()
            // - extendedWaitUntil: visible: id: "alert.button.0"
            awaitTag(TestID.Alert.buttonAt(0))
            // One button, not two: with no node this is iOS's `syncingwallet2` branch.
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertDoesNotExist()
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()

            composeRule.onNodeWithTag(row).assertExists()
        }
    }

    /** Lightning connections → the question card → `header.downButton` back. */
    @Test
    fun `the Lightning question card opens and closes`() {
        openDeviceDetails()

        // - tapOn: id: "device.row.lightningchannels"
        composeRule.onNodeWithTag(TestID.Device.Row.lightningchannels)
            .performScrollTo().performClick()
        // - assertVisible: id: "question.yellowCard"
        awaitTag(TestID.Question.yellowCard)

        // - tapOn: id: "header.downButton" — back to Device details.
        composeRule.onNodeWithTag(TestID.Header.downButton).performClick()
        awaitTag(TestID.Device.Row.lightningchannels)
    }

    /**
     * The flow's exit: two `header.downButton` taps from Device details land on Home.
     *
     * Both screens carry that same id, which is how iOS spells it and therefore how
     * the flow taps it — so the only thing that makes the second tap land on Home
     * rather than somewhere else is the back stack, which is what this asserts.
     */
    @Test
    fun `two down taps from Device details return to Home`() {
        openDeviceDetails()

        composeRule.onNodeWithTag(TestID.Header.downButton).performClick()
        // - assertVisible: id: "settings.row.device"
        awaitTag(TestID.Settings.Row.device)

        composeRule.onNodeWithTag(TestID.Header.downButton).performClick()
        // - assertVisible: id: "home.headerLabel"
        awaitTag(TestID.Home.headerLabel)
    }

    // -----------------------------------------------------------------------
    // Steps shared between the tests
    // -----------------------------------------------------------------------

    /** The flow's route in: Home → Settings → Device details. */
    private fun openDeviceDetails() {
        launchOnHome()
        composeRule.onNodeWithTag(TestID.Nav.settingsButton).performClick()
        awaitTag(TestID.Settings.Row.device)
        composeRule.onNodeWithTag(TestID.Settings.Row.device).performClick()
        awaitTag(TestID.Device.Darkmode.moonButton)
    }

    private fun awaitTag(tag: String) = composeRule.waitUntil(TIMEOUT_MS) {
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L

        /** `SettingsStrings.CANCEL`, which is `internal` to `:feature:settings`. */
        const val CANCEL = "Cancel"
    }
}
