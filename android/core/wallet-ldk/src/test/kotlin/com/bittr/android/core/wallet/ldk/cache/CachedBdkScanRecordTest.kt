package com.bittr.android.core.wallet.ldk.cache

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * iOS's `hasStoredFullScan`, `markBdkNeedsRebuild()` and their cache keys (PR #99).
 */
class CachedBdkScanRecordTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private var now = 2_000L
    private var databaseCreated: Long? = 1_000L

    private fun record(cache: WalletCache = FileWalletCache(temporaryFolder.newFolder())) =
        CachedBdkScanRecord(cache = cache, databaseCreatedAt = { databaseCreated }, now = { now })

    @Test
    fun `a full scan newer than the database is stored`() {
        val record = record()
        assertFalse(record.hasStoredFullScan)

        record.storeFullScanCompletion()

        assertTrue(record.hasStoredFullScan)
    }

    /** Both are whole seconds, so a scan in the second the database was created still counts. */
    @Test
    fun `a full scan in the same second as the database counts`() {
        val record = record()
        now = 1_000L
        record.storeFullScanCompletion()

        assertTrue(record.hasStoredFullScan)
    }

    @Test
    fun `a full scan made in another database is distrusted`() {
        val record = record()
        record.storeFullScanCompletion()

        databaseCreated = now + 1

        assertFalse(record.hasStoredFullScan)
    }

    /** A clock that ran ahead when the database was created, and was corrected before the scan. */
    @Test
    fun `a full scan made in this database counts, whatever the clock did in between`() {
        val record = record()
        now = 500L
        record.storeFullScanCompletion()

        assertTrue(record.hasStoredFullScan)
    }

    /** Stored before scans recorded their database: the times are compared, as iOS does. */
    @Test
    fun `a full scan stored without its database is compared by time`() {
        val cache = FileWalletCache(temporaryFolder.newFolder())
        cache.put(CachedBdkScanRecord.KEY_LAST_FULL_SCAN, listOf("2000"))

        assertTrue(record(cache).hasStoredFullScan)
        databaseCreated = 2_001L
        assertFalse(record(cache).hasStoredFullScan)
    }

    @Test
    fun `no database means no stored full scan`() {
        val record = record()
        record.storeFullScanCompletion()

        databaseCreated = null

        assertFalse(record.hasStoredFullScan)
    }

    @Test
    fun `a cleared full scan is gone`() {
        val record = record()
        record.storeFullScanCompletion()

        record.clearFullScanCompletion()

        assertFalse(record.hasStoredFullScan)
    }

    @Test
    fun `a rebuild request forgets the full scan and survives a restart until cleared`() {
        val directory = temporaryFolder.newFolder()
        val record = record(FileWalletCache(directory))
        record.storeFullScanCompletion()

        record.requestRebuild()

        assertFalse(record.hasStoredFullScan)
        val afterRestart = record(FileWalletCache(directory))
        assertTrue(afterRestart.rebuildRequested)

        afterRestart.clearRebuildRequest()
        assertFalse(afterRestart.rebuildRequested)
    }

    /** iOS's keys, which wallet removal clears. */
    @Test
    fun `the keys are iOS's`() {
        assertTrue(CachedBdkScanRecord.KEY_LAST_FULL_SCAN == "lastbdkfullscan")
        assertTrue(CachedBdkScanRecord.KEY_REBUILD_REQUESTED == "bdkrebuildrequested")
    }
}
