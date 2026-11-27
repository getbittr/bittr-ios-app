package com.bittr.android.core.wallet.ldk.onchain

import java.io.File

/**
 * BDK's SQLite store: opened as it is, or thrown away and started empty.
 *
 * Port of `Connection.open()`, `Connection.recreate()` and
 * `Connection.walletDatabaseCreationDate` (`BitcoinManager.swift`, PR #99) — the
 * **app's own extension, not a BDK API**. bdk-android 1.2.0's `Connection` takes
 * a path and nothing else, so the directory, its lifecycle and the creation date
 * are decided here, out of the iOS source.
 *
 * ## The store is kept between starts
 *
 * iOS used to delete `wallet_data/` on every start, so every launch paid for a
 * full scan. Since PR #99 it opens the stored database instead, loads the wallet
 * from it with `Wallet.load`, and only starts empty when the stored data is
 * corrupt, belongs to another seed or network, or the user pulled to refresh.
 * [open] and [recreate] are those two paths; `BdkWalletOpener` decides between
 * them.
 *
 * Everything in this store is chain data derived from the two BIP84 descriptors.
 * No key material lives here, so throwing it away costs a scan, not a coin.
 *
 * ## When the database was created
 *
 * iOS distrusts a stored full scan older than the database it describes, and
 * reads the database file's creation date for that. Android's file systems do
 * not reliably report a creation date — `BasicFileAttributes.creationTime()`
 * falls back to the modification time, which every write moves past the scan.
 * So the creation time is written down instead, in [CREATED_AT_FILE] beside the
 * database, by [recreate] and by the first [open] that finds none, or finds one it
 * cannot read. It is not essential: when it cannot be written, the database simply
 * has no known creation time, and the next launch scans in full.
 *
 * ## Where the store lives, and why the delete is fenced
 *
 * iOS puts it at `Documents/wallet_data/wallet.sqlite`. On Android it is
 * `WalletPaths.bdkDatabaseFile`, inside `WalletPaths.bdkStoreDir` — under
 * `no_backup/wallet/`, so it inherits the backup exclusion by path. It is
 * deliberately *not* inside `ldkStateDir`: a quarantine moves that directory, and
 * must not drag BDK's store along.
 *
 * **The dedicated directory is load-bearing, not organisational.** iOS's
 * `wallet_data/` holds only `wallet.sqlite`, so deleting it recursively is safe.
 * Android's `walletDir` also holds `seed.bin`, `ldk_state/` and
 * `foreign_ldk_state/`, where the same recursive delete would destroy the seed
 * blob and every channel state on the device. [recreate] and [delete] therefore
 * refuse a directory that is not named [EXPECTED_DIR_NAME].
 *
 * Proved by `BdkStoreTest`.
 */
object BdkStore {

    /**
     * `Connection.open()`: make sure the store's directory exists and hand back the
     * database path, leaving whatever is stored there in place.
     *
     * @param databaseFile `WalletPaths.bdkDatabaseFile`.
     * @return the same file, with its parent directory guaranteed present.
     * @throws java.io.IOException if the directory cannot be created.
     */
    fun open(databaseFile: File): File {
        val directory = storeDirectory(databaseFile)
        if (!directory.mkdirs() && !directory.isDirectory) {
            throw java.io.IOException("Could not create BDK store directory: $directory")
        }
        // A store whose creation time is missing or unreadable counts as created now.
        // Any full scan recorded before this moment is then distrusted, as on iOS.
        val createdAt = File(directory, CREATED_AT_FILE)
        if (readCreatedAt(createdAt) == null) writeCreatedAt(createdAt)
        return databaseFile
    }

    /**
     * `Connection.recreate()`: throw the stored wallet away and open an empty
     * database in its place.
     *
     * @throws java.io.IOException if the directory cannot be cleared or created.
     */
    fun recreate(databaseFile: File): File {
        delete(databaseFile)
        return open(databaseFile)
    }

    /**
     * Delete the store's directory and everything in it. Used by [recreate], and by
     * wallet removal, so the removed wallet's history doesn't outlive its seed —
     * iOS deletes it with the rest of `Documents` (`deleteDocuments()`).
     *
     * @throws java.io.IOException if the directory cannot be deleted.
     */
    fun delete(databaseFile: File) {
        val directory = storeDirectory(databaseFile)
        // `deleteRecursively` follows a symlinked directory, so a link here could reach
        // anything the app can write. Nothing in the app creates one.
        require(!java.nio.file.Files.isSymbolicLink(directory.toPath())) {
            "Refusing to delete '$directory': it is a symbolic link"
        }
        if (directory.exists() && !directory.deleteRecursively()) {
            throw java.io.IOException("Could not clear BDK store directory: $directory")
        }
    }

    /**
     * `Connection.walletDatabaseCreationDate`, in whole seconds since the epoch.
     *
     * Null when there is no database, or no creation time was written down for it.
     */
    fun creationEpochSeconds(databaseFile: File): Long? {
        if (!databaseFile.exists()) return null
        return readCreatedAt(File(databaseFile.parentFile ?: return null, CREATED_AT_FILE))
    }

    private fun readCreatedAt(file: File): Long? =
        runCatching { file.readText().trim().toLong() }.getOrNull()

    /** Written to a temporary file and renamed into place, so it is never read half-written. */
    private fun writeCreatedAt(file: File) {
        val temporary = File(file.parentFile, "$CREATED_AT_FILE.tmp")
        val written = runCatching {
            temporary.writeText((System.currentTimeMillis() / 1000).toString())
            temporary.renameTo(file)
        }.getOrDefault(false)
        if (!written) temporary.delete()
    }

    private fun storeDirectory(databaseFile: File): File {
        val directory = databaseFile.parentFile
            ?: throw java.io.IOException("BDK database path has no parent directory: $databaseFile")

        // The fence. [delete] removes this directory recursively, so it must be
        // BDK's own directory and nothing else — see the class comment.
        require(directory.name == EXPECTED_DIR_NAME) {
            "Refusing to use '${directory.name}': BdkStore deletes this " +
                "directory recursively and will only do so for a directory named " +
                "'$EXPECTED_DIR_NAME'. The BDK database must live in its own " +
                "directory (WalletPaths.bdkStoreDir), never beside the seed blob " +
                "or the LDK state directory. Got: $databaseFile"
        }
        return directory
    }

    /**
     * The only directory name this object will use, and so the only one it deletes.
     *
     * Deliberately duplicated from `WalletPaths.BDK_STORE_DIR` rather than
     * referenced: `state/` may not depend on `onchain/` or the reverse, and a
     * fence that imports its own bound from the thing it is fencing is not a
     * fence. `BdkStoreTest` asserts the two strings agree, so the duplication
     * cannot drift.
     */
    const val EXPECTED_DIR_NAME = "bdk_store"

    /** When the database was created, in whole seconds since the epoch. */
    const val CREATED_AT_FILE = "created_at"
}
