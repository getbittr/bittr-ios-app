package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.onchain.BdkScanRecord

/**
 * [BdkScanRecord] over the wallet cache — iOS's `CacheKeys.lastBdkFullScan` and
 * `CacheKeys.bdkRebuildRequested` in `CacheStore`.
 *
 * A write that cannot be made durable is reported to [onFailure] and otherwise
 * ignored, as iOS's `CacheStore.set` does. A lost scan record costs a scan, and a
 * lost rebuild request is one the user can make again.
 *
 * @param databaseCreatedAt when the BDK database was created, in whole seconds
 *   since the epoch, or null when there is none. `BdkStore.creationEpochSeconds`.
 * @param now the current time in whole seconds since the epoch.
 */
class CachedBdkScanRecord(
    private val cache: WalletCache,
    private val databaseCreatedAt: () -> Long?,
    private val now: () -> Long = { System.currentTimeMillis() / 1000 },
    private val onFailure: (Throwable) -> Unit = {},
) : BdkScanRecord {

    override val hasStoredFullScan: Boolean
        get() {
            // Check when the BDK wallet was last scanned.
            val scannedAt = cache.strings(KEY_LAST_FULL_SCAN).firstOrNull()?.toLongOrNull() ?: return false

            // Make sure the most recent scan is not older than this database.
            val databaseCreated = databaseCreatedAt() ?: return false
            return databaseCreated <= scannedAt
        }

    override fun storeFullScanCompletion() = write { cache.put(KEY_LAST_FULL_SCAN, listOf(now().toString())) }

    override fun clearFullScanCompletion() = write { cache.remove(KEY_LAST_FULL_SCAN) }

    override val rebuildRequested: Boolean
        get() = cache.strings(KEY_REBUILD_REQUESTED).firstOrNull() == true.toString()

    override fun requestRebuild() {
        write { cache.put(KEY_REBUILD_REQUESTED, listOf(true.toString())) }
        clearFullScanCompletion()
    }

    override fun clearRebuildRequest() = write { cache.remove(KEY_REBUILD_REQUESTED) }

    private inline fun write(block: () -> Unit) {
        try {
            block()
        } catch (failure: java.io.IOException) {
            onFailure(failure)
        }
    }

    companion object {
        /** `CacheKeys.lastBdkFullScan`. */
        const val KEY_LAST_FULL_SCAN = "lastbdkfullscan"

        /** `CacheKeys.bdkRebuildRequested`. */
        const val KEY_REBUILD_REQUESTED = "bdkrebuildrequested"
    }
}
