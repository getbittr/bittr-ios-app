package com.bittr.android

import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.PinLockout
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.seed.SeedWalletService
import com.bittr.android.navigation.UnlockScreen
import com.bittr.android.navigation.UnlockViewModel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** In-memory [SecureStore] — the Keystore's behaviour minus the encryption. */
private class GateStore : SecureStore {
    private val values = mutableMapOf<String, ByteArray>()
    override fun read(key: String): ByteArray? = values[key]
    override fun write(key: String, value: ByteArray) { values[key] = value }
    override fun contains(key: String): Boolean = key in values
    override fun remove(key: String) { values.remove(key) }
}

/**
 * Walks the four PIN-gate Maestro flows on the JVM, selecting on the ids Maestro uses.
 *
 * `helpers/unlock.yaml`, `features/wrong_pin.yaml`, `features/pin_warning.yaml` and
 * `features/forgot_pin.yaml` — one test each, with the flow's `tapOn` / `assertVisible`
 * steps in the flow's order. This is what closes BIT-97's "all four reachable on
 * Android" without an emulator: the Android Maestro runner is not stood up yet, so the
 * alternative is claiming reachability from reading the source.
 *
 * Sibling of `RestoreArcTestIdsTest`, and it has the same blind spot: Robolectric reads
 * the Compose semantics tree directly, so these pass whether or not
 * `testTagsAsResourceId` bridges the tags onto the accessibility tree Maestro actually
 * queries. `TestTagsAsResourceIdGuardTest` guards that line; only the emulator proves
 * the two together.
 *
 * **The channel-close branches are not here**, because they are not built:
 * `wrong_pin_with_channel.yaml` and `remove_wallet.yaml` need a node to close channels
 * against and belong to BIT-6's wave. The no-channel branches below are the whole of
 * BIT-97.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class PinGateFlowTest {

    @get:Rule
    val composeRule = createComposeRule()

    /**
     * The fixed phrase `restore_wallet.yaml` and `pin_warning.yaml` bake in, so the
     * wallet under test is the one those flows produce.
     */
    private val flowWords = listOf(
        "attack", "urge", "across", "cupboard", "year", "armor",
        "list", "vital", "outer", "leader", "anxiety", "endorse",
    )

    private val store = GateStore()
    private val wallet = SeedWalletService(store)

    /** The wallet the flows start from: restored, PIN 1234, no failed attempts. */
    private fun aWalletWithPin1234() = runBlocking {
        wallet.restoreWallet(Mnemonic(flowWords))
        wallet.setPin(CORRECT_PIN)
    }

    private fun gate(
        onUnlocked: () -> Unit = {},
        onWalletWiped: () -> Unit = {},
    ): UnlockViewModel {
        val viewModel = UnlockViewModel(wallet)
        composeRule.setContent {
            BittrTheme {
                UnlockScreen(
                    onUnlocked = onUnlocked,
                    onWalletWiped = onWalletWiped,
                    viewModel = viewModel,
                )
            }
        }
        return viewModel
    }

    // -----------------------------------------------------------------------
    // helpers/unlock.yaml
    // -----------------------------------------------------------------------

    @Test
    fun `the unlock helper opens the wallet`() {
        aWalletWithPin1234()
        var unlocked = false
        gate(onUnlocked = { unlocked = true })

        // - assertVisible: id: "unlock.topLabel"
        composeRule.onNodeWithTag(TestID.Unlock.topLabel).assertIsDisplayed()
        // - tapOn: pin.button1 .. pin.button4, then pin.confirmButton
        enterPin(CORRECT_PIN)

        composeRule.waitUntil(TIMEOUT_MS) { unlocked }
        assertEquals(WalletState.Ready, wallet.state.value)
    }

    // -----------------------------------------------------------------------
    // features/pin_warning.yaml
    // -----------------------------------------------------------------------

    /**
     * The distinguishing assertion of the whole flow is `alert.button.1`: the plain
     * incorrect-PIN alert has one button, the warning has two, so a second button
     * existing *is* how the flow knows which alert it got. Getting the two indices the
     * wrong way round would make `wrong_pin_until_lockout.yaml` — which taps
     * `alert.button.0` on every attempt including the third — walk into the reset arc
     * instead of retrying, so the order is asserted rather than assumed.
     */
    @Test
    fun `three wrong PINs raise the warning, and its second button resets the PIN`() {
        aWalletWithPin1234()
        var unlocked = false
        gate(onUnlocked = { unlocked = true })

        // Wrong attempts 1..2: the one-button incorrect-PIN alert.
        repeat(2) {
            enterPin(WRONG_PIN)
            awaitTag(TestID.Alert.buttonAt(0))
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).assertDoesNotExist()
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        }

        // Wrong attempt 3: the warning. Two buttons, and the second says Forgot PIN.
        enterPin(WRONG_PIN)
        awaitTag(TestID.Alert.buttonAt(1))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertIsDisplayed()
        // - assertVisible: "Forgot PIN" — on the alert button and on the pad's own
        // button underneath it, hence onAllNodesWithText.
        assertTrue(
            "The warning's second button must read \"Forgot PIN\"",
            composeRule.onAllNodesWithText(FORGOT_PIN).fetchSemanticsNodes().isNotEmpty(),
        )

        // - tapOn: alert.button.1 — straight into the phrase fields, with no second
        // confirmation. That asymmetry with forgot_pin.yaml is the flow's point.
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).performClick()
        awaitTag(TestID.Signup.Restore.topLabel)

        resetPinWithThePhrase()

        composeRule.waitUntil(TIMEOUT_MS) { unlocked }
        // Non-destructive: same wallet, new PIN, and the failures are cleared.
        assertEquals(WalletState.Ready, wallet.state.value)
        assertTrue(runBlocking { wallet.holdsSeed(Mnemonic(flowWords)) })
        assertEquals(0, runBlocking { wallet.failedUnlockAttempts() })
    }

    // -----------------------------------------------------------------------
    // features/forgot_pin.yaml
    // -----------------------------------------------------------------------

    @Test
    fun `forgot PIN confirms first, then resets against the phrase`() {
        aWalletWithPin1234()
        var unlocked = false
        gate(onUnlocked = { unlocked = true })

        composeRule.onNodeWithTag(TestID.Unlock.topLabel).assertIsDisplayed()
        // - tapOn: id: "pin.restoreButton"
        composeRule.onNodeWithTag(TestID.Pin.restoreButton).performClick()

        // - assertVisible / tapOn: id: "alert.button.1" — [Cancel, Reset].
        awaitTag(TestID.Alert.buttonAt(1))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).performClick()

        awaitTag(TestID.Signup.Restore.topLabel)
        resetPinWithThePhrase()

        composeRule.waitUntil(TIMEOUT_MS) { unlocked }
        assertEquals(WalletState.Ready, wallet.state.value)
        assertTrue(
            "The reset must keep the same wallet",
            runBlocking { wallet.holdsSeed(Mnemonic(flowWords)) },
        )
    }

    /** Cancel on that alert is Cancel: nothing is reset and nothing is erased. */
    @Test
    fun `cancelling the forgot-PIN confirmation leaves the wallet alone`() {
        aWalletWithPin1234()
        gate()

        composeRule.onNodeWithTag(TestID.Pin.restoreButton).performClick()
        awaitTag(TestID.Alert.buttonAt(0))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()

        composeRule.onNodeWithTag(TestID.Unlock.topLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Signup.Restore.topLabel).assertDoesNotExist()
        assertEquals(WalletState.Locked, wallet.state.value)
    }

    /** `forgotpin3`: a valid phrase that is not this wallet's does not get you in. */
    @Test
    fun `someone else's recovery phrase cannot reset the PIN`() {
        aWalletWithPin1234()
        gate()

        composeRule.onNodeWithTag(TestID.Pin.restoreButton).performClick()
        awaitTag(TestID.Alert.buttonAt(1))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(1)).performClick()
        awaitTag(TestID.Signup.Restore.topLabel)

        typePhrase(OTHER_PHRASE)
        composeRule.onNodeWithTag(TestID.Signup.Restore.nextButton)
            .performScrollTo().performClick()

        awaitTag(TestID.Alert.buttonAt(0))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        // Still on the fields, and the old PIN still works.
        composeRule.onNodeWithTag(TestID.Signup.Restore.topLabel).assertExists()
        composeRule.onNodeWithTag(TestID.Signup.Restore.PinSet.topLabel).assertDoesNotExist()
        assertTrue(runBlocking { SeedWalletService(store).unlock(CORRECT_PIN) })
    }

    // -----------------------------------------------------------------------
    // features/wrong_pin.yaml — via helpers/wrong_pin_until_lockout.yaml
    // -----------------------------------------------------------------------

    /**
     * Ten wrong entries and the wallet is off the device.
     *
     * The helper flow taps `alert.button.0` after every one of the first nine — which
     * includes the third, where that button is the warning's Okay rather than the
     * incorrect-PIN alert's. Driving it the same way here is what proves the two
     * alerts are interchangeable from the helper's point of view.
     */
    @Test
    fun `ten wrong PINs erase the wallet and hand off to signup`() {
        aWalletWithPin1234()
        var wiped = false
        gate(onWalletWiped = { wiped = true })

        composeRule.onNodeWithTag(TestID.Unlock.topLabel).assertIsDisplayed()

        repeat(PinLockout.WIPE_AT - 1) { attempt ->
            enterPin(WRONG_PIN)
            awaitTag(TestID.Alert.buttonAt(0))
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
            assertEquals(
                "after wrong attempt ${attempt + 1}",
                attempt + 1,
                runBlocking { wallet.failedUnlockAttempts() },
            )
        }

        // The tenth. The flow stops here and waits for an alert.
        enterPin(WRONG_PIN)
        awaitTag(TestID.Alert.buttonAt(0))

        // wrong_pin.yaml: tap Okay, then Signup1 is reachable. The wipe has already
        // happened by the time the alert claims it has — see UnlockViewModel.
        assertEquals(WalletState.Uninitialized, wallet.state.value)
        assertFalse(store.contains(SeedWalletService.KEY_SEED))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()

        composeRule.waitUntil(TIMEOUT_MS) { wiped }
        assertTrue("The gate must hand off to signup once the wallet is gone", wiped)
    }

    /**
     * `clearPinField()` — the rejected digits go away.
     *
     * This is not cosmetic and it is not implied by the alert appearing. The pad caps
     * at eight digits, so a pad that kept the four refused ones would accept four more
     * and then silently ignore every tap after that: `wrong_pin_until_lockout.yaml`
     * would enter `11111111` on attempt two and the *same* `11111111` on every attempt
     * after it, and a correct PIN typed at attempt ten would never reach the service.
     * The flow still reaches the wipe, so only asserting the wipe hides this.
     */
    @Test
    fun `a rejected PIN empties the pad`() {
        aWalletWithPin1234()
        gate()

        enterPin(WRONG_PIN)
        awaitTag(TestID.Alert.buttonAt(0))
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()

        composeRule.onNodeWithTag(TestID.Pin.pinTextField)
            .assertContentDescriptionEquals("0 digits entered")
    }

    /**
     * The guard above the wrong-PIN branch, not above the method: nine failures and
     * then the right PIN is a user who remembered, not a lockout.
     */
    @Test
    fun `a correct tenth entry still unlocks`() {
        aWalletWithPin1234()
        var unlocked = false
        var wiped = false
        gate(onUnlocked = { unlocked = true }, onWalletWiped = { wiped = true })

        repeat(PinLockout.WIPE_AT - 1) {
            enterPin(WRONG_PIN)
            awaitTag(TestID.Alert.buttonAt(0))
            composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        }
        enterPin(CORRECT_PIN)

        composeRule.waitUntil(TIMEOUT_MS) { unlocked }
        assertFalse("A correct PIN must not erase the wallet", wiped)
        assertEquals(WalletState.Ready, wallet.state.value)
        assertEquals(0, runBlocking { wallet.failedUnlockAttempts() })
    }

    /**
     * `CoreViewController.checkWalletRemoval` — a wipe already earned completes on the
     * next launch without a PIN being typed.
     *
     * This is the branch that makes force-quitting on the tenth wrong entry useless.
     * Killing the app between the increment and the erase would otherwise be a way to
     * keep a wallet that is already forfeit.
     */
    @Test
    fun `a lockout survives the app being killed and finishes on the next launch`() {
        aWalletWithPin1234()
        runBlocking { repeat(PinLockout.WIPE_AT) { wallet.unlock(WRONG_PIN) } }
        // A fresh service over the same storage is the relaunch.
        val afterRelaunch = SeedWalletService(store)
        assertEquals(WalletState.Locked, afterRelaunch.state.value)

        var wiped = false
        val viewModel = UnlockViewModel(afterRelaunch)
        composeRule.setContent {
            BittrTheme {
                UnlockScreen(onUnlocked = {}, onWalletWiped = { wiped = true }, viewModel = viewModel)
            }
        }

        awaitTag(TestID.Alert.buttonAt(0))
        assertEquals(WalletState.Uninitialized, afterRelaunch.state.value)
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        composeRule.waitUntil(TIMEOUT_MS) { wiped }
    }

    // -----------------------------------------------------------------------
    // Steps shared between the flows
    // -----------------------------------------------------------------------

    /**
     * The digit taps plus `pin.confirmButton`, as every flow spells them out.
     *
     * No `performScrollTo` here, unlike the phrase fields: the pad is a fixed layout
     * that fits the screen, and asking a non-scrollable parent to scroll is an error
     * rather than a no-op.
     */
    private fun enterPin(pin: String) {
        pin.forEach { digit -> composeRule.onNodeWithTag(digitTag(digit)).performClick() }
        composeRule.onNodeWithTag(TestID.Pin.confirmButton).performClick()
    }

    /**
     * The tail both reset flows share: type the phrase, then 1234 twice.
     *
     * Both end on PIN 1234 so the wallet is left exactly as `helpers/unlock.yaml`
     * expects it — which is what makes `pin_warning.yaml` repeatable.
     */
    private fun resetPinWithThePhrase() {
        typePhrase(flowWords)
        composeRule.onNodeWithTag(TestID.Signup.Restore.nextButton)
            .performScrollTo().performClick()

        awaitTag(TestID.Signup.Restore.PinSet.topLabel)
        enterPin(CORRECT_PIN)

        awaitTag(TestID.Signup.Restore.PinConfirm.topLabel)
        enterPin(CORRECT_PIN)
    }

    private fun typePhrase(words: List<String>) {
        fieldTags.forEachIndexed { index, tag ->
            composeRule.onNodeWithTag(tag).performScrollTo().performTextInput(words[index])
        }
    }

    private fun awaitTag(tag: String) = composeRule.waitUntil(TIMEOUT_MS) {
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private fun digitTag(digit: Char): String = when (digit) {
        '0' -> TestID.Pin.button0
        '1' -> TestID.Pin.button1
        '2' -> TestID.Pin.button2
        '3' -> TestID.Pin.button3
        '4' -> TestID.Pin.button4
        '5' -> TestID.Pin.button5
        '6' -> TestID.Pin.button6
        '7' -> TestID.Pin.button7
        '8' -> TestID.Pin.button8
        '9' -> TestID.Pin.button9
        else -> error("Not a digit: $digit")
    }

    private val fieldTags = listOf(
        TestID.Signup.Restore.field1,
        TestID.Signup.Restore.field2,
        TestID.Signup.Restore.field3,
        TestID.Signup.Restore.field4,
        TestID.Signup.Restore.field5,
        TestID.Signup.Restore.field6,
        TestID.Signup.Restore.field7,
        TestID.Signup.Restore.field8,
        TestID.Signup.Restore.field9,
        TestID.Signup.Restore.field10,
        TestID.Signup.Restore.field11,
        TestID.Signup.Restore.field12,
    )

    private companion object {
        /** `helpers/unlock.yaml` and every onboarding flow set this one. */
        const val CORRECT_PIN = "1234"

        /** `helpers/wrong_pin_until_lockout.yaml` taps 1 four times. */
        const val WRONG_PIN = "1111"

        const val FORGOT_PIN = "Forgot PIN"
        const val TIMEOUT_MS = 10_000L

        /** The BIP-39 all-zero-entropy vector: valid, and not this wallet's. */
        val OTHER_PHRASE = listOf(
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        )
    }
}
