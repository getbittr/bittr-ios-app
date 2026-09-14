package com.bittr.android.feature.receive

import kotlinx.coroutines.flow.StateFlow

/**
 * Everything Receive asks of the wallet, as one seam `:app` implements over the engine.
 *
 * Each member names the iOS call it replaces. Nothing here is a node type: this module
 * depends on `:core:common` and the design system and nothing wallet-specific, so the
 * screen and its controller can be driven on the JVM with a fake.
 */
interface ReceiveSource {

    /** `lightningIsAvailable()` — `lightningChannels.getActiveChannel() != nil`. */
    fun lightningAvailable(): Boolean

    /**
     * `userLNURL()` — the bittr account's lightning address, as the full `user@host`
     * string the QR encodes. Null when the account has none (and always, until the bittr
     * account is ported).
     */
    fun lightningAddress(): String?

    /**
     * `onchainAddressesVerified` — the address pool has finished checking which addresses
     * are used. Receive waits for it (at most [ReceiveController.ADDRESS_VERIFICATION_TIMEOUT_MS])
     * before showing an on-chain address, so it never shows one that was already used.
     */
    val addressesVerified: StateFlow<Boolean>

    /** `getCachedOnchainAddress()` — the address currently shown, or null. */
    fun currentOnchainAddress(): String?

    /**
     * `onchainAddresses.getNextUnusedAddress()` — advance to the next unused address in the
     * pool and make it the current one. Null when the pool has none left.
     */
    fun nextOnchainAddress(): String?

    /** `getZeroInvoice(enteredDescription:)`. Null if the node could not create one. */
    suspend fun zeroAmountInvoice(description: String): String?

    /** `getRegularInvoice(amountMsat:description:expirySecs:)`, one hour expiry. */
    suspend fun invoice(amountSats: Long, description: String): String?

    /** The display currency iOS offers in the currency picker, e.g. `EUR` / `€`. */
    fun fiatCurrency(): FiatCurrency

    /** `getCorrectBitcoinValue().currentValue` — the price of one bitcoin, or null if unknown. */
    suspend fun fiatPricePerBitcoin(): Double?
}

/** @property code the currency label (`EUR`); @property symbol the picker button (`€`). */
data class FiatCurrency(val code: String, val symbol: String)
