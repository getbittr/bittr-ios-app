package com.bittr.android.feature.signup

import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.seed.SeedWalletService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private class RestoreFakeStore(private val failWritesFor: Set<String> = emptySet()) : SecureStore {
    private val values = mutableMapOf<String, ByteArray>()
    override fun read(key: String): ByteArray? = values[key]
    override fun write(key: String, value: ByteArray) {
        if (key in failWritesFor) throw WalletStorageException("Injected failure for $key")
        values[key] = value
    }
    override fun contains(key: String): Boolean = key in values
    override fun remove(key: String) {
        values.remove(key)
    }
}

/**
 * The restore arc as the screen drives it.
 *
 * `SeedPhraseEntryTest` proves the rejection rules; this proves the screen is wired to
 * them — that a rejected phrase keeps the user on the fields **and never reaches
 * secure storage**. Those are two different failures, and testing the rules alone
 * catches only one of them: a screen that showed the alert and stored the seed anyway
 * would pass every test in `SeedPhraseEntryTest`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RestoreWalletViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)

    @After fun tearDown() = Dispatchers.resetMain()

    /** The phrase `shared/flows/onboarding/restore_wallet.yaml` types in. */
    private val flowPhrase = listOf(
        "attack", "urge", "across", "cupboard", "year", "armor",
        "list", "vital", "outer", "leader", "anxiety", "endorse",
    )

    private fun viewModel(store: SecureStore = RestoreFakeStore()) =
        RestoreWalletViewModel(SeedWalletService(store)) to store

    // --- Rejection path 1: a word that is not BIP-39 -------------------------

    @Test
    fun `a misspelled word is rejected and nothing is stored`() = runTest(dispatcher) {
        val (vm, store) = viewModel()

        vm.submitPhrase(listOf("attck") + flowPhrase.drop(1))
        advanceUntilIdle()

        assertEquals(RestoreWalletStep.Phrase, vm.uiState.value.step)
        assertEquals(SignupStrings.INVALID_PHRASE, vm.uiState.value.alert?.title)
        assertFalse(
            "A rejected phrase must never reach the Keystore",
            store.contains(SeedWalletService.KEY_SEED),
        )
    }

    // --- Rejection path 2: twelve real words, wrong phrase -------------------

    @Test
    fun `real words that do not checksum are rejected and nothing is stored`() =
        runTest(dispatcher) {
            val (vm, store) = viewModel()

            vm.submitPhrase(List(12) { "abandon" })
            advanceUntilIdle()

            assertEquals(RestoreWalletStep.Phrase, vm.uiState.value.step)
            assertEquals(SignupStrings.INVALID_PHRASE, vm.uiState.value.alert?.title)
            assertFalse(store.contains(SeedWalletService.KEY_SEED))
        }

    @Test
    fun `the right words in the wrong order are rejected`() = runTest(dispatcher) {
        val (vm, store) = viewModel()

        vm.submitPhrase(flowPhrase.toMutableList().apply { add(0, removeAt(1)) })
        advanceUntilIdle()

        assertEquals(RestoreWalletStep.Phrase, vm.uiState.value.step)
        assertEquals(SignupStrings.INVALID_PHRASE, vm.uiState.value.alert?.title)
        assertFalse(store.contains(SeedWalletService.KEY_SEED))
    }

    /**
     * Both invalid cases read the same to the user, matching iOS's single
     * `invalidphrase` alert. If a later change splits them, this is the test that
     * says so out loud rather than letting the copy drift silently.
     */
    @Test
    fun `a bad word and a bad checksum show the same alert`() = runTest(dispatcher) {
        val (badWord, _) = viewModel()
        badWord.submitPhrase(listOf("attck") + flowPhrase.drop(1))
        advanceUntilIdle()

        val (badChecksum, _) = viewModel()
        badChecksum.submitPhrase(List(12) { "abandon" })
        advanceUntilIdle()

        assertEquals(badWord.uiState.value.alert, badChecksum.uiState.value.alert)
    }

    @Test
    fun `an empty field is incomplete, not invalid`() = runTest(dispatcher) {
        val (vm, _) = viewModel()

        vm.submitPhrase(flowPhrase.toMutableList().apply { this[5] = "" })
        advanceUntilIdle()

        assertEquals(SignupStrings.INCOMPLETE_PHRASE, vm.uiState.value.alert?.title)
        assertEquals(RestoreWalletStep.Phrase, vm.uiState.value.step)
    }

    // --- The happy path the Maestro flow drives ------------------------------

    @Test
    fun `a valid phrase stores the seed and advances to the PIN`() = runTest(dispatcher) {
        val (vm, store) = viewModel()

        vm.submitPhrase(flowPhrase)
        advanceUntilIdle()

        assertNull(vm.uiState.value.alert)
        assertEquals(RestoreWalletStep.PinSet, vm.uiState.value.step)
        assertEquals(
            flowPhrase.joinToString(" "),
            store.read(SeedWalletService.KEY_SEED)?.toString(Charsets.UTF_8),
        )
    }

    @Test
    fun `the arc ends on Home only after the PIN is set`() = runTest(dispatcher) {
        val store = RestoreFakeStore()
        val wallet = SeedWalletService(store)
        val vm = RestoreWalletViewModel(wallet)
        var finished = false

        vm.submitPhrase(flowPhrase)
        advanceUntilIdle()

        // A seed with no PIN is not a wallet — the user who quits here restarts
        // signup rather than facing a PIN screen for a restore they abandoned.
        assertEquals(WalletState.Uninitialized, wallet.state.value)

        vm.submitFirstPin("1234")
        assertEquals(RestoreWalletStep.PinConfirm, vm.uiState.value.step)

        vm.submitConfirmationPin("1234") { finished = true }
        advanceUntilIdle()

        assertTrue("Restore3 must hand off to Home", finished)
        assertEquals(WalletState.Locked, wallet.state.value)
    }

    @Test
    fun `a mismatched confirmation stays on the pad and does not finish`() =
        runTest(dispatcher) {
            val (vm, _) = viewModel()
            var finished = false

            vm.submitPhrase(flowPhrase)
            advanceUntilIdle()
            vm.submitFirstPin("1234")

            vm.submitConfirmationPin("1235") { finished = true }
            advanceUntilIdle()

            assertFalse(finished)
            assertEquals(RestoreWalletStep.PinConfirm, vm.uiState.value.step)
            assertEquals(SignupStrings.INCORRECT_PIN, vm.uiState.value.alert?.title)
        }

    @Test
    fun `a short PIN is refused with the 4-to-8 message`() = runTest(dispatcher) {
        val (vm, _) = viewModel()

        vm.submitPhrase(flowPhrase)
        advanceUntilIdle()
        vm.submitFirstPin("12")

        assertEquals(RestoreWalletStep.PinSet, vm.uiState.value.step)
        assertEquals(SignupStrings.PIN_SHOULD_BE_4_TO_8, vm.uiState.value.alert?.message)
    }

    // --- Storage failure: iOS's abort-loudly path ----------------------------

    @Test
    fun `a seed that cannot be stored keeps the user on the fields`() = runTest(dispatcher) {
        val (vm, _) = viewModel(RestoreFakeStore(failWritesFor = setOf(SeedWalletService.KEY_SEED)))

        vm.submitPhrase(flowPhrase)
        advanceUntilIdle()

        assertEquals(RestoreWalletStep.Phrase, vm.uiState.value.step)
        assertEquals(SignupStrings.ERROR, vm.uiState.value.alert?.title)
        assertFalse("busy must clear so the user can retry", vm.uiState.value.busy)
    }

    @Test
    fun `dismissing an alert clears it`() = runTest(dispatcher) {
        val (vm, _) = viewModel()

        vm.submitPhrase(List(12) { "abandon" })
        advanceUntilIdle()
        assertNotNull(vm.uiState.value.alert)

        vm.dismissAlert()
        assertNull(vm.uiState.value.alert)
    }
}
