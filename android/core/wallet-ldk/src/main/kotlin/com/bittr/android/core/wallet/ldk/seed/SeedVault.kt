package com.bittr.android.core.wallet.ldk.seed

/**
 * The mnemonic's home on this device.
 *
 * The one thing to hold on to while reading this file: under BIT-8 rule 3 the
 * wrapped blob is a **cache, never the only copy**. Losing it must degrade to
 * "restore from mnemonic", never to "funds lost" and never to "cannot
 * restore". Every signature here is shaped by that.
 */
interface SeedVault {

    /**
     * What this device can say about the presence of a mnemonic *right now*.
     *
     * Deliberately three-valued. See [MnemonicPresence].
     */
    fun presence(): MnemonicPresence

    /** The mnemonic, or `null` if there is none. Throws on a transient failure. */
    fun read(): String?

    /**
     * Wrap and persist [mnemonic], then read it back and compare before
     * returning.
     *
     * The read-back is a port, not an embellishment: `persistSecret`
     * (`CacheManager.swift:528–539`) writes the secret, reads it straight back
     * and throws `writeVerificationFailed` on a mismatch. Without it a write
     * that fails silently leaves the app believing a wallet exists when nothing
     * recoverable was stored. The Android path has more surface for exactly
     * that — a wrap can succeed while the file write is truncated, and the key
     * can be invalidated between generation and use.
     *
     * Proved by `BlobWriteVerifiedTest`.
     */
    fun store(mnemonic: String)

    /** Remove the wrapped blob and its key. Used by the wallet-removal path. */
    fun clear()
}

/**
 * Three-way, where iOS is two-way — BIT-20 rule 3, adopted verbatim.
 *
 * iOS's guard is `guard try readSecretOrThrow(...) == nil else { return }`
 * (`CacheManager.swift:363`). `readSecretOrThrow` (`:570–576`) returns nil only
 * for genuine absence and **throws** on a read failure, so an unreadable
 * Keychain propagates out of `storeMnemonic()` and the seed import fails
 * outright. (The comment at `:364` describing "or is unreadable" belongs to the
 * non-throwing `readSecret` at `:558–565`, not to that call site.)
 *
 * Both literal readings of that break BIT-8 rule 3, in opposite directions:
 *
 * - read as *return early on unreadable* → the identity check is skipped in
 *   rule 3's routine case, and the user's own state is never re-adopted;
 * - read as what the code actually does, *propagate* → an invalidated Keystore
 *   key makes the restore path throw, so rule 3's routine case becomes "cannot
 *   restore". Loss of access. Strictly worse.
 *
 * Hence a third value. Collapsing [Unavailable] into [NoUsableMnemonic] would
 * quarantine live channel state on one flaky Keystore call — the fund-loss
 * outcome arriving by the back door.
 */
sealed interface MnemonicPresence {

    /** The blob decrypted. iOS behaviour: return early, touch nothing. */
    data object Present : MnemonicPresence

    /**
     * There is definitely no usable mnemonic on this device.
     *
     * Blob absent, alias absent, `KeyPermanentlyInvalidatedException`, or
     * `AEADBadTagException`. This is a deliberate divergence from what iOS
     * actually does, and it is mandated by BIT-8 rule 3: these are the routine
     * ways a *cache* is lost, and they must route to the restore screen.
     */
    data object NoUsableMnemonic : MnemonicPresence

    /**
     * The question could not be answered. Not an answer of "no".
     *
     * Abort the import and let the user retry. Never quarantine on this.
     */
    data class Unavailable(val cause: Throwable) : MnemonicPresence
}
