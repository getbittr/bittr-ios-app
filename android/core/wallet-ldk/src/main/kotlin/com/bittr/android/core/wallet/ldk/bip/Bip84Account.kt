package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.DeterministicWallet
import fr.acinq.bitcoin.MnemonicCode

/**
 * BIP39 → BIP32 → the BIP84 account key, on the JVM.
 *
 * **Why this is not done with BDK.** BDK can produce the same account xpub —
 * `Descriptor.newBip84` embeds it, which is where iOS reads it from
 * (`BDKManager.swift:127–139`). But bdk-android is a UniFFI wrapper over a
 * native `.so`, so anything built on it can only run on a device. Two callers
 * cannot live with that:
 *
 * 1. **The BIT-20 discriminator.** The guard has to decide whether a state
 *    directory belongs to the incoming seed *before* anything is booted against
 *    that directory. Deriving from the mnemonic alone is the only ordering that
 *    works, and it is one of the reasons BIT-20 chose the account xpub over the
 *    node id.
 * 2. **The iOS derivation vectors.** They are the evidence for "restore
 *    reproduces the same wallet", and evidence that only runs on hardware CI
 *    does not have yet is evidence nobody sees.
 *
 * Both derivations must agree, and that is not assumed: the instrumented
 * `BdkAccountXpubParityTest` derives the account xpub both ways on a device and
 * asserts they are the same string.
 *
 * Encoding is `xpub`/`tpub` — the BIP32 prefixes, not `zpub`/`vpub` — because
 * that is what BDK puts in the descriptor and therefore what iOS POSTs as
 * `xpub_key` (`Transfer2ViewController.swift:344–362`).
 */
object Bip84Account {

    /**
     * Coin type 1 for every non-mainnet chain, per BIP44. iOS runs signet in
     * the regtest build and reads the same `m/84'/1'/0'` path — the pinned test
     * vector in `BitcoinMessage.swift:363–367` is `m/84'/1'/0'/0/0`.
     */
    fun accountPath(mainnet: Boolean): String = if (mainnet) "m/84'/0'/0'" else "m/84'/1'/0'"

    /**
     * The serialized BIP84 account extended public key.
     *
     * This is the discriminator's input, and it is deliberately a *public* key:
     * recording it introduces no new secret, so BIT-8 rule 1 — the mnemonic is
     * the single root of recovery — is untouched.
     */
    fun accountXpub(mnemonic: String, mainnet: Boolean, passphrase: String = ""): String {
        val account = accountKey(mnemonic, mainnet, passphrase)
        return account.extendedPublicKey.encode(testnet = !mainnet)
    }

    /** The account-level extended *private* key. Never persisted, never logged. */
    fun accountKey(
        mnemonic: String,
        mainnet: Boolean,
        passphrase: String = "",
    ): DeterministicWallet.ExtendedPrivateKey =
        masterKey(mnemonic, passphrase).derivePrivateKey(accountPath(mainnet))

    /** BIP32 master key from the BIP39 seed. `password: nil` on iOS is the empty passphrase. */
    fun masterKey(
        mnemonic: String,
        passphrase: String = "",
    ): DeterministicWallet.ExtendedPrivateKey =
        DeterministicWallet.generate(MnemonicCode.toSeed(mnemonic, passphrase))

    /** Derive at an arbitrary path. Used by the iOS parity vectors and by swap refund keys. */
    fun derive(
        mnemonic: String,
        path: String,
        passphrase: String = "",
    ): DeterministicWallet.ExtendedPrivateKey =
        masterKey(mnemonic, passphrase).derivePrivateKey(path)

    /**
     * Boltz swap refund keys, at the path iOS uses
     * (`SwapManager.swift:196–203`): `m/503'/0'/0'/0/<swapIndex>`.
     *
     * Here because it is the evidence for BIT-8 rule 1. The Keychain/Keystore
     * copy of a refund key is a cache like everything else — given the swap
     * index, which the cache holds, the key is re-derivable from the mnemonic.
     * Were that not true, the refund keys would be a second irreplaceable
     * secret and rule 1 would already be violated by the shipping iOS app.
     *
     * Proved by `SwapRefundKeyDerivationTest`.
     */
    fun swapRefundKey(
        mnemonic: String,
        swapIndex: Int,
        passphrase: String = "",
    ): DeterministicWallet.ExtendedPrivateKey =
        derive(mnemonic, "m/503'/0'/0'/0/$swapIndex", passphrase)
}
