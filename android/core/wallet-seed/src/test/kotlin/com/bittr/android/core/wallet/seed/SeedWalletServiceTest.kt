package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import kotlinx.coroutines.test.runTest
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
}
