package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletActivity
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

/**
 * What the transaction screen shows — `TransactionViewController.setTransactionData()` for
 * a plain on-chain or Lightning transaction. Bittr purchases and swaps have their own
 * sections on iOS and are not ported yet.
 *
 * @property fees only for a transaction that took money out (`received - sent - fee < 0`).
 * @property confirmations only on-chain; "Unconfirmed" until it has one.
 * @property explorerId set for on-chain transactions, which have an explorer page.
 * @property description `descriptionText()`: for now only the channel-closure sentence, because
 *   ldk-node reports no invoice description and Receive does not cache one yet.
 * @property note the user's note, or null for "Add a note".
 */
internal data class TransactionDetail(
    val id: String,
    val date: String,
    val amount: String,
    val isLightning: Boolean,
    val fees: String?,
    val confirmations: String?,
    val explorerId: String?,
    val currentValue: String?,
    val description: String? = null,
    val note: String? = null,
)

internal fun transactionDetail(
    activity: WalletActivity,
    price: FiatPrice?,
    currentHeight: Int?,
    timeZone: TimeZone = TimeZone.getDefault(),
    closureTxIds: Set<String> = emptySet(),
    note: String? = null,
): TransactionDetail {
    val format = SimpleDateFormat("dd MMM yyyy HH:mm", Locale.ENGLISH).apply { this.timeZone = timeZone }
    val gross = activity.receivedSats - activity.sentSats
    val height = activity.confirmationHeight
    return TransactionDetail(
        id = activity.id,
        date = format.format(Date(activity.timestampSecs * 1000)).removePrefix("0"),
        amount = "${if (gross < 0) "-" else "+"} ${groupThousands(abs(gross))} sats",
        isLightning = activity.isLightning,
        fees = if (activity.netSats < 0) "${groupThousands(activity.feeSats)} sats" else null,
        confirmations = when {
            activity.isLightning -> null
            height == null || (currentHeight ?: 0) - height + 1 < 1 -> HomeStrings.UNCONFIRMED
            else -> groupThousands(((currentHeight ?: 0) - height + 1).toLong())
        },
        explorerId = if (activity.isLightning) null else activity.id,
        currentValue = price?.let { "${twoDecimals(abs(activity.netSats) / SATS_PER_BITCOIN * it.pricePerBitcoin)} ${it.symbol}" },
        // `isChannelClosure`: the payout's txid is one the closure scan recorded.
        description = if (!activity.isLightning && activity.id in closureTxIds) HomeStrings.CHANNEL_CLOSURE_TRANSACTION else null,
        note = note?.takeIf { it.isNotBlank() },
    )
}

/** A fiat figure with its whole part grouped and two decimals, e.g. "1 234.50". */
internal fun twoDecimals(value: Double): String {
    val rounded = BigDecimal(value).setScale(2, RoundingMode.HALF_UP)
    val whole = rounded.toBigInteger().toLong()
    val cents = rounded.remainder(BigDecimal.ONE).movePointRight(2).toInt()
    return "${groupThousands(whole)}.${cents.toString().padStart(2, '0')}"
}

private const val SATS_PER_BITCOIN = 100_000_000.0
