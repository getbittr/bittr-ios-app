package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletActivity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * One row of Home's history, already formatted — `HistoryTable.swift`'s
 * `cellForRowAt`, without the cell.
 *
 * @property year shown above the row when it starts a new year, as iOS does from the
 *   second row on.
 * @property fiat null while there is no price to convert with.
 * @property unconfirmed an on-chain transaction with no confirmation yet, which iOS
 *   colours `unconfirmed`. Never true for Lightning.
 */
data class HistoryRow(
    val id: String,
    val day: String,
    val year: String?,
    val sats: String,
    val fiat: String?,
    val isLightning: Boolean,
    val unconfirmed: Boolean,
)

internal fun historyRows(
    transactions: List<WalletActivity>,
    price: FiatPrice?,
    currentHeight: Int?,
    timeZone: TimeZone = TimeZone.getDefault(),
): List<HistoryRow> {
    val dayFormat = SimpleDateFormat("MMM dd", Locale.ENGLISH).apply { this.timeZone = timeZone }
    val yearFormat = SimpleDateFormat("yyyy", Locale.ENGLISH).apply { this.timeZone = timeZone }
    fun year(activity: WalletActivity) = yearFormat.format(Date(activity.timestampSecs * 1000))

    return transactions.mapIndexed { index, activity ->
        val net = activity.netSats
        val height = activity.confirmationHeight
        HistoryRow(
            id = activity.id,
            day = dayFormat.format(Date(activity.timestampSecs * 1000)),
            year = if (index != 0 && year(transactions[index - 1]) != year(activity)) year(activity) else null,
            sats = "${if (net < 0) "-" else "+"} ${groupThousands(abs(net))} sats",
            fiat = price?.let { "${groupThousands(abs((net / SATS_PER_BITCOIN * it.pricePerBitcoin).roundToLong()))} ${it.symbol}" },
            isLightning = activity.isLightning,
            unconfirmed = !activity.isLightning &&
                (height == null || (currentHeight ?: 0) - height + 1 < 1),
        )
    }
}

/** `addSpaces()`: thousands grouped with a space. */
internal fun groupThousands(value: Long): String =
    value.toString().reversed().chunked(3).joinToString(" ").reversed()

private const val SATS_PER_BITCOIN = 100_000_000.0
