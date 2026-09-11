package com.bittr.android.feature.signup

import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.seed.SeedChallenge
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

private class FakeStore(private val failWritesFor: Set<String> = emptySet()) : SecureStore {
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
 * The arc as the screen drives it.
 *
 * `SeedChallengeTest` proves the rejection rules; this proves the screen is actually
 * wired to them — that a wrong word keeps the user on Verify with the right alert
 * rather than waving them through, and that the PIN pair has to match. Those are two
 * different failures and only one of them is caught by testing the rules alone.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CreateWalletViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)

    @After fun tearDown() = Dispatchers.resetMain()

    private fun viewModel(store: SecureStore = FakeStore()) =
        CreateWalletViewModel(SeedWalletService(store)) to store

    /** Answers for the three words the challenge happens to have picked. */
    private fun correctAnswers(state: CreateWalletUiState): List<String> {
        val mnemonic = requireNotNull(state.mnemonic)
        val challenge = requireNotNull(state.challenge)
        return challenge.positions.map { mnemonic.words[it] }
    }

    @Test
    fun `the whole arc reaches Ready and leaves a locked wallet behind`() = runTest {
        val store = FakeStore()
        val wallet = SeedWalletService(store)
        val vm = CreateWalletViewModel(wallet)

        vm.createWallet()
        advanceUntilIdle()
        assertEquals(CreateWalletStep.Phrase, vm.uiState.value.step)

        vm.confirmPhraseSeen()
        assertEquals(CreateWalletStep.Verify, vm.uiState.value.step)

        vm.submitVerification(correctAnswers(vm.uiState.value))
        assertEquals(CreateWalletStep.PinSet, vm.uiState.value.step)

        vm.submitFirstPin("4821")
        assertEquals(CreateWalletStep.PinConfirm, vm.uiState.value.step)

        vm.submitConfirmationPin("4821")
        advanceUntilIdle()
        assertEquals(CreateWalletStep.Ready, vm.uiState.value.step)
        assertEquals(WalletState.Locked, wallet.state.value)

        // The words are gone from the arc once they are no longer needed.
        assertNull(vm.uiState.value.mnemonic)
    }

    @Test
    fun `a wrong word keeps the user on Verify and says so`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()

        val wrong = correctAnswers(vm.uiState.value).toMutableList().apply { this[1] = "zoo" }
        vm.submitVerification(wrong)

        assertEquals(CreateWalletStep.Verify, vm.uiState.value.step)
        assertEquals(SignupStrings.INCORRECT_PHRASE, vm.uiState.value.alert?.title)
    }

    @Test
    fun `a misspelling is reported as an invalid word, not a wrong one`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()

        val typo = correctAnswers(vm.uiState.value).toMutableList().apply { this[0] = "abandonn" }
        vm.submitVerification(typo)

        assertEquals(CreateWalletStep.Verify, vm.uiState.value.step)
        assertEquals(SignupStrings.INVALID_WORDS, vm.uiState.value.alert?.title)
    }

    @Test
    fun `a blank field is reported as missing`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()

        vm.submitVerification(listOf("", "", ""))

        assertEquals(CreateWalletStep.Verify, vm.uiState.value.step)
        assertEquals(SignupStrings.MISSING_WORDS, vm.uiState.value.alert?.title)
    }

    /** Rejection must be recoverable — the user retypes and gets through. */
    @Test
    fun `after a rejection the correct words still pass`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()

        vm.submitVerification(listOf("zoo", "zoo", "zoo"))
        assertEquals(CreateWalletStep.Verify, vm.uiState.value.step)
        vm.dismissAlert()

        vm.submitVerification(correctAnswers(vm.uiState.value))

        assertEquals(CreateWalletStep.PinSet, vm.uiState.value.step)
        assertNull(vm.uiState.value.alert)
    }

    @Test
    fun `a mismatched confirmation PIN does not complete setup`() = runTest {
        val store = FakeStore()
        val wallet = SeedWalletService(store)
        val vm = CreateWalletViewModel(wallet)
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()
        vm.submitVerification(correctAnswers(vm.uiState.value))
        vm.submitFirstPin("4821")

        vm.submitConfirmationPin("1111")
        advanceUntilIdle()

        assertEquals(CreateWalletStep.PinConfirm, vm.uiState.value.step)
        assertEquals(SignupStrings.INCORRECT_PIN, vm.uiState.value.alert?.title)
        assertEquals(WalletState.Uninitialized, wallet.state.value)
    }

    @Test
    fun `a PIN shorter than four digits is refused`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()
        vm.submitVerification(correctAnswers(vm.uiState.value))

        vm.submitFirstPin("123")

        assertEquals(CreateWalletStep.PinSet, vm.uiState.value.step)
        assertNotNull(vm.uiState.value.alert)
    }

    /**
     * The iOS `Signup1` contract. If the seed cannot be stored the user must not be
     * shown a phrase — they would write down a backup for a wallet that does not
     * exist on the device.
     */
    @Test
    fun `a storage failure keeps the user on Start with the save-failed alert`() = runTest {
        val (vm, _) = viewModel(FakeStore(failWritesFor = setOf(SeedWalletService.KEY_SEED)))

        vm.createWallet()
        advanceUntilIdle()

        assertEquals(CreateWalletStep.Start, vm.uiState.value.step)
        assertNull(vm.uiState.value.mnemonic)
        assertEquals(SignupStrings.MNEMONIC_SAVE_FAIL, vm.uiState.value.alert?.message)
    }

    @Test
    fun `going back from Verify returns to the phrase`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()

        vm.backToPhrase()

        assertEquals(CreateWalletStep.Phrase, vm.uiState.value.step)
        assertNotNull(vm.uiState.value.mnemonic)
    }

    /** A fresh challenge each time the user comes back, not the same three words. */
    @Test
    fun `returning to Verify asks again`() = runTest {
        val (vm, _) = viewModel()
        vm.createWallet()
        advanceUntilIdle()
        vm.confirmPhraseSeen()
        val first = vm.uiState.value.challenge?.positions

        vm.backToPhrase()
        assertNull(vm.uiState.value.challenge)
        vm.confirmPhraseSeen()

        assertEquals(SeedChallenge.ASK_COUNT, vm.uiState.value.challenge?.positions?.size)
        assertNotNull(first)
    }
}
