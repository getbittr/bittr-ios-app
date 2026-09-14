package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.StateFlow

/**
 * The user's notes on transactions — iOS's `CacheManager` `transactionnotes` dictionary
 * (`storeTransactionNote`, `getTransactionNote`, `deleteTransactionNote`), keyed by the id the
 * history row carries ([WalletActivity.id]: the on-chain txid or the Lightning preimage, else
 * the payment id).
 *
 * Also where Send puts an LNURL pay request's description once it is paid, as iOS does.
 */
interface TransactionNoteStore {

    /** Every note, by transaction id. */
    val notes: StateFlow<Map<String, String>>

    /** Stores [note], trimmed; a blank note deletes the entry, as clearing the field does on iOS. */
    fun store(transactionId: String, note: String)
}
