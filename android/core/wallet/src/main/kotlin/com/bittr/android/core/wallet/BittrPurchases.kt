package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * A purchase or payout bittr confirmed through `GET /transaction_info` — iOS's `BittrTransaction`
 * turned into a `Transaction` with `isBittr` set (`createTransaction(isFundingTransaction:)`).
 *
 * @property bitcoinAmountSats what arrived, in satoshis.
 * @property transferFeeSats the on-chain fee, or the lightning connection's one-time setup fee.
 * @property bittrFee fiat, in [currency].
 * @property surcharge fiat, in [currency]; zero on purchases of 100 or more.
 * @property timestampSecs bittr's `datetime`, UTC.
 */
data class BittrPurchase(
    val txId: String,
    val currency: String?,
    val bitcoinAmountSats: Long?,
    val fiatNetAmount: Double?,
    val fiatGrossAmount: Double?,
    val transferFeeSats: Long?,
    val bittrFee: Double?,
    val surcharge: Double?,
    val historicalExchangeRate: Double?,
    val timestampSecs: Long?,
)

/** What the transaction screen reads about bittr purchases. `:app` binds it over the customer store. */
interface BittrPurchaseSource {

    /** Confirmed purchases and payouts, by transaction id. */
    val purchases: StateFlow<Map<String, BittrPurchase>>

    /** `CacheManager.getTxoID()`: the transaction that funded the lightning connection bittr opened. */
    fun fundingTxId(): String?

    /** The price of one bitcoin in [currencyCode] (`"EUR"` / `"CHF"`), for a purchase's profit. */
    suspend fun pricePerBitcoin(currencyCode: String): Double?

    /** No customer on this device, or a test. */
    object None : BittrPurchaseSource {
        override val purchases: StateFlow<Map<String, BittrPurchase>> = MutableStateFlow(emptyMap())
        override fun fundingTxId(): String? = null
        override suspend fun pricePerBitcoin(currencyCode: String): Double? = null
    }
}
