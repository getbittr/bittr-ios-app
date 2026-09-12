package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.StateFlow

/**
 * The seam between the app and the wallet layer.
 *
 * Scope note: this is deliberately the smallest API the app needs — enough for
 * navigation to ask "is there a wallet yet?", for signup to create one, and for
 * the app to drive node lifecycle. It is **not** a design for the wallet layer.
 * BIT-6 owns that, and should widen this interface as ldk-node and BDK require
 * rather than treat the shape below as agreed. Nothing in :app or :feature:* may
 * depend on a wallet type that is not declared in this module.
 *
 * ### What "creating a wallet" means here
 *
 * BIT-93 widened this interface for **seed creation only**: generating BIP-39 key
 * material and storing it so it survives a force-quit. Holding funds — ldk-node,
 * BDK, sync, channels, node lifecycle — is separable and stays with BIT-6. A build
 * that implements this interface has a real seed and no funds; [start] and [stop]
 * are still the stub's no-ops until BIT-6 lands.
 */
interface WalletService {

    /** Current wallet state. Cold consumers can read [StateFlow.value] for a snapshot. */
    val state: StateFlow<WalletState>

    /**
     * Generate a new 12-word BIP-39 mnemonic from `SecureRandom` entropy and persist
     * it before returning.
     *
     * Persisting first is the contract, not an implementation detail. iOS aborts the
     * signup arc when the seed cannot be stored (`Signup1ViewController`, the
     * `getNewMnemonic()` catch) rather than walking the user through a backup of a
     * seed that is not on the device — a wallet they then fund would be
     * unrecoverable. Callers must treat [WalletStorageException] the same way.
     *
     * Setup is not complete until [setPin] has also succeeded; see [WalletState].
     * Calling this again before then replaces the unfinished seed.
     *
     * @throws WalletStorageException if the seed cannot be written to secure storage.
     */
    suspend fun createWallet(): Mnemonic

    /**
     * Adopt an existing phrase the user typed in, persisting it before returning.
     *
     * The same contract as [createWallet] on every point that matters — persist or
     * throw, and setup is not complete until [setPin] has also succeeded — and one
     * that differs: **this does not generate anything, and it must not validate
     * anything either.** By the time a caller reaches here the phrase has already
     * been through `SeedPhraseEntry.check`, which is where a mistyped word is caught
     * and told to the user in words they can act on. An implementation that silently
     * re-checked and threw would turn that into a storage error.
     *
     * Restoring replaces whatever unfinished seed is on the device, matching
     * [createWallet]. It does not replace a *finished* wallet: the arc is only
     * reachable from signup, so there is nothing to overwrite. Wiping a funded wallet
     * is `removeWalletButton`'s job and it asks first — see BIT-7.
     *
     * @throws WalletStorageException if the seed cannot be written to secure storage.
     */
    suspend fun restoreWallet(mnemonic: Mnemonic)

    /**
     * Set the PIN that gates this wallet, completing setup.
     *
     * The PIN is an app-level gate, not the thing that protects the seed at rest —
     * that is the platform's job, and on Android it is an Android Keystore key. The
     * implementation stores a verifier it can check [unlock] against, never the PIN.
     *
     * @throws IllegalArgumentException if [pin] is not 4–8 digits, matching the iOS
     *   `pinshouldbe4to8` rule.
     * @throws WalletStorageException if the verifier cannot be written.
     */
    suspend fun setPin(pin: String)

    /**
     * Check [pin] against the stored verifier and, on a match, move to
     * [WalletState.Ready].
     *
     * **This counts.** A wrong PIN increments [failedUnlockAttempts] and a correct one
     * resets it to zero, in the same call that does the check — the count is what
     * [PinLockout] turns into the warning and the wipe, and a caller that had to
     * remember to increment it separately would eventually forget on one branch and
     * hand an attacker unlimited guesses.
     *
     * It does **not** enforce the lockout. iOS checks the count before verifying
     * (`PinViewController`, the `>= 10` guard above the wrong-PIN branch) so that a
     * correct tenth entry still unlocks, and so the wipe can be resumed at launch
     * without a PIN being typed at all. Reproducing that ordering is the caller's job;
     * see [failedUnlockAttempts] and [removeWallet].
     *
     * @return true when the PIN was correct. A wrong PIN returns false and leaves the
     *   state untouched; it is not an exception, because the user getting it wrong is
     *   the expected case.
     */
    suspend fun unlock(pin: String): Boolean

    /**
     * Wrong PIN entries since the last successful [unlock].
     *
     * Durable, not in-memory. The whole point of the counter is that force-quitting
     * the app must not buy another ten guesses, so it outlives the process exactly as
     * the iOS Keychain counter does (`CacheManager.getFailedPinAttempts`).
     *
     * **Reads fail open at 0**, matching iOS: a transient secure-storage error that
     * read as "lots of failures" would wipe a wallet that was never attacked, which is
     * a far worse outcome than granting a few extra attempts.
     */
    suspend fun failedUnlockAttempts(): Int

    /**
     * True when [mnemonic] is the phrase this device's wallet was created from.
     *
     * The gate on the non-destructive forgot-PIN path — iOS's
     * `currentMnemonic == enteredMnemonic` in `RestoreViewController`. It is phrased
     * as a question rather than as a getter on purpose: nothing in the app needs to
     * *read* the stored seed, and an interface that offered it would be an interface
     * someone could log.
     *
     * @return false when there is no wallet, rather than throwing — a caller asking
     *   this question on a device with no wallet has the same answer either way.
     */
    suspend fun holdsSeed(mnemonic: Mnemonic): Boolean

    /**
     * Set a new PIN on the existing wallet and unlock it. **Non-destructive.**
     *
     * This is the whole value of the forgot-PIN path: the user who still has their
     * recovery phrase gets back in without the wallet — and any funds in it — being
     * erased. The seed is not rewritten, only the PIN verifier is, and the failed
     * attempt counter is cleared because the user has just proved ownership by a
     * stronger means than the PIN.
     *
     * [mnemonic] is required rather than assumed-checked: the screen checks it with
     * [holdsSeed] so it can tell the user, and this checks it again so that the one
     * operation that hands out access to an existing wallet cannot be reached by a
     * caller that forgot to.
     *
     * @throws IllegalArgumentException if [pin] is not 4–8 digits.
     * @throws WrongSeedException if [mnemonic] is not this wallet's phrase, or there
     *   is no wallet on the device.
     * @throws WalletStorageException if the new verifier cannot be written.
     */
    suspend fun resetPin(mnemonic: Mnemonic, pin: String)

    /**
     * Erase the wallet from this device: seed, PIN verifier and attempt counter.
     *
     * The destructive half of iOS's `performWalletReset`, and the end of the lockout
     * path — ten wrong PINs and the wallet is gone, along with anything it held. After
     * this, [state] is [WalletState.Uninitialized] and the app is back at signup.
     *
     * **Order matters, and it is the implementation's contract.** The counter and the
     * PIN go first and the seed goes last, so a failure part-way through leaves a
     * wallet that can still be unlocked rather than a seed with no way in. iOS makes
     * the same choice — `CacheManager.deleteClientInfo()` runs only after the node has
     * stopped and the files are gone.
     *
     * Cooperatively closing Lightning channels before the wipe is BIT-6's; this
     * removes key material and nothing else.
     *
     * @throws WalletStorageException if key material could not be removed. The caller
     *   must not tell the user the wallet is gone when it is not.
     */
    suspend fun removeWallet()

    /**
     * Bring the wallet up: load key material, start the Lightning node, begin sync.
     *
     * On Android this will not be a plain suspend call for long — process death is
     * routine, so the real implementation is expected to be backed by a foreground
     * service. See ANDROID_PORT_PLAN.md and the semantic-gap checklist in the
     * inventory doc.
     */
    suspend fun start()

    /** Take the wallet down cleanly. Must be safe to call when already stopped. */
    suspend fun stop()
}

/**
 * Coarse wallet lifecycle. Mirrors the states the iOS app's entry point branches on:
 * no wallet yet (→ signup), wallet present but locked (→ PIN), wallet usable (→ home).
 */
enum class WalletState {
    /**
     * No usable key material on the device. The user has not created or restored a
     * wallet — or started the arc and abandoned it before setting a PIN, which counts
     * as not having one.
     */
    Uninitialized,

    /** Key material exists but is not unlocked for use. */
    Locked,

    /** Wallet is unlocked and the node is running. */
    Ready,
}

/**
 * Secure storage for the small, sensitive blobs the wallet owns.
 *
 * Kept as an interface here so the wallet logic stays pure Kotlin and JVM-testable.
 * The production binding is `:core:wallet-keystore`, which wraps each value with a
 * non-auth-bound Android Keystore AES/GCM key — the faithful port of the mnemonic's
 * iOS Keychain class `afterFirstUnlockThisDeviceOnly` (`CacheManager.swift:358`).
 * BIT-8 decided that; BIT-18 verifies it.
 *
 * [write] and [remove] throw [WalletStorageException] rather than returning a flag,
 * so a caller cannot proceed past a failed save by ignoring a boolean.
 */
interface SecureStore {

    /** The stored bytes, or null when nothing is stored under [key]. */
    fun read(key: String): ByteArray?

    /** @throws WalletStorageException if the value cannot be stored durably. */
    fun write(key: String, value: ByteArray)

    fun contains(key: String): Boolean

    /** @throws WalletStorageException if an existing value cannot be removed. */
    fun remove(key: String)
}

/**
 * Secure storage failed.
 *
 * Signup surfaces this as the iOS `mnemonicsavefail` alert and refuses to advance.
 * The message is for logs; it must never carry key material.
 */
class WalletStorageException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

/**
 * The phrase offered on the forgot-PIN path is not this wallet's.
 *
 * Separate from [WalletStorageException] because the two mean opposite things to the
 * user: storage failed is "try again", a wrong phrase is "check your backup". iOS
 * shows `forgotpin3` for this one.
 *
 * The message must never quote either phrase — see [Mnemonic].
 */
class WrongSeedException(message: String) : Exception(message)
