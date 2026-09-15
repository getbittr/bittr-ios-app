package com.bittr.android.history

import android.content.Context
import com.bittr.android.core.swaps.FileSwapStore
import com.bittr.android.core.swaps.SuggestedSwapStatus
import com.bittr.android.core.swaps.SwapStore
import com.bittr.android.core.wallet.SwapActivityStatus
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
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
    ): WalletOverviewSource = MatchedWalletOverviewSource(
        raw = composition.overview,
        descriptions = descriptions,
        swaps = swaps,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    )
}

/**
 * The node's overview with iOS's history treatment applied: each row's stored description, then
 * `performSwapMatching()`. Recomputed whenever the node publishes or a description is stored —
 * a swap stores its description right after its id, so a new swap is matched as soon as it lands.
 */
class MatchedWalletOverviewSource(
    raw: WalletOverviewSource,
    descriptions: TransactionDescriptionStore,
    private val swaps: SwapStore,
    scope: CoroutineScope,
) : WalletOverviewSource {

    override val overview: StateFlow<WalletOverview> =
        combine(raw.overview, descriptions.descriptions) { wallet, stored -> matched(wallet, stored) }
            .stateIn(scope, SharingStarted.Eagerly, raw.overview.value)

    private fun matched(wallet: WalletOverview, stored: Map<String, String>): WalletOverview {
        val described = SwapHistory.withDescriptions(wallet.transactions, stored)
        val rows = SwapHistory.matched(
            transactions = described,
            swapIdFor = swaps::swapIdFor,
            // `loadSwapDetailsFromFile(swapID:)`: what the transaction screen shows as the swapped amount.
            swapAmountFor = { dateId -> swaps.swapIdFor(dateId)?.let(swaps::load)?.satoshisAmount?.takeIf { it > 0 } },
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
