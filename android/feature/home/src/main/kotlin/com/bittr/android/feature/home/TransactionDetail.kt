package com.bittr.android.feature.home

import com.bittr.android.core.wallet.BittrPurchase
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
import kotlin.math.floor

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
 * A bittr purchase's own section (`bittrFeesStack`) — what bittr received, its fees, the purchase
 * value, the exchange rate and today's value and profit. Fiat figures are in the purchase's currency.
 *
 * @property surcharge null when there was none, which hides the row (`surchargeStack`).
 * @property transferFeeExplanation what tapping the transfer fee says: `transferfee1` for the
 *   payout that funded the lightning connection, `transferfee2` for later Lightning payouts,
 *   `transferfee3` on-chain.
 * @property isLoss colours the profit (`losstext` / `profittext`).
 */
internal data class BittrDetail(
    val receivedAtBittr: String,
    val surcharge: String?,
    val bittrFee: String,
    val transferFee: String,
    val transferFeeExplanation: String,
    val purchaseValue: String,
    val currentValue: String,
    val exchangeRate: String,
    val profit: String,
    val isLoss: Boolean,
)

/**
 * What the transaction screen shows — `TransactionViewController.setTransactionData()` for
 * on-chain and Lightning transactions, swaps and bittr purchases.
 *
 * @property amount iOS's `labelAmount`: signed net for a payment; for a swap, what was swapped —
 *   the amount received once complete, the swap file's amount while pending, "- amount" for a
 *   Swap & Pay leg.
 * @property type iOS's `labelType`: "Instant" / "Regular", or the swap's direction.
 * @property typeBolt the bolt next to "Instant" (`typeBoltImage`); never for a swap.
 * @property idTitle "ID", or "Onchain ID" / "Lightning ID" for a swap's first id.
 * @property fees for a payment that took money out (`received - sent - fee < 0`); for a swap, what
 *   it cost on top of the swapped amount.
 * @property confirmations only on-chain, and not for a swap; "Unconfirmed" until it has one.
 * @property explorerId set when the (first) id is an on-chain transaction.
 * @property currentValue `valueStack`; null for a bittr purchase, whose section carries its own.
 * @property description `descriptionText()`: the stored invoice description, else the
 *   channel-closure sentence; never for a swap, never on the payout summary.
 * @property note the user's note, or null for "Add a note".
 * @property bittr the purchase section, when bittr confirmed this transaction.
 * @property confetti the bittr payout summary (`showConfetti`): the piggy-bank header and the
 *   reminder show, and the type row, the ids, the description and the note are hidden.
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
    val type: String = if (isLightning) HomeStrings.INSTANT else HomeStrings.REGULAR,
    val typeBolt: Boolean = isLightning,
    val bittr: BittrDetail? = null,
    val confetti: Boolean = false,
)

/**
 * @param purchase bittr's record of this transaction, when it is a bittr purchase or payout.
 * @param confetti opened as the bittr payout summary.
 * @param isFunding the purchase that funded the lightning connection (`isFundingTransaction`).
 * @param purchasePrice one bitcoin in the purchase's currency, for its current value and profit.
 */
internal fun transactionDetail(
    activity: WalletActivity,
    price: FiatPrice?,
    currentHeight: Int?,
    timeZone: TimeZone = TimeZone.getDefault(),
    closureTxIds: Set<String> = emptySet(),
    note: String? = null,
    purchase: BittrPurchase? = null,
    confetti: Boolean = false,
    isFunding: Boolean = false,
    purchasePrice: Double? = null,
): TransactionDetail {
    val format = SimpleDateFormat("dd MMM yyyy HH:mm", Locale.ENGLISH).apply { this.timeZone = timeZone }
    val gross = activity.receivedSats - activity.sentSats
    val height = activity.confirmationHeight
    val swap = activity.swap
    val fullSwap = swap?.takeIf { !it.isSuggested }
    val suggestedSwap = swap?.takeIf { it.isSuggested }

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

    if (suggestedSwap != null && swapDetail != null) {
        // A Swap & Pay leg: the payment on top, the swap's other side from its file below.
        id = activity.id
        if (suggestedSwap.direction == SwapActivityDirection.OnchainToLightning) {
            idTitle = HomeStrings.ONCHAIN_ID
            explorerId = activity.id
            val hash = suggestedSwap.file?.paidInvoiceHash
            swapDetail = swapDetail.copy(
                bottomIdTitle = HomeStrings.LIGHTNING_ID,
                bottomId = hash ?: HomeStrings.UNAVAILABLE,
                bottomIdCopyable = hash != null,
            )
        } else {
            idTitle = HomeStrings.LIGHTNING_ID
            explorerId = null
            val txId = suggestedSwap.file?.sentOnchainTxId
            swapDetail = swapDetail.copy(
                bottomIdTitle = HomeStrings.ONCHAIN_ID,
                bottomId = txId ?: HomeStrings.UNAVAILABLE,
                bottomIdCopyable = txId != null,
                bottomExplorerId = txId,
            )
        }
    }

    // `labelAmount`.
    val amount = when {
        fullSwap != null -> when (fullSwap.status) {
            SwapActivityStatus.Succeeded -> sats(activity.receivedSats)
            SwapActivityStatus.Pending -> sats(fullSwap.amountSats ?: gross)
            SwapActivityStatus.Failed ->
                // A failed swap is an on-chain → Lightning one refunded: nothing was swapped.
                if (fullSwap.direction == SwapActivityDirection.OnchainToLightning) "0 sats" else sats(gross)
        }
        // The paid invoice amount, not the whole on-chain outflow with the swap's cut and fee in it.
        suggestedSwap != null -> "- ${sats(suggestedSwap.amountSats ?: (activity.sentSats - activity.receivedSats))}"
        else -> "${if (gross < 0) "-" else "+"} ${sats(gross)}"
    }

    // `labelFees`.
    val fees = when {
        fullSwap != null -> when {
            // Completed or failed: Boltz's spread plus the network fee the user paid.
            fullSwap.status != SwapActivityStatus.Pending -> sats(activity.sentSats - activity.receivedSats + activity.feeSats)
            else -> fullSwap.amountSats?.let { sats(activity.sentSats - activity.receivedSats - it) } ?: "0 sats"
        }
        suggestedSwap != null -> suggestedSwap.amountSats
            ?.let { sats(activity.sentSats - activity.receivedSats + activity.feeSats - it) }
            ?: sats(activity.feeSats)
        activity.netSats < 0 -> sats(activity.feeSats)
        else -> null
    }

    val chosenValue = price?.let { "${twoDecimals(abs(activity.netSats) / SATS_PER_BITCOIN * it.pricePerBitcoin)} ${it.symbol}" }

    return TransactionDetail(
        id = id,
        date = format.format(Date(activity.timestampSecs * 1000)).removePrefix("0"),
        amount = amount,
        isLightning = activity.isLightning,
        fees = fees,
        confirmations = when {
            activity.isLightning || fullSwap != null -> null
            height == null || (currentHeight ?: 0) - height + 1 < 1 -> HomeStrings.UNCONFIRMED
            else -> groupThousands(((currentHeight ?: 0) - height + 1).toLong())
        },
        explorerId = explorerId,
        // `valueStack` is hidden for a bittr purchase: its section shows the value instead.
        currentValue = if (purchase != null) null else chosenValue,
        description = when {
            swap != null || confetti -> null
            !activity.description.isNullOrBlank() -> activity.description
            // `isChannelClosure`: the payout's txid is one the closure scan recorded.
            !activity.isLightning && activity.id in closureTxIds -> HomeStrings.CHANNEL_CLOSURE_TRANSACTION
            else -> null
        },
        note = note?.takeIf { it.isNotBlank() && !confetti },
        idTitle = idTitle,
        swap = swapDetail,
        type = when {
            fullSwap == null -> if (activity.isLightning) HomeStrings.INSTANT else HomeStrings.REGULAR
            fullSwap.direction == SwapActivityDirection.OnchainToLightning -> HomeStrings.ONCHAIN_TO_LIGHTNING
            else -> HomeStrings.LIGHTNING_TO_ONCHAIN
        },
        typeBolt = fullSwap == null && activity.isLightning,
        bittr = purchase?.let { bittrDetail(activity, it, chosenValue, isFunding, purchasePrice) },
        confetti = confetti,
    )
}

/**
 * The `isBittr` branch of `setTransactionData()`.
 *
 * iOS writes the current value in the chosen currency and then, when it can convert, in the
 * purchase's currency; the profit is that value minus the purchase value. A purchase bittr has not
 * priced yet (net amount 0) shows its current value as the purchase value and no profit. When the
 * transfer fee is 0, iOS recomputes the purchase value as gross − surcharge − bittr fee.
 */
private fun bittrDetail(
    activity: WalletActivity,
    purchase: BittrPurchase,
    chosenValue: String?,
    isFunding: Boolean,
    purchasePrice: Double?,
): BittrDetail {
    val symbol = if (purchase.currency == "EUR") "€" else "CHF"
    val bitcoin = activity.netSats / SATS_PER_BITCOIN
    val valueInPurchaseCurrency = purchasePrice?.let { bitcoin * it }
    val currentValue = valueInPurchaseCurrency?.let { "${twoDecimals(abs(it))} $symbol" } ?: chosenValue ?: "0.00 $symbol"
    val gross = purchase.fiatGrossAmount ?: 0.0
    val surcharge = purchase.surcharge ?: 0.0
    val bittrFee = purchase.bittrFee ?: 0.0
    val transferFeeSats = purchase.transferFeeSats ?: 0L
    val net = purchase.fiatNetAmount ?: 0.0

    val purchaseValue: String
    val profit: String
    val isLoss: Boolean
    if (net == 0.0) {
        purchaseValue = currentValue
        profit = "0.00 $symbol"
        isLoss = false
    } else {
        val fixedNet = if (transferFeeSats == 0L) gross - surcharge - bittrFee else net
        purchaseValue = "${twoDecimals(fixedNet)} $symbol"
        val profitValue = valueInPurchaseCurrency?.minus(fixedNet)
        profit = if (profitValue == null) "0.00 $symbol" else "${if (profitValue < 0) "- " else ""}${twoDecimals(abs(profitValue))} $symbol"
        isLoss = (profitValue ?: 0.0) < 0
    }

    return BittrDetail(
        receivedAtBittr = "${twoDecimals(gross)} $symbol",
        surcharge = if (surcharge == 0.0) null else "${twoDecimals(surcharge)} $symbol",
        bittrFee = "${twoDecimals(bittrFee)} $symbol",
        transferFee = "${groupThousands(transferFeeSats)} sats",
        transferFeeExplanation = when {
            isFunding -> HomeStrings.TRANSFER_FEE_1
            activity.isLightning -> HomeStrings.TRANSFER_FEE_2
            else -> HomeStrings.TRANSFER_FEE_3
        },
        purchaseValue = purchaseValue,
        currentValue = currentValue,
        exchangeRate = "${purchase.historicalExchangeRate?.let(::plainNumber) ?: "0"} $symbol/btc",
        profit = profit,
        isLoss = isLoss,
    )
}

/**
 * A bittr purchase that is not in the wallet's history — the transaction that funded the lightning
 * connection. iOS builds a `Transaction` for it from bittr's record (`createTransaction(isFundingTransaction: true)`).
 */
internal fun purchaseActivity(purchase: BittrPurchase, nowSecs: Long = System.currentTimeMillis() / 1000): WalletActivity =
    WalletActivity(
        id = purchase.txId,
        receivedSats = purchase.bitcoinAmountSats ?: 0L,
        sentSats = 0L,
        feeSats = 0L,
        timestampSecs = purchase.timestampSecs ?: nowSecs,
        isLightning = true,
        confirmationHeight = null,
    )

/** A satoshi figure without its sign, as iOS strips the "-" from every one of these labels. */
private fun sats(value: Long): String = "${groupThousands(abs(value))} sats"

/** A fiat figure with its whole part grouped and two decimals, e.g. "1 234.50". */
internal fun twoDecimals(value: Double): String {
    val rounded = BigDecimal(value).setScale(2, RoundingMode.HALF_UP)
    val whole = rounded.toBigInteger().toLong()
    val cents = rounded.remainder(BigDecimal.ONE).movePointRight(2).toInt()
    return "${groupThousands(whole)}.${cents.toString().padStart(2, '0')}"
}

/** A rate as iOS's `toString().addSpaces()` shows it: grouped, with decimals only when it has them. */
private fun plainNumber(value: Double): String =
    if (value == floor(value)) groupThousands(value.toLong()) else twoDecimals(value)

private const val SATS_PER_BITCOIN = 100_000_000.0
