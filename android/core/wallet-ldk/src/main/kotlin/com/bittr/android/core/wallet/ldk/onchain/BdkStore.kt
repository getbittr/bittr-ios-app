package com.bittr.android.core.wallet.ldk.onchain

import java.io.File

/**
 * Preparing BDK's SQLite store for a wallet start.
 *
 * Port of `Connection.createConnection()` (`BitcoinManager.swift:832–850`) —
 * which is the **app's own extension, not a BDK API**. Worth stating because
 * bdk-android 1.2.0's `Connection` companion offers only `newInMemory()`, so a
 * port that goes looking for `createConnection` finds nothing and has to decide
 * what the path and the lifecycle are. Both are decided here, out of the iOS
 * source, rather than improvised in an adapter no JVM test can reach.
 *
 * ## iOS deletes the whole store on every start. That is ported, deliberately.
 *
 * ```swift
 * if FileManager.default.fileExists(atPath: walletDataDirectoryURL.path) {
 *     try FileManager.default.removeItem(at: walletDataDirectoryURL)
 * }
 * ```
 *
 * `createConnection()` is called from `didStartBDK()` (`BDKManager.swift:149`) on
 * every start, so BDK begins every launch with an empty store. Three consequences,
 * and they are the reason this is a named, tested decision rather than a line in
 * an adapter:
 *
 * 1. **A full scan is mandatory after every start, not an optimisation.** With an
 *    empty store BDK knows no UTXOs, so `startFullScan` with `stopGap: 25` is the
 *    only thing that makes the wallet's own coins visible. That is why
 *    `StartLightning.swift:186` full-scans unless `hasBeenScanned`.
 * 2. **It is safe for funds, and that is why it is ported rather than questioned.**
 *    Everything in this store is chain data derived from the two BIP84 descriptors,
 *    and those come from the mnemonic. No key material lives here, nothing in it is
 *    irreplaceable, and BIT-8 rule 1 is untouched. Deleting it costs a scan, not a
 *    coin.
 * 3. **On Android the cost lands far more often than on iOS.** Process death is
 *    routine rather than exceptional, so "full scan per start" becomes "full scan
 *    per process", each one a fresh Electrum/Esplora round trip with a 180-second
 *    watchdog ([ScanCoordinator]) that Doze can push past. A start whose scan fails
 *    presents an empty wallet: balance zero, and a drain preview that throws
 *    `drainProducedNoOutput` rather than offering a wrong number. **It fails
 *    closed**, which is why this is flagged as a cost and a UX question rather
 *    than as a fund risk — but it is the single most likely reason an Android user
 *    sees "no funds" on a wallet that has them, so it belongs in the security
 *    write-up as a known behaviour and not as a surprise.
 *
 * The alternative — persisting the store across starts — is a **deviation from
 * iOS behaviour**, and this issue's notes put that decision with the founder, not
 * in this file. It is raised on the issue rather than taken here.
 *
 * ## Where the store lives, and why the delete is fenced
 *
 * iOS puts it at `Documents/wallet_data/wallet.sqlite`. On Android it is
 * `WalletPaths.bdkDatabaseFile`, inside `WalletPaths.bdkStoreDir` — under
 * `no_backup/wallet/`, so it inherits the BIT-8 rule 4 / BIT-20 rule 5 backup
 * exclusion by path rather than by a manifest entry a later PR can weaken. It is
 * deliberately *not* inside `ldkStateDir`: the BIT-20 quarantine moves that
 * directory, and a quarantine must not drag BDK's cache along.
 *
 * **The dedicated directory is load-bearing, not organisational.** iOS's
 * `wallet_data/` holds only `wallet.sqlite`, so deleting it recursively is safe.
 * Until `bdkStoreDir` was split out, Android's database sat directly in
 * `walletDir` beside `seed.bin`, `ldk_state/` and `foreign_ldk_state/` — where
 * this same ported delete would have destroyed the seed blob and every channel
 * state on the device, on a routine start. [prepare] therefore refuses to delete
 * a directory that is not named [EXPECTED_DIR_NAME], so the layout cannot regress
 * into that shape without failing loudly. A comment would not have stopped it; a
 * precondition does.
 *
 * Proved by `BdkStoreTest`, which asserts the siblings survive and that a
 * mis-sited database is rejected rather than honoured.
 */
object BdkStore {

    /**
     * Clear and recreate the directory holding BDK's SQLite file, returning the
     * path to open a `Connection` at.
     *
     * Mirrors `createConnection()`'s order exactly: delete the directory if it
     * exists, recreate it, then hand back the file path inside it.
     *
     * @param databaseFile `WalletPaths.bdkDatabaseFile`.
     * @return the same file, with its parent directory guaranteed present and empty.
     * @throws java.io.IOException if the directory cannot be cleared or created —
     *   a failure, not something to proceed past. iOS's `try` propagates and
     *   `didStartBDK` returns false (`BDKManager.swift:147–152`); the same
     *   distinction BIT-20 rule 3 draws for the Keystore applies here.
     */
    fun prepare(databaseFile: File): File {
        val directory = databaseFile.parentFile
            ?: throw java.io.IOException("BDK database path has no parent directory: $databaseFile")

        // The fence. This function recursively deletes `directory`, so it must be
        // BDK's own directory and nothing else — see the class comment for what
        // sat next to the database before `bdkStoreDir` existed.
        require(directory.name == EXPECTED_DIR_NAME) {
            "Refusing to clear '${directory.name}': BdkStore.prepare deletes this " +
                "directory recursively and will only do so for a directory named " +
                "'$EXPECTED_DIR_NAME'. The BDK database must live in its own " +
                "directory (WalletPaths.bdkStoreDir), never beside the seed blob " +
                "or the LDK state directory. Got: $databaseFile"
        }

        if (directory.exists() && !directory.deleteRecursively()) {
            throw java.io.IOException("Could not clear BDK store directory: $directory")
        }
        if (!directory.mkdirs() && !directory.isDirectory) {
            throw java.io.IOException("Could not create BDK store directory: $directory")
        }
        return databaseFile
    }

    /**
     * The only directory name [prepare] will clear.
     *
     * Deliberately duplicated from `WalletPaths.BDK_STORE_DIR` rather than
     * referenced: `state/` may not depend on `onchain/` or the reverse, and a
     * fence that imports its own bound from the thing it is fencing is not a
     * fence. `BdkStoreTest` asserts the two strings agree, so the duplication
     * cannot drift.
     */
    const val EXPECTED_DIR_NAME = "bdk_store"
}
