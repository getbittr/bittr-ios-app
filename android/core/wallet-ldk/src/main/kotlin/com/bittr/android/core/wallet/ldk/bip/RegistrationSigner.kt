package com.bittr.android.core.wallet.ldk.bip

/**
 * The on-chain half of bittr registration: sign the `bitcoin_message` with the key of the first
 * receive address — iOS's `BitcoinManager.signMessageForPath(path: defaultBip84SigningPath(),
 * message:)` (`BitcoinManager.swift:774-784`), used by `Transfer2ViewController.gatherParameters`.
 *
 * The seed is read per call, never held: the same rule `BdkOnchainWalletHolder` follows, because
 * the wallet can be removed while the app runs.
 *
 * @param mnemonic the stored phrase, or null when there is none.
 * @param mainnet false for development builds, whose coin type is 1 — iOS's
 *   `EnvironmentConfig.isDevelopment`.
 */
class RegistrationSigner(
    private val mnemonic: () -> String?,
    private val mainnet: Boolean,
) {

    /** The path signed with, `m/84'/{1 dev, 0 prod}'/0'/0/0`. */
    val path: String get() = BitcoinMessageSigner.defaultSigningPath(mainnet)

    /** The base64 P2WPKH message signature, or null when there is no seed to sign with. */
    fun sign(message: String): String? {
        val phrase = mnemonic() ?: return null
        val key = Bip84Account.derive(phrase, path).privateKey
        return BitcoinMessageSigner.signP2wpkh(message, key)
    }
}
