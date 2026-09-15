package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

/**
 * The swap stack on the transaction screen — Swap ID and Swap status (`swapStack`), and the second
 * id row a swap has (`bottomIdStack`).
 *
 * @property boltzId what `swapStatusButton` opens; null when the swap id is unknown, in which case
 *   the button does nothing (`openSwapTapped`'s guard).
 * @property bottomId the second id's text: an id, or "Expecting" while that leg has not happened.
 * @property bottomIdCopyable false for "Expecting".
 * @property bottomExplorerId set when the second id is an on-chain transaction.
 */
internal data class SwapDetail(
    val boltzId: String?,
    val swapIdLabel: String,
    val status: String,
    val bottomIdTitle: String? = null,
    val bottomId: String? = null,
    val bottomIdCopyable: Boolean = false,
    val bottomExplorerId: String? = null,
)

/**
 * What the transaction screen shows — `TransactionViewController.setTransactionData()` for
 * on-chain and Lightning transactions and swaps. Bittr purchases have their own section on iOS
 * and are not ported here.
 *
 * @property idTitle "ID", or "Onchain ID" / "Lightning ID" for a swap's first id.
 * @property fees only for a transaction that took money out (`received - sent - fee < 0`).
 * @property confirmations only on-chain, and not for a swap; "Unconfirmed" until it has one.
 * @property explorerId set when the (first) id is an on-chain transaction.
 * @property description `descriptionText()`: the stored invoice description, else the
 *   channel-closure sentence; never for a swap.
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
    val idTitle: String = HomeStrings.ID,
    val swap: SwapDetail? = null,
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
    val swap = activity.swap
    val fullSwap = swap?.takeIf { !it.isSuggested }

    var idTitle = HomeStrings.ID
    var id = activity.id
    var explorerId = if (activity.isLightning) null else activity.id
    var swapDetail: SwapDetail? = null

    if (swap != null) {
        swapDetail = SwapDetail(
            boltzId = swap.boltzId,
            swapIdLabel = swap.boltzId ?: HomeStrings.UNAVAILABLE,
            status = when (swap.status) {
                SwapActivityStatus.Succeeded -> HomeStrings.SWAP_SUCCEEDED
                SwapActivityStatus.Pending -> HomeStrings.SWAP_PENDING
                SwapActivityStatus.Failed -> HomeStrings.SWAP_FAILED
            },
        )
    }
    if (fullSwap != null && swapDetail != null) {
        // The `bottomIdStack` table, per direction and status.
        if (fullSwap.direction == SwapActivityDirection.OnchainToLightning) {
            idTitle = HomeStrings.ONCHAIN_ID
            id = fullSwap.onchainId ?: activity.id
            explorerId = fullSwap.onchainId
            swapDetail = when (fullSwap.status) {
                SwapActivityStatus.Succeeded -> swapDetail.copy(
                    bottomIdTitle = HomeStrings.LIGHTNING_ID,
                    bottomId = fullSwap.lightningId,
                    bottomIdCopyable = fullSwap.lightningId != null,
                )
                SwapActivityStatus.Pending -> swapDetail.copy(bottomIdTitle = HomeStrings.LIGHTNING_ID, bottomId = HomeStrings.EXPECTING)
                SwapActivityStatus.Failed -> swapDetail.copy(
                    bottomIdTitle = HomeStrings.REFUND_ID,
                    bottomId = fullSwap.lightningId,
                    bottomIdCopyable = fullSwap.lightningId != null,
                    bottomExplorerId = fullSwap.lightningId,
                )
            }
        } else {
            idTitle = HomeStrings.LIGHTNING_ID
            id = fullSwap.lightningId ?: activity.id
            explorerId = null
            swapDetail = when (fullSwap.status) {
                SwapActivityStatus.Succeeded -> swapDetail.copy(
                    bottomIdTitle = HomeStrings.ONCHAIN_ID,
                    bottomId = fullSwap.onchainId,
                    bottomIdCopyable = fullSwap.onchainId != null,
                    bottomExplorerId = fullSwap.onchainId,
                )
                SwapActivityStatus.Pending -> swapDetail.copy(bottomIdTitle = HomeStrings.ONCHAIN_ID, bottomId = HomeStrings.EXPECTING)
                SwapActivityStatus.Failed -> swapDetail
            }
        }
    }

    return TransactionDetail(
        id = id,
        date = format.format(Date(activity.timestampSecs * 1000)).removePrefix("0"),
        amount = "${if (gross < 0) "-" else "+"} ${groupThousands(abs(gross))} sats",
        isLightning = activity.isLightning,
        fees = when {
            fullSwap != null && activity.netSats < 0 -> "${groupThousands(abs(activity.netSats))} sats"
            activity.netSats < 0 -> "${groupThousands(activity.feeSats)} sats"
            else -> null
        },
        confirmations = when {
            activity.isLightning || fullSwap != null -> null
            height == null || (currentHeight ?: 0) - height + 1 < 1 -> HomeStrings.UNCONFIRMED
            else -> groupThousands(((currentHeight ?: 0) - height + 1).toLong())
        },
        explorerId = explorerId,
        currentValue = price?.let { "${twoDecimals(abs(activity.netSats) / SATS_PER_BITCOIN * it.pricePerBitcoin)} ${it.symbol}" },
        description = when {
            swap != null -> null
            !activity.description.isNullOrBlank() -> activity.description
            // `isChannelClosure`: the payout's txid is one the closure scan recorded.
            !activity.isLightning && activity.id in closureTxIds -> HomeStrings.CHANNEL_CLOSURE_TRANSACTION
            else -> null
        },
        note = note?.takeIf { it.isNotBlank() },
        idTitle = idTitle,
        swap = swapDetail,
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
