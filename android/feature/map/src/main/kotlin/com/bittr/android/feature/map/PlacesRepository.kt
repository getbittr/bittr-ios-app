package com.bittr.android.feature.map

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The BTCMap places, cached on disk and refreshed incrementally.
 *
 * Ported from `resyncBTCPlaces` / `BitcoinPlacesCache`
 * (`ios/bittr/Map/BitcoinPlace.swift`). The sequence matters and is kept:
 *
 * 1. Read the cache and show it immediately — an opened map is never blank on a
 *    second visit.
 * 2. Sync. Nothing cached means a full download and no watermark; anything cached
 *    means an incremental one, which is the only case that asks for tombstones.
 * 3. Merge, save, and only then advance the watermark.
 *
 * Step 3's order is the part that is easy to get wrong: a watermark written before a
 * failed save silently skips every place that changed between the two syncs, and
 * nothing surfaces it — the map just stops learning about some shops.
 */
internal interface PlacesRepository {

    /** The cached set, without touching the network. */
    suspend fun cached(): List<BitcoinPlace>

    /** Syncs and returns the merged set. Throws if the request fails. */
    suspend fun sync(): List<BitcoinPlace>
}

internal class HttpPlacesRepository(context: Context) : PlacesRepository {

    private val cacheFile = File(context.applicationContext.cacheDir, CACHE_FILE_NAME)
    private val preferences =
        context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override suspend fun cached(): List<BitcoinPlace> = withContext(Dispatchers.IO) {
        runCatching { parsePlaces(cacheFile.readText()) }.getOrDefault(emptyList())
    }

    override suspend fun sync(): List<BitcoinPlace> = withContext(Dispatchers.IO) {
        val cached = cached()

        // No cache means a full download, so there is nothing to sync *from* even if
        // a watermark survived an earlier install of the cache file.
        val updatedSince = if (cached.isEmpty()) null else preferences.getString(KEY_WATERMARK, null)
        val response = get(bitcoinMapUrl(updatedSince = updatedSince, includeDeleted = updatedSince != null))
        val synced = parsePlaces(response)
        val merged = applySyncedPlaces(synced = synced, cached = cached)

        val saved = runCatching { cacheFile.writeText(encodePlaces(merged)) }.isSuccess
        if (saved) {
            newestUpdatedAt(synced)?.let { preferences.edit().putString(KEY_WATERMARK, it).apply() }
        }
        merged
    }

    private fun get(url: String): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) error("BTCMap returned $code")
            return connection.inputStream.use { it.reader().readText() }
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val CACHE_FILE_NAME = "btc_places_cache.json"
        const val PREFERENCES_NAME = "btc_map"

        /** iOS's `btcMapLastUpdatedAt` UserDefaults key, under the same name. */
        const val KEY_WATERMARK = "btcMapLastUpdatedAt"

        /**
         * A first-ever sync downloads the full dataset, which is why the flow allows
         * two minutes for the spinner. The socket timeouts are per-read, not for the
         * whole transfer, so this does not cap that.
         */
        const val TIMEOUT_MS = 30_000
    }
}
