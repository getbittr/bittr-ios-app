package com.bittr.android.core.swaps

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/** A suggested swap's last observed outcome — iOS's `SwapStatus` in `CacheManager`. */
enum class SuggestedSwapStatus(val raw: String) {
    Pending("pending"),
    Succeeded("succeeded"),
    Failed("failed"),
}

/**
 * Where swaps are kept — iOS's per-swap JSON files in `Documents` plus the four `CacheManager`
 * entries swaps own (`swapids`, `suggestedswaps`, `ongoingswap`, `swapindex`).
 */
interface SwapStore {

    /** Write the swap file, named by `sha256(boltzId)`. A swap without a Boltz id is not written. */
    fun save(swap: Swap)

    /** The swap file for [boltzId]: the hashed name first, then the legacy plaintext one. */
    fun load(boltzId: String): Swap?

    /** The swap a push refers to. The pushed id is already the file stem. */
    fun loadForPushedId(pushedId: String): Swap?

    /** The swap file on disk, for "Download details". */
    fun fileFor(boltzId: String): File?

    /** `incrementSwapIndex()`: the next key index, persisted before it is returned. First is 1. */
    fun nextSwapIndex(): Int

    fun storeSwapId(dateId: String, boltzId: String)

    fun swapIdFor(dateId: String): String?

    fun setSuggestedStatus(dateId: String, status: SuggestedSwapStatus)

    fun suggestedStatus(dateId: String): SuggestedSwapStatus?

    /** `saveLatestSwap` — the swap on screen, so it survives the app closing. */
    fun saveLatest(swap: Swap?)

    fun latest(): Swap?
}

/**
 * [SwapStore] over a directory of files — the swap files beside one `swap-cache.json`.
 *
 * **The swap file keeps the refund key in plain text, deliberately.** iOS says why at
 * `SwapManager.swift:746-753`: it is the user-facing emergency artifact for Boltz's rescue flow
 * and must stay usable without a working app. On Android the directory is app-private storage
 * with backup disabled, which is the counterpart of iOS's "complete until first user
 * authentication" file protection. The latest-swap cache is the same directory, so unlike iOS
 * there is no second, Keychain-stripped copy: both are app-private and neither leaves the device.
 */
class FileSwapStore(private val directory: File) : SwapStore {

    private val lock = Any()
    private val cacheFile get() = File(directory, CACHE_FILE)

    override fun save(swap: Swap) {
        val boltzId = swap.boltzId ?: return
        synchronized(lock) {
            directory.mkdirs()
            atomicWrite(File(directory, "${Swap.hashedId(boltzId)}.json"), SwapJson.encode(swap))
        }
    }

    override fun load(boltzId: String): Swap? =
        read(Swap.hashedId(boltzId)) ?: read(boltzId)

    override fun loadForPushedId(pushedId: String): Swap? = read(pushedId)

    override fun fileFor(boltzId: String): File? =
        listOf(Swap.hashedId(boltzId), boltzId).map { File(directory, "$it.json") }.firstOrNull { it.isFile }

    override fun nextSwapIndex(): Int = synchronized(lock) {
        val cache = readCache()
        val next = ((cache[KEY_INDEX] as? JsonPrimitive)?.intOrNull ?: 0) + 1
        writeCache(JsonObject(cache + (KEY_INDEX to JsonPrimitive(next))))
        next
    }

    override fun storeSwapId(dateId: String, boltzId: String) = updateMap(KEY_SWAP_IDS, dateId, boltzId)

    override fun swapIdFor(dateId: String): String? = mapValue(KEY_SWAP_IDS, dateId)

    override fun setSuggestedStatus(dateId: String, status: SuggestedSwapStatus) = updateMap(KEY_SUGGESTED, dateId, status.raw)

    override fun suggestedStatus(dateId: String): SuggestedSwapStatus? =
        mapValue(KEY_SUGGESTED, dateId)?.let { raw -> SuggestedSwapStatus.entries.firstOrNull { it.raw == raw } }

    override fun saveLatest(swap: Swap?) = synchronized(lock) {
        val cache = readCache().toMutableMap()
        if (swap == null) cache.remove(KEY_LATEST) else cache[KEY_LATEST] = SwapJson.toJson(swap)
        writeCache(JsonObject(cache))
    }

    override fun latest(): Swap? = (readCache()[KEY_LATEST] as? JsonObject)?.let(SwapJson::fromJson)

    private fun read(stem: String): Swap? {
        val file = File(directory, "$stem.json")
        return if (file.isFile) SwapJson.decode(file.readText()) else null
    }

    private fun updateMap(key: String, entry: String, value: String) = synchronized(lock) {
        val cache = readCache()
        val map = (cache[key] as? JsonObject).orEmpty() + (entry to JsonPrimitive(value))
        writeCache(JsonObject(cache + (key to JsonObject(map))))
    }

    private fun mapValue(key: String, entry: String): String? =
        ((readCache()[key] as? JsonObject)?.get(entry) as? JsonPrimitive)?.contentOrNull

    private fun readCache(): Map<String, kotlinx.serialization.json.JsonElement> = synchronized(lock) {
        val file = cacheFile
        if (!file.isFile) return emptyMap()
        runCatching { Json.parseToJsonElement(file.readText()).jsonObject }.getOrElse { buildJsonObject { } }
    }

    private fun writeCache(cache: JsonObject) {
        directory.mkdirs()
        atomicWrite(cacheFile, cache.toString())
    }

    /** Write beside, then rename over — a crash mid-write leaves the previous file, not half of one. */
    private fun atomicWrite(target: File, text: String) {
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(text)
        if (!temporary.renameTo(target)) {
            target.delete()
            check(temporary.renameTo(target)) { "Could not write ${target.name}" }
        }
    }

    private companion object {
        const val CACHE_FILE = "swap-cache.json"
        const val KEY_INDEX = "swapindex"
        const val KEY_SWAP_IDS = "swapids"
        const val KEY_SUGGESTED = "suggestedswaps"
        const val KEY_LATEST = "ongoingswap"
    }
}

@Suppress("unused")
private fun JsonObject.Companion.of(vararg pairs: Pair<String, String>) = buildJsonObject { pairs.forEach { (k, v) -> put(k, v) } }
