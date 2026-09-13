package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.WrongSeedException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * In-memory [SecureStore]. Everything Android-specific about the real one is the
 * encryption; the behaviour the service depends on is this map.
 *
 * @param failWritesFor keys whose writes blow up, for the abort-loudly path.
 */
private class FakeStore(
    private val failWritesFor: Set<String> = emptySet(),
) : SecureStore {
    val values = mutableMapOf<String, ByteArray>()

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

/** `assertThrows` cannot call a suspend function; this can. */
private inline fun <reified T : Throwable> assertFails(block: () -> Unit): T {
    val thrown = runCatching(block).exceptionOrNull()
        ?: throw AssertionError("Expected ${T::class.simpleName}, nothing was thrown")
    if (thrown !is T) throw AssertionError("Expected ${T::class.simpleName}, got $thrown", thrown)
    return thrown
}

class SeedWalletServiceTest {

    @Test
    fun `a fresh install is uninitialized`() {
        val service = SeedWalletService(FakeStore())

        assertEquals(WalletState.Uninitialized, service.state.value)
    }

    @Test
    fun `creating a wallet persists the phrase before returning it`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)

        val mnemonic = service.createWallet()

        assertEquals(12, mnemonic.words.size)
        assertEquals(
            mnemonic.phrase,
            String(store.values.getValue(SeedWalletService.KEY_SEED), Charsets.UTF_8),
        )
    }

    /**
     * The iOS `Signup1` contract: if the seed cannot be stored, the arc stops. A user
     * who is walked through backing up a phrase that was never written to the device
     * has a wallet that vanishes on the next launch.
     */
    @Test
    fun `a storage failure aborts creation instead of returning an unsaved phrase`() = runTest {
        val store = FakeStore(failWritesFor = setOf(SeedWalletService.KEY_SEED))
        val service = SeedWalletService(store)

        assertFails<WalletStorageException> { service.createWallet() }

        assertFalse(store.contains(SeedWalletService.KEY_SEED))
        assertEquals(WalletState.Uninitialized, service.state.value)
    }

    /** A phrase with no PIN is an abandoned arc, not a wallet. */
    @Test
    fun `a seed without a PIN leaves the app in signup`() = runTest {
        val service = SeedWalletService(FakeStore())

        service.createWallet()

        assertEquals(WalletState.Uninitialized, service.state.value)
    }

    @Test
    fun `setting the PIN completes setup and locks the wallet`() = runTest {
        val service = SeedWalletService(FakeStore())

        service.createWallet()
        service.setPin("1234")

        assertEquals(WalletState.Locked, service.state.value)
    }

    @Test
    fun `the correct PIN unlocks`() = runTest {
        val service = SeedWalletService(FakeStore())
        service.createWallet()
        service.setPin("482913")

        assertTrue(service.unlock("482913"))
        assertEquals(WalletState.Ready, service.state.value)
    }

    @Test
    fun `a wrong PIN does not unlock and does not change state`() = runTest {
        val service = SeedWalletService(FakeStore())
        service.createWallet()
        service.setPin("1234")

        assertFalse(service.unlock("1235"))
        assertFalse(service.unlock(""))
        assertFalse(service.unlock("12345"))
        assertEquals(WalletState.Locked, service.state.value)
    }

    /**
     * The Definition of Done, expressed as a test: create, set a PIN, force-quit (a
     * brand-new service over the same storage), and land on the PIN screen rather
     * than back in signup — with the same phrase still on the device.
     */
    @Test
    fun `the wallet survives a force-quit and comes back locked`() = runTest {
        val store = FakeStore()
        val created = SeedWalletService(store).let { service ->
            val mnemonic = service.createWallet()
            service.setPin("9182")
            mnemonic
        }

        val afterRelaunch = SeedWalletService(store)

        assertEquals(WalletState.Locked, afterRelaunch.state.value)
        assertTrue(afterRelaunch.unlock("9182"))
        assertEquals(
            created.phrase,
            String(store.values.getValue(SeedWalletService.KEY_SEED), Charsets.UTF_8),
        )
    }

    @Test
    fun `the PIN itself is never stored`() = runTest {
        val store = FakeStore()
        SeedWalletService(store).apply {
            createWallet()
            setPin("135790")
        }

        val verifier = store.values.getValue(SeedWalletService.KEY_PIN)

        assertFalse(String(verifier, Charsets.ISO_8859_1).contains("135790"))
        assertEquals(16 + 32, verifier.size)
    }

    /** Same PIN, different salt — two installs must not share a verifier. */
    @Test
    fun `verifiers are salted`() = runTest {
        val first = FakeStore()
        SeedWalletService(first).apply { createWallet(); setPin("1111") }
        val second = FakeStore()
        SeedWalletService(second).apply { createWallet(); setPin("1111") }

        assertNotEquals(
            first.values.getValue(SeedWalletService.KEY_PIN).toList(),
            second.values.getValue(SeedWalletService.KEY_PIN).toList(),
        )
    }

    @Test
    fun `PIN length follows the iOS four-to-eight rule`() = runTest {
        val service = SeedWalletService(FakeStore())
        service.createWallet()

        assertFails<IllegalArgumentException> { service.setPin("123") }
        assertFails<IllegalArgumentException> { service.setPin("123456789") }
        assertFails<IllegalArgumentException> { service.setPin("12a4") }

        service.setPin("1234")
        assertEquals(WalletState.Locked, service.state.value)
    }

    @Test
    fun `a PIN cannot be set before a wallet exists`() = runTest {
        val service = SeedWalletService(FakeStore())

        assertFails<WalletStorageException> { service.setPin("1234") }
    }

    /** Restarting the arc must not leave the previous attempt's PIN attached. */
    @Test
    fun `creating a second wallet clears the old PIN`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)
        service.createWallet()
        service.setPin("1234")

        service.createWallet()

        assertFalse(store.contains(SeedWalletService.KEY_PIN))
        assertEquals(WalletState.Uninitialized, service.state.value)
        assertFalse(service.unlock("1234"))
    }

    // ---------------------------------------------------------------------------
    // The lockout counter — BIT-97. `PinLockout` owns what the numbers mean; these
    // cover the half that has to survive the process dying.
    // ---------------------------------------------------------------------------

    @Test
    fun `wrong PINs count up and a correct one clears the count`() = runTest {
        val service = SeedWalletService(FakeStore())
        service.createWallet()
        service.setPin("1234")

        assertEquals(0, service.failedUnlockAttempts())
        service.unlock("1111")
        service.unlock("1111")
        assertEquals(2, service.failedUnlockAttempts())

        assertTrue(service.unlock("1234"))
        assertEquals(0, service.failedUnlockAttempts())
    }

    /**
     * The counter is the whole defence against a 4-digit PIN, so force-quitting must
     * not buy another ten guesses. A count held in the service object would.
     */
    @Test
    fun `the failure count survives a force-quit`() = runTest {
        val store = FakeStore()
        SeedWalletService(store).let { service ->
            service.createWallet()
            service.setPin("1234")
            repeat(9) { service.unlock("0000") }
        }

        assertEquals(9, SeedWalletService(store).failedUnlockAttempts())
    }

    @Test
    fun `a fresh wallet does not inherit the previous one's failures`() = runTest {
        // A device wiped for ten wrong PINs and then set up again must not come back
        // already locked out.
        val store = FakeStore()
        val service = SeedWalletService(store)
        service.createWallet()
        service.setPin("1234")
        repeat(4) { service.unlock("0000") }

        service.createWallet()
        service.setPin("5678")

        assertEquals(0, service.failedUnlockAttempts())
    }

    @Test
    fun `unlocking a device with no wallet does not accumulate a lockout`() = runTest {
        val service = SeedWalletService(FakeStore())

        assertFalse(service.unlock("1234"))

        assertEquals(0, service.failedUnlockAttempts())
    }

    @Test
    fun `an unreadable counter fails open rather than wiping the wallet`() = runTest {
        // iOS reads the Keychain counter through `try?` for this reason: a transient
        // storage error that read as "lots of failures" would erase a wallet that was
        // never attacked.
        val store = FakeStore()
        val service = SeedWalletService(store)
        service.createWallet()
        service.setPin("1234")
        store.values[SeedWalletService.KEY_PIN_ATTEMPTS] = "not a number".toByteArray()

        assertEquals(0, service.failedUnlockAttempts())
    }

    // ---------------------------------------------------------------------------
    // The wipe.
    // ---------------------------------------------------------------------------

    @Test
    fun `removing the wallet erases the seed, the PIN and the counter`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)
        service.createWallet()
        service.setPin("1234")
        repeat(10) { service.unlock("0000") }

        service.removeWallet()

        assertFalse(store.contains(SeedWalletService.KEY_SEED))
        assertFalse(store.contains(SeedWalletService.KEY_PIN))
        assertFalse(store.contains(SeedWalletService.KEY_PIN_ATTEMPTS))
        assertEquals(WalletState.Uninitialized, service.state.value)
    }

    /** And it stays gone across a relaunch — the app comes back at signup. */
    @Test
    fun `a removed wallet does not come back`() = runTest {
        val store = FakeStore()
        SeedWalletService(store).removeWalletAfterSetup()

        assertEquals(WalletState.Uninitialized, SeedWalletService(store).state.value)
    }

    // ---------------------------------------------------------------------------
    // The non-destructive forgot-PIN path.
    // ---------------------------------------------------------------------------

    @Test
    fun `holdsSeed recognises this wallet's phrase and no other`() = runTest {
        val service = SeedWalletService(FakeStore())
        val mnemonic = service.createWallet()
        service.setPin("1234")

        assertTrue(service.holdsSeed(mnemonic))
        assertFalse(service.holdsSeed(SOME_OTHER_PHRASE))
    }

    @Test
    fun `holdsSeed says no on a device with no wallet`() = runTest {
        assertFalse(SeedWalletService(FakeStore()).holdsSeed(SOME_OTHER_PHRASE))
    }

    /**
     * The point of the whole path: the user gets back in and the wallet — and
     * anything in it — is still there.
     */
    @Test
    fun `resetting the PIN keeps the same seed and unlocks`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)
        val mnemonic = service.createWallet()
        service.setPin("1234")
        val seedBefore = store.values.getValue(SeedWalletService.KEY_SEED).copyOf()

        service.resetPin(mnemonic, "5678")

        assertEquals(WalletState.Ready, service.state.value)
        assertArrayEquals(seedBefore, store.values.getValue(SeedWalletService.KEY_SEED))
        assertTrue(SeedWalletService(store).unlock("5678"))
        assertFalse(SeedWalletService(store).unlock("1234"))
    }

    @Test
    fun `resetting the PIN clears the failures that led to it`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)
        val mnemonic = service.createWallet()
        service.setPin("1234")
        repeat(9) { service.unlock("0000") }

        service.resetPin(mnemonic, "5678")

        // Nine failures and a user who has just proved they own the wallet: leaving
        // the count would wipe them on their next typo.
        assertEquals(0, service.failedUnlockAttempts())
    }

    @Test
    fun `the wrong phrase cannot reset the PIN`() = runTest {
        val store = FakeStore()
        val service = SeedWalletService(store)
        service.createWallet()
        service.setPin("1234")

        assertFails<WrongSeedException> { service.resetPin(SOME_OTHER_PHRASE, "5678") }

        assertEquals(WalletState.Locked, service.state.value)
        assertTrue(SeedWalletService(store).unlock("1234"))
    }

    @Test
    fun `a PIN cannot be reset on a device with no wallet`() = runTest {
        val service = SeedWalletService(FakeStore())

        assertFails<WrongSeedException> { service.resetPin(SOME_OTHER_PHRASE, "5678") }
    }

    @Test
    fun `a reset PIN still follows the four-to-eight rule`() = runTest {
        val service = SeedWalletService(FakeStore())
        val mnemonic = service.createWallet()
        service.setPin("1234")

        assertFails<IllegalArgumentException> { service.resetPin(mnemonic, "123") }
        assertFails<IllegalArgumentException> { service.resetPin(mnemonic, "123456789") }
    }

    private suspend fun SeedWalletService.removeWalletAfterSetup() {
        createWallet()
        setPin("1234")
        removeWallet()
    }
}

/**
 * A valid BIP-39 phrase that is not the one under test — the specification's
 * all-zero-entropy vector. Worth nothing to anybody, which is why it is safe to write
 * down here.
 */
private val SOME_OTHER_PHRASE = Mnemonic(
    listOf(
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about",
    ),
)
