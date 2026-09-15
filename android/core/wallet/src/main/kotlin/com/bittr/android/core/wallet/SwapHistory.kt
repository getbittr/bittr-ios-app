package com.bittr.android.core.wallet

enum class SwapActivityStatus { Pending, Succeeded, Failed }

enum class SwapActivityDirection { OnchainToLightning, LightningToOnchain }

/**
 * A swap as history shows it — iOS `Transaction.isSwap` / `isSuggestedSwap` and the fields
 * `performSwapMatching` fills.
 *
 * @property dateId the swap's `dateID` ("Swap onchain to lightning 2026…"), which both legs
 *   carry as their description.
 * @property boltzId `CacheManager.getSwapID(dateID:)`, or null when unknown ("Unavailable").
 * @property isSuggested a Swap & Pay leg: it stays the payment it paid, with the swap's id and
 *   status shown on the transaction screen.
 */
data class SwapActivity(
    val dateId: String,
    val boltzId: String?,
    val status: SwapActivityStatus,
    val direction: SwapActivityDirection,
    val isSuggested: Boolean = false,
    val onchainId: String? = null,
    val lightningId: String? = null,
)

/** Where transaction descriptions are kept — iOS `CacheManager.storeInvoiceDescription`. */
interface TransactionDescriptionStore {

    /** Every description, keyed by payment hash (Lightning) or txid (on-chain). */
    val descriptions: kotlinx.coroutines.flow.StateFlow<Map<String, String>>

    fun store(key: String, description: String)
}

/**
 * `SwapMatching.swift` and the description lookup `Transaction.swift` does, as pure functions
 * over the history.
 */
object SwapHistory {

    const val ONCHAIN_TO_LIGHTNING = "Swap onchain to lightning "
    const val LIGHTNING_TO_ONCHAIN = "Swap lightning to onchain "

    /** `getInvoiceDescription(preimages:)`: by the row's id first, then its payment hash. */
    fun withDescriptions(transactions: List<WalletActivity>, descriptions: Map<String, String>): List<WalletActivity> {
        if (descriptions.isEmpty()) return transactions
        return transactions.map { activity ->
            val found = descriptions[activity.id] ?: activity.paymentHash?.let { descriptions[it] }
            if (found == null || found == activity.description) activity else activity.copy(description = found)
        }
    }

    /**
     * `performSwapMatching()`: legs sharing a "Swap …" description become one row; a lone leg
     * becomes a pending swap row, unless it is a Swap & Pay leg, which keeps its row and gains the
     * swap's status. Newest first, as the history is.
     *
     * @param swapIdFor `CacheManager.getSwapID(dateID:)`.
     * @param suggestedStatus `CacheManager.getSuggestedSwapStatus(dateID:)`.
     */
    fun matched(
        transactions: List<WalletActivity>,
        swapIdFor: (String) -> String?,
        suggestedStatus: (String) -> SwapActivityStatus?,
    ): List<WalletActivity> {
        val groups = transactions
            .filter { it.swap == null && it.description?.contains("Swap") == true }
            .groupBy { it.description!! }
        if (groups.isEmpty()) return transactions

        val current = transactions.toMutableList()
        for ((dateId, legs) in groups) {
            when (legs.size) {
                2 -> {
                    val combined = completed(dateId, legs[0], legs[1], swapIdFor(dateId))
                    current.removeAll { it === legs[0] || it === legs[1] }
                    current += combined
                }
                1 -> {
                    val index = current.indexOfFirst { it === legs[0] }
                    current[index] = pending(dateId, legs[0], swapIdFor(dateId), suggestedStatus(dateId))
                }
            }
        }
        return current.sortedByDescending { it.timestampSecs }
    }

    private fun completed(dateId: String, first: WalletActivity, second: WalletActivity, boltzId: String?): WalletActivity {
        val direction = direction(dateId)
        var sent = first.receivedSats + second.receivedSats - first.sentSats - second.sentSats
        var received = 0L
        var timestamp: Long? = null
        var height: Int? = null
        var onchainId: String? = null
        var lightningId: String? = null

        for (leg in listOf(first, second)) {
            if (leg.isLightning) {
                lightningId = leg.id
                if (direction == SwapActivityDirection.OnchainToLightning) {
                    timestamp = leg.timestampSecs
                    received = leg.receivedSats
                } else {
                    sent = leg.sentSats
                }
            } else {
                onchainId = leg.id
                height = leg.confirmationHeight
                if (direction == SwapActivityDirection.LightningToOnchain) {
                    timestamp = leg.timestampSecs
                    received = leg.receivedSats - leg.sentSats
                } else {
                    sent = leg.sentSats - leg.receivedSats
                }
            }
        }

        var status = SwapActivityStatus.Succeeded
        if (!first.isLightning && !second.isLightning) {
            // Both legs on-chain: a failed swap and its refund.
            timestamp = first.timestampSecs
            sent = first.sentSats + second.sentSats
            received = first.receivedSats + second.receivedSats
            status = SwapActivityStatus.Failed
            if (first.receivedSats - first.sentSats < second.receivedSats - second.sentSats) {
                onchainId = first.id
                lightningId = second.id
            } else {
                onchainId = second.id
                lightningId = first.id
            }
        }

        return WalletActivity(
            id = stripped(dateId),
            receivedSats = received,
            sentSats = sent,
            feeSats = first.feeSats + second.feeSats,
            timestampSecs = timestamp ?: maxOf(first.timestampSecs, second.timestampSecs),
            isLightning = dateId.contains("lightning to onchain"),
            confirmationHeight = height,
            description = dateId,
            swap = SwapActivity(dateId, boltzId, status, direction, onchainId = onchainId, lightningId = lightningId),
        )
    }

    private fun pending(dateId: String, leg: WalletActivity, boltzId: String?, suggested: SwapActivityStatus?): WalletActivity {
        val direction = direction(dateId)
        val onchainId = leg.id.takeIf { !leg.isLightning }
        val lightningId = leg.id.takeIf { leg.isLightning }
        if (suggested != null) {
            return leg.copy(swap = SwapActivity(dateId, boltzId, suggested, direction, isSuggested = true, onchainId = onchainId, lightningId = lightningId))
        }
        return WalletActivity(
            id = stripped(dateId),
            receivedSats = leg.receivedSats,
            sentSats = leg.sentSats,
            feeSats = 0L,
            timestampSecs = leg.timestampSecs,
            isLightning = leg.isLightning,
            confirmationHeight = if (leg.isLightning) null else leg.confirmationHeight,
            description = dateId,
            swap = SwapActivity(dateId, boltzId, SwapActivityStatus.Pending, direction, onchainId = onchainId, lightningId = lightningId),
        )
    }

    private fun direction(dateId: String): SwapActivityDirection =
        if (dateId.contains("onchain to lightning")) SwapActivityDirection.OnchainToLightning else SwapActivityDirection.LightningToOnchain

    private fun stripped(dateId: String): String =
        dateId.replace(LIGHTNING_TO_ONCHAIN, "").replace(ONCHAIN_TO_LIGHTNING, "")
}
