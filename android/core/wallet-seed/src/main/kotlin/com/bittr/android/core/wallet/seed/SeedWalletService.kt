package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A [WalletService] with a real seed and no funds.
 *
 * It generates a BIP-39 phrase from `SecureRandom`, hands it to [store] to persist,
 * and gates it behind a PIN. It does not open a node, sync a chain or hold a
 * balance — [start] and [stop] are no-ops until BIT-6 lands `:core:wallet-ldk`. That
 * split is the point of BIT-93: the seed is the part the user has to write down and
 * the part that has to survive a force-quit, and it is separable from the funds.
 *
 * ### Where the protection actually is
 *
 * The PIN does **not** encrypt the seed. [store] does, with a key the platform
 * holds — on Android a non-auth-bound Keystore AES/GCM key, which is the faithful
 * port of the mnemonic's iOS Keychain class `afterFirstUnlockThisDeviceOnly`
 * (BIT-8's decision, verified by BIT-18). The PIN is the app-level gate iOS also
 * runs, and what is stored for it is a PBKDF2 verifier, never the PIN.
 *
 * Deriving the storage key from a 4-digit PIN would be worse, not better: 10,000
 * candidates is not a key, and it would make the seed unrecoverable if the user
 * changed their PIN. Keeping the two separate is deliberate.
 *
 * ### Setup is atomic from the user's point of view
 *
 * A seed with no PIN is not a wallet. [state] stays [WalletState.Uninitialized]
 * until [setPin] succeeds, so a user who force-quits halfway through the arc comes
 * back to the start of signup rather than to a PIN screen for a phrase they never
 * finished writing down. Running the arc again replaces the unfinished seed.
 */
class SeedWalletService(
    private val store: SecureStore,
    private val random: SecureRandom = SecureRandom(),
) : WalletService {

    private val _state = MutableStateFlow(storedState())
    override val state: StateFlow<WalletState> = _state.asStateFlow()

    override suspend fun createWallet(): Mnemonic {
        val mnemonic = Bip39.generate(random)
        // Persist before returning. The screen may not show the user a phrase that
        // is not on the device — see WalletService.createWallet.
        store.write(KEY_SEED, mnemonic.phrase.toByteArray(Charsets.UTF_8))
        store.removeIfPresent(KEY_PIN)
        _state.value = storedState()
        return mnemonic
    }

    override suspend fun restoreWallet(mnemonic: Mnemonic) {
        // Identical to createWallet from the seed's point of view — the only
        // difference is where the entropy came from, and the store does not care.
        // Clearing the PIN keeps the invariant that a restored wallet is
        // Uninitialized until setPin runs, so an abandoned restore does not leave
        // the user facing a PIN screen for a phrase they gave up on.
        store.write(KEY_SEED, mnemonic.phrase.toByteArray(Charsets.UTF_8))
        store.removeIfPresent(KEY_PIN)
        _state.value = storedState()
    }

    override suspend fun setPin(pin: String) {
        require(isValidPin(pin)) { "PIN must be $MIN_PIN_LENGTH–$MAX_PIN_LENGTH digits" }
        if (!store.contains(KEY_SEED)) {
            throw WalletStorageException("Cannot set a PIN before a wallet exists")
        }
        val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
        store.write(KEY_PIN, salt + derive(pin, salt))
        _state.value = WalletState.Locked
    }

    override suspend fun unlock(pin: String): Boolean {
        val stored = store.read(KEY_PIN) ?: return false
        if (stored.size != SALT_BYTES + KEY_BYTES) return false
        val salt = stored.copyOfRange(0, SALT_BYTES)
        val expected = stored.copyOfRange(SALT_BYTES, stored.size)
        // Constant-time: a timing signal on a 4-digit secret is worth removing even
        // though an attacker at this point already has the unlocked device.
        if (!MessageDigest.isEqual(expected, derive(pin, salt))) return false
        _state.value = WalletState.Ready
        return true
    }

    /** No node yet — BIT-6. Present so the seam does not change shape when it lands. */
    override suspend fun start() = Unit

    override suspend fun stop() = Unit

    private fun storedState(): WalletState =
        if (store.contains(KEY_SEED) && store.contains(KEY_PIN)) {
            WalletState.Locked
        } else {
            WalletState.Uninitialized
        }

    private fun derive(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, PBKDF2_ITERATIONS, KEY_BYTES * 8)
        return try {
            SecretKeyFactory.getInstance(PBKDF2_ALGORITHM).generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }

    private fun SecureStore.removeIfPresent(key: String) {
        if (contains(key)) remove(key)
    }

    companion object {
        const val KEY_SEED = "wallet.seed"
        const val KEY_PIN = "wallet.pin"

        /** iOS `pinshouldbe4to8`, and `Signup5ViewController`'s `count > 3`. */
        const val MIN_PIN_LENGTH = 4
        const val MAX_PIN_LENGTH = 8

        private const val PBKDF2_ALGORITHM = "PBKDF2WithHmacSHA256"

        /**
         * Chosen for the device, not for the threat model on paper: the PIN space is
         * 10^4–10^8, so the verifier's only job is to make offline guessing cost
         * something if the blob ever leaks. 120k iterations is roughly a quarter of a
         * second on the slowest minSdk-26 hardware, which is invisible behind a PIN
         * pad and turns a full 4-digit sweep into minutes rather than milliseconds.
         */
        private const val PBKDF2_ITERATIONS = 120_000
        private const val SALT_BYTES = 16
        private const val KEY_BYTES = 32

        fun isValidPin(pin: String): Boolean =
            pin.length in MIN_PIN_LENGTH..MAX_PIN_LENGTH && pin.all { it.isDigit() }
    }
}
