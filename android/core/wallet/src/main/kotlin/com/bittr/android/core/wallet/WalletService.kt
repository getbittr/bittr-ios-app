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
     * @return true when the PIN was correct. A wrong PIN returns false and leaves the
     *   state untouched; it is not an exception, because the user getting it wrong is
     *   the expected case.
     */
    suspend fun unlock(pin: String): Boolean

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
