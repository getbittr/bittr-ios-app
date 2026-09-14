package com.bittr.android.core.wallet.ldk.adapter

import org.lightningdevkit.ldknode.Bolt11Invoice

/** What a BOLT11 invoice says, read by ldk-node. */
data class Bolt11Facts(
    /** `amountMilliSatoshis()`, or null for an invoice that leaves the amount open. */
    val amountMsat: Long?,
    /** `paymentHash()`, lower-case hex. */
    val paymentHashHex: String,
)

/**
 * The full BOLT11 decode — iOS's `String.bolt11Invoice()`. The swap checks need the payment hash,
 * which `:core:common`'s human-readable-part parser does not read; only the node's decoder does.
 */
object Bolt11Decoder {

    /** Null when [invoice] does not parse. */
    fun decode(invoice: String): Bolt11Facts? = runCatching {
        Bolt11Invoice.fromStr(invoice).use { parsed ->
            Bolt11Facts(parsed.amountMilliSatoshis()?.toLong(), parsed.paymentHash().lowercase())
        }
    }.getOrNull()
}
