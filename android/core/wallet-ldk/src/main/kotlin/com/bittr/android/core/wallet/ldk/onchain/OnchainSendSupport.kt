package com.bittr.android.core.wallet.ldk.onchain

/**
 * What Send needs from the BDK wallet: whether it can be asked yet, and the two previews
 * the screen quotes amounts and fees from.
 *
 * An interface so `:app` can hand it to the Send source without naming a BDK type —
 * `:core:wallet-ldk` depends on bdk-android with `implementation`.
 */
interface OnchainSendSupport {

    /** `bdkWallet != nil && bdkWalletHasBeenScanned` — open, and the full scan has applied. */
    val isReady: Boolean

    /** The unclamped drain to [address] (or the largest common output), or null with no wallet. */
    fun drainPreview(address: String?, satPerVb: ULong): OnchainDrainPreview?

    /** The vsize of paying [amountSats] to [address], or null with no wallet. Throws BDK's error. */
    fun transactionVsize(address: String, amountSats: Long, satPerVb: ULong): ULong?
}
