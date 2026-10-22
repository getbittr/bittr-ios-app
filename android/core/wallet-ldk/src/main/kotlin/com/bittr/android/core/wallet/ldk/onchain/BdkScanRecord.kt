package com.bittr.android.core.wallet.ldk.onchain

/**
 * What the stored BDK wallet's scans are worth across launches — iOS's
 * `lastBdkFullScan` and `bdkRebuildRequested` cache keys (`BDKManager.swift`, PR #99).
 *
 * A full scan stands until the user asks for another one by pulling to refresh. A
 * launch that finds one stored, newer than the database it describes, light syncs
 * the loaded wallet instead of scanning it again.
 *
 * The implementation is `CachedBdkScanRecord`, in `cache/`.
 */
interface BdkScanRecord {

    /**
     * `hasStoredFullScan`: a full scan was recorded, and not before the database
     * was created. Both are compared in whole seconds.
     */
    val hasStoredFullScan: Boolean

    /** `storeFullScanCompletion()`. Only after the scan has persisted. */
    fun storeFullScanCompletion()

    /** `clearFullScanCompletion()`. The next launch scans again. */
    fun clearFullScanCompletion()

    /** `bdkRebuildIsRequested`: the next start builds the wallet from an empty database. */
    val rebuildRequested: Boolean

    /**
     * The stored half of `markBdkNeedsRebuild()`. Remembers the request, so the next
     * launch still rebuilds the wallet if this session doesn't, and forgets the last
     * full scan, so the next launch still scans if this one doesn't finish.
     */
    fun requestRebuild()

    /** `clearBdkRebuildRequest()`. The wallet has been built from scratch. */
    fun clearRebuildRequest()
}
