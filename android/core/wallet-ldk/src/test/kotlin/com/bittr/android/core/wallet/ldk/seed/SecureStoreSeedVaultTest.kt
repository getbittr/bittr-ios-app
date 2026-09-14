package com.bittr.android.core.wallet.ldk.seed

import android.security.keystore.KeyPermanentlyInvalidatedException
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletStorageException
import java.security.KeyStoreException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The bridge that lets a node read the seed the app actually stored.
 *
 * `LdkNodeFactory` reads through [SeedVault]; the mnemonic of every wallet
 * created on a device so far is in a [SecureStore] under BIT-93's key. Without
 * this, a node start on a device with a perfectly good wallet fails with
 * `MnemonicUnavailableException` — a failure that reads as "this device has no
 * wallet" and would send a funded user to the restore screen.
 *
 * The tests that matter are not the round trip. They are the two places where
 * the three-valued contract could be collapsed into two, because both
 * collapses have a fund-loss shape (BIT-20 rule 3): an unreadable Keystore that
 * reads as *absent* sends a user with live channels to restore, and — one layer
 * up, where [MnemonicPresence] is consumed — quarantines their channel state.
 *
 * ## Why Robolectric for a class with no Android in it
 *
 * [SeedVaultFailures] classifies on [KeyPermanentlyInvalidatedException], which
 * is `android.security.keystore`. Constructing one to classify needs a real
 * class rather than the unit-test stub android.jar's, which throws on every
 * call.
 *
 * Pinned at 26 / 34 / 36 — `minSdk`, the level the CI emulator boots, and the
 * newest Robolectric 4.16.1 can instantiate. The claim is not API-dependent;
 * the pin is `RobolectricSdkPinGuardTest`'s rule, and it applies because a class
 * that silently stops running is worse than one that fails.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 34, 36])
class SecureStoreSeedVaultTest {

    private companion object {
        const val KEY = "wallet.seed"
        const val PHRASE = "abandon abandon abandon abandon abandon abandon " +
            "abandon abandon abandon abandon abandon about"
    }

    private class FakeStore : SecureStore {
        val values = mutableMapOf<String, ByteArray>()

        /** Set to make the next [read] throw, the way a busy Keystore does. */
        var readFailure: (() -> Throwable)? = null

        /** Set to make [write] appear to succeed and store nothing. */
        var swallowWrites = false

        override fun read(key: String): ByteArray? {
            readFailure?.let { throw it() }
            return values[key]
        }

        override fun write(key: String, value: ByteArray) {
            if (swallowWrites) return
            values[key] = value
        }

        override fun contains(key: String): Boolean = values.containsKey(key)

        override fun remove(key: String) {
            if (values.remove(key) == null) {
                throw WalletStorageException("nothing stored under $key")
            }
        }
    }

    @Test
    fun `reads the phrase the app stored`() {
        val store = FakeStore().apply { values[KEY] = PHRASE.toByteArray() }

        val vault = SecureStoreSeedVault(store, KEY)

        assertEquals(PHRASE, vault.read())
        assertEquals(MnemonicPresence.Present, vault.presence())
    }

    @Test
    fun `a device with no wallet reports no usable mnemonic`() {
        val vault = SecureStoreSeedVault(FakeStore(), KEY)

        assertNull(vault.read())
        assertEquals(MnemonicPresence.NoUsableMnemonic, vault.presence())
    }

    /**
     * **BIT-20 rule 3. A Keystore that cannot answer has not answered "no".**
     *
     * `KeyStoreException` from a busy or unavailable provider is transient. If
     * it classified as absent, the caller one layer up treats the device's
     * existing LDK state as foreign and quarantines it — the fund-loss outcome,
     * arriving from one flaky call.
     */
    @Test
    fun `a transient keystore failure is unavailable, never absent`() {
        val store = FakeStore().apply { readFailure = { KeyStoreException("provider busy") } }

        val presence = SecureStoreSeedVault(store, KEY).presence()

        assertTrue(
            "expected Unavailable, got $presence",
            presence is MnemonicPresence.Unavailable,
        )
    }

    /**
     * The other side of the same asymmetry: the two terminal cases *do* mean
     * absent, because they are the routine ways a cache is lost and BIT-8 rule 3
     * says a lost cache routes to restore.
     */
    @Test
    fun `a blob that will never decrypt again is absent`() {
        listOf(
            { AEADBadTagException("tag mismatch") },
            { KeyPermanentlyInvalidatedException("key gone") },
        ).forEach { failure ->
            val store = FakeStore().apply { readFailure = failure }

            assertEquals(
                "the terminal cases route to restore, not to a retry",
                MnemonicPresence.NoUsableMnemonic,
                SecureStoreSeedVault(store, KEY).presence(),
            )
        }
    }

    /**
     * **A write that reported success and did not happen must not look like a
     * wallet.**
     *
     * The port of `persistSecret`'s `writeVerificationFailed`
     * (`CacheManager.swift:528–539`), and the reason this class does the
     * read-back rather than trusting `SecureStore.write` to throw: the store
     * throws on the failures it can see, and this catches the one it cannot.
     */
    @Test
    fun `a write that silently dropped is not reported as stored`() {
        val store = FakeStore().apply { swallowWrites = true }

        assertThrows(SeedWriteVerificationException::class.java) {
            SecureStoreSeedVault(store, KEY).store(PHRASE)
        }
    }

    @Test
    fun `refuses to store a blank phrase`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecureStoreSeedVault(FakeStore(), KEY).store("   ")
        }
    }

    /**
     * **Clearing a vault that is already empty is not a failure.**
     *
     * `removeWallet`'s contract is an ordering: the counter and the PIN go
     * first, the seed last, so a failure part-way leaves a wallet that can still
     * be opened. A `clear()` that threw because the seed was already gone would
     * abort that sequence on its final step — after a first attempt had removed
     * the seed and failed somewhere else — leaving the user unable to complete
     * the removal they asked for.
     */
    @Test
    fun `clearing an empty vault does not throw`() {
        val vault = SecureStoreSeedVault(FakeStore(), KEY)

        vault.clear()

        assertNull(vault.read())
    }

    @Test
    fun `clear removes the seed`() {
        val store = FakeStore().apply { values[KEY] = PHRASE.toByteArray() }
        val vault = SecureStoreSeedVault(store, KEY)

        vault.clear()

        assertFalse(store.contains(KEY))
        assertNull(vault.read())
    }
}
