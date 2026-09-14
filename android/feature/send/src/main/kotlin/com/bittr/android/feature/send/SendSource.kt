package com.bittr.android.feature.send

import com.bittr.android.core.common.destination.BitcoinNetwork
import kotlinx.coroutines.flow.Flow

/**
 * Everything Send reads from and asks of the wallet. `:app` implements it over the node,
 * the BDK wallet and the price and fee endpoints; tests implement it with fixed answers.
 */
interface SendSource {

    /** Which chain an address or invoice has to be on. */
    val network: BitcoinNetwork

    /** Emits whenever the wallet's balances may have changed, so "You can send" can refresh. */
    val walletUpdates: Flow<Any>

    /** The BDK wallet is open and scanned, so on-chain amounts can be quoted. */
    fun onchainReady(): Boolean

    /** Waits for [onchainReady]; false if the scan failed or took too long. */
    suspend fun awaitOnchainReady(): Boolean

    /** ldk-node's spendable on-chain balance — `satoshisOnchainSpendable`. */
    fun onchainSpendableSats(): Long

    /** The active channel's outbound capacity. */
    fun lightningSendableSats(): Long

    suspend fun feeEstimates(): FeeEstimates?

    /** The drain to [address] (or to the largest common output), clamped; null if it cannot be built. */
    suspend fun drainQuote(address: String?, satPerVb: Long): DrainQuote?

    /** The vsize of paying [amountSats] to [address]; a failure carries a message to show. */
    suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long): Result<Long>

    /** Broadcast; the txid on success. [sendAll] drains, keeping the channel reserve. */
    suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long, sendAll: Boolean): Result<String>

    /**
     * Pay a BOLT11 invoice and wait for it to settle; the payment id on success.
     * [amountSats] is only passed for an invoice without an amount.
     */
    suspend fun payInvoice(invoice: String, amountSats: Long?): Result<String>

    /**
     * Sync the wallet and return the history id of the payment [id] if it has shown up —
     * iOS's `syncWallets()` then `listPayments().first { ... }`. Null when it has not yet.
     */
    suspend fun settledTransactionId(id: String): String?

    fun fiatCurrency(): FiatCurrency

    suspend fun fiatPricePerBitcoin(): Double?
}
