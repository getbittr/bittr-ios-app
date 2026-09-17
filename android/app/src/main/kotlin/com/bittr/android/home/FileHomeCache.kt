package com.bittr.android.home

import com.bittr.android.core.wallet.CachedHome
import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletOverviewSource
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/**
 * [HomeCache] as one JSON file — iOS's `walletcache`, which lives in `UserDefaults` scoped by
 * environment. Here it is one file per backend under `no_backup`, written through a temporary file
 * so a crash mid-write keeps the previous cache.
 *
 * The history rows include Lightning ids (the preimage once a payment settles), as iOS's cached
 * `Transaction`s do; nothing here can spend. An unreadable file reads as no cache.
 */
class FileHomeCache(private val file: File) : HomeCache {

    private val _cached = MutableStateFlow(load())
    override val cached: StateFlow<CachedHome?> = _cached.asStateFlow()

    @Synchronized
    override fun saveOverview(overview: WalletOverview) {
        if (!overview.hasSynced) return
        save(CachedHome.of(overview, _cached.value))
    }

    @Synchronized
    override fun savePrice(price: FiatPrice) {
        val current = _cached.value ?: CachedHome()
        if (current.prices[price.symbol] == price.pricePerBitcoin) return
        save(current.copy(prices = current.prices + (price.symbol to price.pricePerBitcoin)))
    }

    @Synchronized
    override fun saveProfit(profit: CachedProfit) {
        val current = _cached.value ?: CachedHome()
        if (current.profit == profit) return
        save(current.copy(profit = profit))
    }

    @Synchronized
    override fun clear() {
        _cached.value = null
        runCatching {
            file.delete()
            File(file.parentFile, "${file.name}.tmp").delete()
        }
    }

    private fun save(cache: CachedHome) {
        _cached.value = cache
        runCatching { write(cache) }
    }

    private fun load(): CachedHome? = runCatching {
        if (!file.exists()) return null
        decode(Json.parseToJsonElement(file.readText()).jsonObject)
    }.getOrNull()

    private fun write(cache: CachedHome) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(encode(cache).toString())
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
    }

    internal companion object {

        private const val VERSION = 1

        fun encode(cache: CachedHome): JsonObject = buildJsonObject {
            put("version", VERSION)
            put("hasReading", cache.hasReading)
            put("satoshisOnchain", cache.satoshisOnchain)
            put("satoshisLightning", cache.satoshisLightning)
            put("pendingClosureSatoshis", cache.pendingClosureSatoshis)
            put("currentHeight", cache.currentHeight)
            put("channelClosureTxIds", buildJsonArray { cache.channelClosureTxIds.forEach { add(JsonPrimitive(it)) } })
            put("transactions", buildJsonArray { cache.transactions.forEach { add(encodeActivity(it)) } })
            put("prices", JsonObject(cache.prices.mapValues { JsonPrimitive(it.value) }))
            cache.profit?.let { profit ->
                put(
                    "profit",
                    buildJsonObject {
                        put("totalProfit", profit.totalProfit)
                        put("totalInvestment", profit.totalInvestment)
                        put("currentValue", profit.currentValue)
                        put("currencySymbol", profit.currencySymbol)
                    },
                )
            }
        }

        fun decode(root: JsonObject): CachedHome? {
            if (root.int("version") != VERSION) return null
            return CachedHome(
                hasReading = root.boolean("hasReading") ?: false,
                satoshisOnchain = root.long("satoshisOnchain") ?: 0L,
                satoshisLightning = root.long("satoshisLightning") ?: 0L,
                pendingClosureSatoshis = root.long("pendingClosureSatoshis") ?: 0L,
                currentHeight = root.int("currentHeight"),
                channelClosureTxIds = root.array("channelClosureTxIds")
                    ?.mapNotNull { it.jsonPrimitive.contentOrNull }?.toSet().orEmpty(),
                transactions = root.array("transactions")
                    ?.mapNotNull { (it as? JsonObject)?.let(::decodeActivity) }
                    ?.filter { it.timestampSecs != 0L }
                    .orEmpty(),
                prices = (root["prices"] as? JsonObject)
                    ?.mapNotNull { (symbol, value) -> (value as? JsonPrimitive)?.doubleOrNull?.let { symbol to it } }
                    ?.toMap().orEmpty(),
                profit = (root["profit"] as? JsonObject)?.let { profit ->
                    CachedProfit(
                        totalProfit = profit.long("totalProfit") ?: return@let null,
                        totalInvestment = profit.long("totalInvestment") ?: return@let null,
                        currentValue = profit.long("currentValue") ?: return@let null,
                        currencySymbol = profit.string("currencySymbol") ?: return@let null,
                    )
                },
            )
        }

        private fun encodeActivity(activity: WalletActivity): JsonObject = buildJsonObject {
            put("id", activity.id)
            put("receivedSats", activity.receivedSats)
            put("sentSats", activity.sentSats)
            put("feeSats", activity.feeSats)
            put("timestampSecs", activity.timestampSecs)
            put("isLightning", activity.isLightning)
            put("confirmationHeight", activity.confirmationHeight)
            put("paymentHash", activity.paymentHash)
            put("description", activity.description)
            activity.swap?.let { swap ->
                put(
                    "swap",
                    buildJsonObject {
                        put("dateId", swap.dateId)
                        put("boltzId", swap.boltzId)
                        put("status", swap.status.name)
                        put("direction", swap.direction.name)
                        put("isSuggested", swap.isSuggested)
                        put("onchainId", swap.onchainId)
                        put("lightningId", swap.lightningId)
                        put("amountSats", swap.amountSats)
                    },
                )
            }
        }

        private fun decodeActivity(o: JsonObject): WalletActivity? = WalletActivity(
            id = o.string("id") ?: return null,
            receivedSats = o.long("receivedSats") ?: 0L,
            sentSats = o.long("sentSats") ?: 0L,
            feeSats = o.long("feeSats") ?: 0L,
            timestampSecs = o.long("timestampSecs") ?: 0L,
            isLightning = o.boolean("isLightning") ?: false,
            confirmationHeight = o.int("confirmationHeight"),
            paymentHash = o.string("paymentHash"),
            description = o.string("description"),
            swap = (o["swap"] as? JsonObject)?.let { swap ->
                SwapActivity(
                    dateId = swap.string("dateId") ?: return@let null,
                    boltzId = swap.string("boltzId"),
                    status = swap.string("status")?.let { name -> SwapActivityStatus.entries.firstOrNull { it.name == name } }
                        ?: return@let null,
                    direction = swap.string("direction")?.let { name -> SwapActivityDirection.entries.firstOrNull { it.name == name } }
                        ?: return@let null,
                    isSuggested = swap.boolean("isSuggested") ?: false,
                    onchainId = swap.string("onchainId"),
                    lightningId = swap.string("lightningId"),
                    amountSats = swap.long("amountSats"),
                )
            },
        )

        private fun JsonObject.primitive(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeUnless { it is JsonNull }
        private fun JsonObject.string(key: String): String? = primitive(key)?.takeIf { it.isString }?.contentOrNull
        private fun JsonObject.long(key: String): Long? = primitive(key)?.longOrNull
        private fun JsonObject.int(key: String): Int? = primitive(key)?.intOrNull
        private fun JsonObject.boolean(key: String): Boolean? = primitive(key)?.booleanOrNull
        private fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray
    }
}

/**
 * Keeps [HomeCache] up to date for the whole process, not only while Home is on screen: every synced
 * reading is saved (`LoadWalletData.swift` writes the cache from each wallet load), and the cache is
 * cleared as soon as there is no wallet, so a removed wallet's balance and history are never shown
 * for the next one.
 *
 * After a clear, the overview that was on screen at that moment is not written back: the node's last
 * reading can outlive the wallet it came from until the new wallet's first reading replaces it.
 */
class HomeCacheWriter(
    private val cache: HomeCache,
    private val overview: WalletOverviewSource,
    private val walletState: StateFlow<WalletState>,
    private val scope: CoroutineScope,
) {

    @Volatile
    private var staleAfterClear: WalletOverview? = null

    fun start() {
        scope.launch {
            walletState.collect { state ->
                if (state == WalletState.Uninitialized) {
                    staleAfterClear = overview.overview.value
                    cache.clear()
                }
            }
        }
        scope.launch {
            overview.overview.collect { reading ->
                if (!reading.hasSynced || walletState.value == WalletState.Uninitialized) return@collect
                if (reading == staleAfterClear) return@collect
                staleAfterClear = null
                cache.saveOverview(reading)
            }
        }
    }
}
