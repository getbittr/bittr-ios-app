package com.bittr.android.history

import android.content.Context
import com.bittr.android.core.swaps.FileSwapStore
import com.bittr.android.core.swaps.SuggestedSwapStatus
import com.bittr.android.core.swaps.SwapStore
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.wallet.BittrPurchaseSource
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.toActivity
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.SwapFileIds
import com.bittr.android.core.wallet.ldk.adapter.Bolt11Decoder
import com.bittr.android.core.wallet.SwapHistory
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.di.WalletComposition
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

@Module
@InstallIn(SingletonComponent::class)
object HistoryModule {

    /** iOS keeps `invoicedescriptions` in `UserDefaults`; like the notes, this is not key material. */
    @Provides
    @Singleton
    fun provideTransactionDescriptionStore(@ApplicationContext context: Context): TransactionDescriptionStore =
        FileTransactionDescriptionStore(File(context.filesDir, "transaction_descriptions.json"))

    /**
     * One swap store for the process, shared by the coordinator and the history. App-private, and
     * backup is off app-wide: the swap files hold refund keys in the clear, as iOS's do, because
     * they are the user's rescue artifact for Boltz.
     */
    @Provides
    @Singleton
    fun provideSwapStore(@ApplicationContext context: Context): SwapStore = FileSwapStore(File(context.filesDir, "swaps"))

    /** What Home and the transaction screen read — the wallet's overview with descriptions and swaps matched. */
    @Provides
    @Singleton
    fun provideWalletOverviewSource(
        composition: WalletComposition,
        descriptions: TransactionDescriptionStore,
        swaps: SwapStore,
        customers: BittrCustomerStore,
        purchases: BittrPurchaseSource,
    ): WalletOverviewSource = MatchedWalletOverviewSource(
        raw = composition.overview,
        descriptions = descriptions,
        swaps = swaps,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        fundingRows = combine(customers.fundingTransactions, purchases.purchases) { ids, bought ->
            // iOS drops cached rows without a date (`timestamp != 0`).
            ids.mapNotNull { id -> bought[id]?.let { purchase -> purchase.timestampSecs?.let(purchase::toActivity) } }
        },
    )
}

/**
 * The node's overview with iOS's history treatment applied: each row's stored description, then
 * `performSwapMatching()`, then the cached bittr rows the node has no payment for. Recomputed
 * whenever the node publishes, a description is stored or a row is cached — a swap stores its
 * description right after its id, so a new swap is matched as soon as it lands, and a confirmed
 * funding purchase shows on Home straight away, as `addLightningTransaction` adds it on iOS.
 *
 * @param fundingRows `CacheManager.getLightningTransactions()` as far as Android caches them: the
 *   purchases that funded a channel bittr opened. Not payments of the node, so nothing else lists them.
 */
class MatchedWalletOverviewSource(
    raw: WalletOverviewSource,
    descriptions: TransactionDescriptionStore,
    private val swaps: SwapStore,
    scope: CoroutineScope,
    fundingRows: Flow<List<WalletActivity>> = flowOf(emptyList()),
) : WalletOverviewSource {

    override val overview: StateFlow<WalletOverview> =
        combine(raw.overview, descriptions.descriptions, fundingRows) { wallet, stored, funding ->
            withCachedRows(matched(wallet, stored), funding)
        }.stateIn(scope, SharingStarted.Eagerly, raw.overview.value)

    /** The cached rows the history doesn't already have, in date order with the rest (newest first). */
    private fun withCachedRows(wallet: WalletOverview, cached: List<WalletActivity>): WalletOverview {
        val ids = wallet.transactions.mapTo(HashSet()) { it.id }
        val missing = cached.filter { it.id !in ids }
        if (missing.isEmpty()) return wallet
        return wallet.copy(transactions = (wallet.transactions + missing).sortedByDescending { it.timestampSecs })
    }

    private fun matched(wallet: WalletOverview, stored: Map<String, String>): WalletOverview {
        val described = SwapHistory.withDescriptions(wallet.transactions, stored)
        val rows = SwapHistory.matched(
            transactions = described,
            swapIdFor = swaps::swapIdFor,
            // `loadSwapDetailsFromFile(swapID:)`: what the transaction screen shows as the swapped amount.
            swapAmountFor = { dateId -> swaps.swapIdFor(dateId)?.let(swaps::load)?.satoshisAmount?.takeIf { it > 0 } },
            swapFileIdsFor = { dateId ->
                swaps.swapIdFor(dateId)?.let(swaps::load)?.let { swap ->
                    SwapFileIds(
                        paidInvoiceHash = swap.createdInvoice?.let { Bolt11Decoder.decode(it)?.paymentHashHex },
                        sentOnchainTxId = swap.sentOnchainTransactionId,
                    )
                }
            },
        ) { dateId ->
            when (swaps.suggestedStatus(dateId)) {
                SuggestedSwapStatus.Pending -> SwapActivityStatus.Pending
                SuggestedSwapStatus.Succeeded -> SwapActivityStatus.Succeeded
                SuggestedSwapStatus.Failed -> SwapActivityStatus.Failed
                null -> null
            }
        }
        return if (rows === wallet.transactions) wallet else wallet.copy(transactions = rows)
    }
}

/**
 * [TransactionDescriptionStore] as one JSON object in a file, written through a temporary file
 * so a crash mid-write keeps the previous descriptions.
 */
class FileTransactionDescriptionStore(private val file: File) : TransactionDescriptionStore {

    private val _descriptions = MutableStateFlow(load())
    override val descriptions: StateFlow<Map<String, String>> = _descriptions.asStateFlow()

    @Synchronized
    override fun store(key: String, description: String) {
        if (key.isBlank() || description.isBlank()) return
        _descriptions.update { it + (key to description) }
        runCatching { write(_descriptions.value) }
    }

    private fun load(): Map<String, String> = runCatching {
        if (!file.exists()) return emptyMap()
        Json.parseToJsonElement(file.readText()).jsonObject
            .mapNotNull { (key, value) -> value.jsonPrimitive.contentOrNull?.let { key to it } }
            .toMap()
    }.getOrDefault(emptyMap())

    private fun write(descriptions: Map<String, String>) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(JsonObject(descriptions.mapValues { JsonPrimitive(it.value) }).toString())
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
    }
}
