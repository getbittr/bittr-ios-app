package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.SecureStore

/**
 * [SeedVault] over the [SecureStore] the app already writes the mnemonic to.
 *
 * ## Why this exists, which is not the reason it looks like it exists
 *
 * There are two seed stores in this repo and they are both real. BIT-93 shipped
 * `SeedWalletService` over `:core:wallet-keystore`'s `KeystoreSecureStore`, and
 * that is where the mnemonic of every wallet created on a device so far
 * actually is. BIT-8/BIT-20 designed [WrappedSeedVault] — a wrapped blob at
 * `WalletPaths.seedBlobFile`, with the three-way presence classification and the
 * quarantine discriminator hanging off it — and that is where the mnemonic is
 * meant to end up.
 *
 * `LdkNodeFactory` reads through [SeedVault]. Binding it to [WrappedSeedVault]
 * today would build a node from a blob that nothing writes, so every start would
 * fail with `MnemonicUnavailableException` on a device that demonstrably has a
 * wallet. Binding it to this reads the seed the app has.
 *
 * **This is a bridge and it should not outlive the migration.** Reconciling the
 * two stores — which one is canonical, what a device holding only the old one
 * does on first launch after the change, and what the discriminator says about
 * state written under either — is a decision with a fund-loss failure mode in
 * it, and it is not this issue's. What this class does is make the node work
 * against today's storage without pre-empting that decision in either direction.
 *
 * ## What it deliberately does not do
 *
 * It does not classify presence by hand. [SeedVaultFailures] is the closed list
 * of "this blob will never decrypt again" and its whole design property is that
 * an unrecognised throwable means [MnemonicPresence.Unavailable] — abort — and
 * never [MnemonicPresence.NoUsableMnemonic] — quarantine. A second
 * classification written here would be a second chance to get that asymmetry
 * backwards, and getting it backwards costs a user their channel balance on one
 * flaky Keystore call.
 *
 * Proved by `SecureStoreSeedVaultTest`.
 */
class SecureStoreSeedVault(
    private val store: SecureStore,
    /**
     * The key the seed is under. Passed in rather than named here: the constant
     * belongs to `:core:wallet-seed`'s `SeedWalletService`, which this module
     * does not depend on and should not — the app is the one place that knows
     * both halves.
     */
    private val key: String,
) : SeedVault {

    override fun presence(): MnemonicPresence = try {
        if (read() != null) MnemonicPresence.Present else MnemonicPresence.NoUsableMnemonic
    } catch (throwable: Throwable) {
        SeedVaultFailures.classify(throwable)
    }

    /**
     * The mnemonic, or null when there is none. Throws on a transient failure.
     *
     * The three-valued distinction [SeedVault] exists to make, preserved
     * exactly: `SecureStore.read` returns null only for genuine absence and
     * throws for everything else, which is the same contract, so nothing here
     * flattens one into the other.
     *
     * A blob that is present but empty reads as absent. That is not a store the
     * app can write — `store` refuses a blank mnemonic — so it means a
     * truncated write, and "no seed" is the fail-safe reading of one: it routes
     * to the restore screen, where the user's own words fix it.
     */
    override fun read(): String? =
        store.read(key)?.toString(Charsets.UTF_8)?.takeIf { it.isNotBlank() }

    /**
     * Write, then read back and compare.
     *
     * The same read-back [WrappedSeedVault] does, and for the same reason: a
     * write that silently dropped leaves the app believing a wallet exists when
     * nothing recoverable was stored. `KeystoreSecureStore.write` throws on a
     * failure it can see; this catches the one it cannot.
     */
    override fun store(mnemonic: String) {
        require(mnemonic.isNotBlank()) { "refusing to store a blank mnemonic" }
        store.write(key, mnemonic.toByteArray(Charsets.UTF_8))

        val readBack = try {
            read()
        } catch (throwable: Throwable) {
            throw SeedWriteVerificationException(
                "seed did not read back after writing", throwable,
            )
        }
        if (readBack != mnemonic) {
            throw SeedWriteVerificationException(
                if (readBack == null) {
                    "seed was absent immediately after writing"
                } else {
                    "seed read back as a different value than was written"
                },
            )
        }
    }

    /**
     * Remove the seed.
     *
     * Guarded by [SecureStore.contains] because `remove` throws
     * `WalletStorageException` when there is nothing to remove on some bindings,
     * and a removal path that fails because the thing was already gone would
     * stop `WalletService.removeWallet` half-way through — which is the one
     * ordering that method's contract is about.
     */
    override fun clear() {
        if (store.contains(key)) store.remove(key)
    }
}
