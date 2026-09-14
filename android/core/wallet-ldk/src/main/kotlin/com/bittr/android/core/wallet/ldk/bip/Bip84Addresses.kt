package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.Bitcoin
import fr.acinq.bitcoin.Block
import fr.acinq.bitcoin.BlockHash

/**
 * The BIP84 receive and change addresses, derived on the JVM.
 *
 * **What this is for.** `wallet-core-spec` §6 states K4 as *"restore-from-mnemonic
 * on a fresh install reproduces the same descriptors, xpub and first 20 addresses
 * as iOS"*. [Bip84Account] covers the account xpub; nothing covered the addresses,
 * so the half of K4 the user actually sees — the address the receive screen shows
 * them after a restore — had no implementation and no test.
 *
 * That gap is worse than a missing assertion. A restore that reproduces the right
 * account xpub and the wrong addresses looks entirely healthy: the backend accepts
 * the account, the wallet starts, the balance is right, and the address the user
 * hands out belongs to a wallet nobody holds the keys for. Funds paid to it are
 * gone, and nothing reports an error at any point.
 *
 * **Why it is here rather than on BDK.** BDK derives these addresses in
 * production, and BDK is what iOS runs. But `bdk-android` is a UniFFI wrapper over
 * a native `.so`, so a claim expressed in terms of it can only be proved on an
 * emulator — and this module's definition of done is "each claim naming the test
 * that proves it" (see `WalletLayeringGuardTest`). So the derivation is written
 * twice, exactly as the account xpub already is:
 *
 * - **here, on bitcoin-kmp**, anchored to the published BIP84 test vectors by
 *   `Bip84AddressVectorTest`, which runs on every `./gradlew test`;
 * - **on BDK, natively**, asserted equal to this one by
 *   `BdkAddressParityTest` on a device.
 *
 * Neither test alone is the claim. The first says this implementation matches the
 * standard; the second says the implementation iOS ships matches this one. iOS
 * pins `bdk-swift 1.2.0` and Android pins `bdk-android 1.2.0` — the same Rust
 * core behind two bindings — which is what makes the second one parity with iOS
 * rather than parity with Android.
 *
 * **This derives addresses, it does not track them.** Gap limits, used-address
 * scanning and the receive index all belong to BDK's wallet, which owns that
 * state. Nothing here is on the path that hands an address to a user; it exists
 * to be compared against the path that does.
 */
object Bip84Addresses {

    /** BIP44 change level: 0 = external (receive), 1 = internal (change). */
    private const val EXTERNAL = 0
    private const val INTERNAL = 1

    /**
     * The chain hash the address encoding is keyed on.
     *
     * Signet and testnet share the `tb` human-readable part, so this choice is
     * not observable in the output for non-mainnet — but the regtest build runs
     * signet (`Bip84Account.accountPath`), and naming the chain we actually run
     * keeps this honest if a future chain stops sharing the HRP.
     */
    private fun chainHash(mainnet: Boolean): BlockHash =
        if (mainnet) Block.LivenetGenesisBlock.hash else Block.SignetGenesisBlock.hash

    /**
     * The P2WPKH address at `m/84'/<coin>'/0'/<change>/<index>`.
     *
     * [change] is the BIP44 change level rather than a boolean because that is
     * how it appears in the path, and a boolean at the call site reads as
     * "is change?" in one place and "is receive?" in the next.
     */
    fun addressAt(
        mnemonic: String,
        mainnet: Boolean,
        change: Int,
        index: Int,
        passphrase: String = "",
    ): String {
        require(change == EXTERNAL || change == INTERNAL) {
            "BIP44 change level must be 0 (receive) or 1 (change), was $change"
        }
        require(index >= 0) { "Address index must be non-negative, was $index" }

        val account = Bip84Account.accountKey(mnemonic, mainnet, passphrase)
        val key = account.derivePrivateKey("$change/$index")
        return Bitcoin.computeBIP84Address(key.publicKey, chainHash(mainnet))
    }

    /** The first [count] receive addresses, in index order from 0. */
    fun receiveAddresses(
        mnemonic: String,
        mainnet: Boolean,
        count: Int,
        passphrase: String = "",
    ): List<String> = addresses(mnemonic, mainnet, EXTERNAL, count, passphrase)

    /** The first [count] change addresses, in index order from 0. */
    fun changeAddresses(
        mnemonic: String,
        mainnet: Boolean,
        count: Int,
        passphrase: String = "",
    ): List<String> = addresses(mnemonic, mainnet, INTERNAL, count, passphrase)

    private fun addresses(
        mnemonic: String,
        mainnet: Boolean,
        change: Int,
        count: Int,
        passphrase: String,
    ): List<String> {
        require(count >= 0) { "Address count must be non-negative, was $count" }
        // Derived from the account key once rather than re-deriving the master key
        // per address: BIP39 seed derivation is 2048 rounds of PBKDF2, and the
        // parity test asks for 40 addresses.
        val account = Bip84Account.accountKey(mnemonic, mainnet, passphrase)
        val hash = chainHash(mainnet)
        return (0 until count).map { index ->
            Bitcoin.computeBIP84Address(account.derivePrivateKey("$change/$index").publicKey, hash)
        }
    }
}
