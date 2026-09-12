package com.bittr.android.feature.scanner

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The three states the Definition of Done names, and the test IDs the iOS suite
 * drives them with.
 *
 * Two things are being held still here.
 *
 * **The IDs.** `scanner.scannerView`, `scanner.closeButton` and the indexed
 * `alert.button.N` are what `shared/flows/` selects on, and they are shared with
 * iOS — no new ID was invented for this screen. Losing one is a one-character change
 * that Maestro only catches after an emulator boot, and reports as "element not
 * found", which looks exactly like a broken emulator.
 *
 * **The words.** The camera strings are founder-approved copy (BIT-15 ->
 * `decision-brief` D1 - DEV-37) and two of their sentences are factual claims about
 * this build that compliance signed off as binding (BIT-36, BIT-57). Asserting the
 * rendered text, rather than the constants, is what makes a quiet reword during a
 * layout change fail here instead of shipping.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class ScannerScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private var state: ScannerUiState by mutableStateOf(ScannerUiState.Scanning)
    private var settingsAvailable: Boolean by mutableStateOf(true)

    private var closes = 0
    private var cancels = 0
    private var continues = 0
    private var settingsOpens = 0

    /** Composes the screen once; [state] drives it from there. */
    private fun start(initial: ScannerUiState) {
        state = initial
        composeRule.setContent {
            BittrTheme {
                ScannerScreenContent(
                    state = state,
                    onClose = { closes++ },
                    onCancel = { cancels++ },
                    onContinue = { continues++ },
                    onOpenSettings = if (settingsAvailable) ({ settingsOpens++ }) else null,
                )
            }
        }
    }

    @Test
    fun `scanning shows the frame and the close button and no alert`() {
        start(ScannerUiState.Scanning)

        composeRule.onNodeWithTag(TestID.Scanner.scannerView).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Scanner.closeButton).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertDoesNotExist()
    }

    /**
     * The frame stays put under the alert.
     *
     * `send_onchain.yaml:78-81` asserts `scanner.scannerView` and then
     * `alert.button.0`, in that order, on the same screen — iOS leaves the scanner
     * view mounted and presents the alert over it. Swapping the frame out for the
     * alert is the obvious Compose shape, passes any test that only looks at the
     * alert, and fails that flow after a full emulator boot.
     */
    @Test
    fun `the scanner frame stays visible under every alert`() {
        start(ScannerUiState.Rationale)

        for (alertState in listOf(
            ScannerUiState.Rationale,
            ScannerUiState.PermanentlyDenied,
            ScannerUiState.NoCamera,
        )) {
            composeRule.runOnIdle { state = alertState }
            composeRule.onNodeWithTag(TestID.Scanner.scannerView).assertIsDisplayed()
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertIsDisplayed()
        }
    }

    @Test
    fun `the rationale shows the approved copy above cancel and continue`() {
        start(ScannerUiState.Rationale)

        composeRule.onNodeWithText(ScannerCopy.PERMISSION_TITLE).assertIsDisplayed()
        composeRule.onNodeWithText(ScannerCopy.RATIONALE_BODY).assertIsDisplayed()

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertTextEquals(ScannerCopy.CANCEL)
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertTextEquals(ScannerCopy.CONTINUE)
    }

    /** The sentence the whole camera path is built around, checked as shipped text. */
    @Test
    fun `the rationale tells the user nothing is recorded`() {
        start(ScannerUiState.Rationale)

        composeRule
            .onNodeWithText(
                "The camera is used only to read the code in front of it. Nothing is recorded.",
                substring = true,
            )
            .assertIsDisplayed()
    }

    @Test
    fun `continue asks for the permission and cancel closes the scanner`() {
        start(ScannerUiState.Rationale)

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).performClick()
        assertEquals(1, continues)

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        assertEquals(1, cancels)
    }

    @Test
    fun `permanently denied shows the approved copy above cancel and settings`() {
        start(ScannerUiState.PermanentlyDenied)

        composeRule.onNodeWithText(ScannerCopy.PERMISSION_TITLE).assertIsDisplayed()
        composeRule.onNodeWithText(ScannerCopy.PERMANENTLY_DENIED_BODY).assertIsDisplayed()

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertTextEquals(ScannerCopy.CANCEL)
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertTextEquals(ScannerCopy.SETTINGS)

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).performClick()
        assertEquals(1, settingsOpens)
    }

    /**
     * The permanently-denied copy names the paste route, so the sentence is only
     * true while a paste control exists on the screen the scanner returns to. That
     * control is `TestID.Send.pasteButton`, which the port keeps — compliance
     * verified the route rather than taking it on trust, which is why the sentence
     * shipped without a caveat.
     */
    @Test
    fun `permanently denied offers paste as the alternative`() {
        start(ScannerUiState.PermanentlyDenied)

        composeRule
            .onNodeWithText(
                "You can also paste an address or an invoice instead of scanning it.",
                substring = true,
            )
            .assertIsDisplayed()

        assertEquals("send.pasteButton", TestID.Send.pasteButton)
    }

    /**
     * No settings app, no Settings button.
     *
     * [com.bittr.android.core.permissions.AppSettings] is explicit that an
     * unresolvable intent means leaving the button out: it is the button whose whole
     * job is to be the way out of a dead end, and one that throws
     * `ActivityNotFoundException` is a crash from exactly there. Cancel stays at
     * position 0, so the flow's `alert.button.0` still means the way out.
     */
    @Test
    fun `the settings button is left out when nothing can open settings`() {
        settingsAvailable = false
        start(ScannerUiState.PermanentlyDenied)

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertTextEquals(ScannerCopy.CANCEL)
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertDoesNotExist()
    }

    /**
     * The no-camera state reuses the iOS strings unchanged, and its single Okay
     * button closes the scanner — as `ScannerViewController.swift:53` does. This is
     * the alert `send_onchain.yaml` actually meets today, because the simulator has
     * no camera.
     */
    @Test
    fun `no camera reuses the shipped iOS strings and closes on okay`() {
        start(ScannerUiState.NoCamera)

        composeRule.onNodeWithText(ScannerCopy.NO_CAMERA_TITLE).assertIsDisplayed()
        composeRule.onNodeWithText(ScannerCopy.NO_CAMERA_BODY).assertIsDisplayed()

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertTextEquals(ScannerCopy.OKAY)
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertDoesNotExist()

        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        assertEquals(1, closes)
    }
}
