package com.bittr.android.core.wallet.ldk.onchain

/**
 * The BDK calls opening a wallet makes, as a seam with no BDK types in it.
 *
 * @param C the store. `org.bitcoindevkit.Connection` in production.
 * @param W the wallet. `org.bitcoindevkit.Wallet` in production.
 */
interface BdkOpenPort<C : Any, W : Any> {

    /** `Connection.open()`. */
    fun openStore(): C

    /** `Connection.recreate()`. */
    fun recreateStore(): C

    /** Release the store, before the file underneath it is deleted. */
    fun closeStore(store: C)

    /** `Wallet.load(descriptor:changeDescriptor:connection:)`. Throws when nothing loads. */
    fun load(store: C): W

    /** Whether the loaded wallet's network is this build's network. */
    fun isOnThisNetwork(wallet: W): Boolean

    /** Release a wallet this sequence will not hand back. */
    fun closeWallet(wallet: W)

    /** `Wallet(descriptor:changeDescriptor:network:connection:)`. */
    fun create(store: C): W

    /** `revealAddresses(toIndex:)`: reveal external addresses up to [index] and persist them. */
    fun revealTo(wallet: W, store: C, index: Int)

    /** `Error.isCorruptDatabase`: SQLite's own wording for a damaged file, or one that isn't a database. */
    fun isCorruptDatabase(failure: Throwable): Boolean

    /**
     * Why nothing loaded, when that is a reason to start a new database: `CouldNotLoad`
     * ("nothing stored") or `InvalidChangeSet` ("stored data did not match"). Null for
     * anything else.
     */
    fun nothingToLoadReason(failure: Throwable): String?
}

/** `WalletError.storedWalletOnAnotherNetwork`: the stored wallet was written on a different network. */
class StoredWalletOnAnotherNetworkException : Exception("The stored wallet was written on a different network")

/**
 * Opening the BDK wallet — the store and wallet half of `didStartBDK()` (`BDKManager.swift`,
 * PR #99), in iOS's order.
 *
 * 1. **Open the store** as it is, or an empty one when the user asked for a rebuild. A
 *    corrupt database holds nothing worth keeping, so it is replaced by an empty one. Any
 *    other failure may pass, so the file is left for the next launch to try again.
 * 2. **Load the stored wallet**, and check it was written on this build's network.
 *    `Wallet.load` itself refuses a database that belongs to another seed.
 * 3. **Only replace a database that is corrupt, or doesn't hold this wallet**: nothing
 *    stored, stored data that does not match, another network, or a corrupt file. Any
 *    other read failure keeps the file for the next launch. A replacement forgets the
 *    last full scan, builds a new wallet, reveals the cached address pool again for light
 *    syncs to watch, and clears a requested rebuild.
 *
 * Proved by `BdkWalletOpenerTest`.
 *
 * @param topPoolIndex the highest index in the cached on-chain address pool, or null.
 * @param onError a failure iOS hands `handleError(error:row:)`, with its row.
 */
class BdkWalletOpener<C : Any, W : Any>(
    private val port: BdkOpenPort<C, W>,
    private val record: BdkScanRecord,
    private val topPoolIndex: () -> Int?,
    private val log: (String) -> Unit = {},
    private val onError: (Throwable, Int) -> Unit = { _, _ -> },
) {

    /** A wallet and the store it was opened against. */
    data class Opened<C, W>(val store: C, val wallet: W, val loaded: Boolean)

    /**
     * Open the wallet.
     *
     * @throws Exception when no wallet could be opened. Nothing is left open then.
     */
    fun open(): Opened<C, W> {
        // Open the stored wallet database, or an empty one when the user asked for a rebuild.
        val opened = try {
            if (record.rebuildRequested) {
                log("A BDK rebuild was requested. Will start from an empty database.")
                port.recreateStore()
            } else {
                port.openStore()
            }
        } catch (failure: Exception) {
            if (!port.isCorruptDatabase(failure)) {
                // Anything else may pass, so leave the file for the next launch to try again.
                onError(failure, ROW_OPEN_FAILED)
                throw failure
            }
            onError(failure, ROW_OPEN_CORRUPT)

            // A corrupt database holds nothing worth keeping, so start an empty one.
            record.clearFullScanCompletion()
            try {
                port.recreateStore()
            } catch (recreateFailure: Exception) {
                onError(recreateFailure, ROW_RECREATE_FAILED)
                throw recreateFailure
            }
        }

        return try {
            loadStored(opened)
        } catch (failure: Exception) {
            replaceStore(opened, failure)
        }
    }

    private fun loadStored(store: C): Opened<C, W> {
        // Check whether a stored BDK wallet is available.
        val loaded = port.load(store)

        // Confirm the stored wallet's network matches this build's network.
        if (!port.isOnThisNetwork(loaded)) {
            port.closeWallet(loaded)
            throw StoredWalletOnAnotherNetworkException()
        }

        log("Did load the stored BDK wallet.")
        if (record.hasStoredFullScan) {
            log("A full scan is stored. Will light sync rather than scan.")
        } else {
            log("No stored full scan is available. Will scan.")
        }
        return Opened(store, loaded, loaded = true)
    }

    private fun replaceStore(store: C, failure: Exception): Opened<C, W> {
        // Only replace a database that is corrupt, or doesn't hold this wallet.
        val reason = when {
            failure is StoredWalletOnAnotherNetworkException -> "stored on another network"
            else -> port.nothingToLoadReason(failure)
                ?: if (port.isCorruptDatabase(failure)) "database is corrupt" else null
        }
        if (reason == null) {
            // A read failure may pass, so keep the file for the next launch to try again.
            onError(failure, ROW_LOAD_FAILED)
            port.closeStore(store)
            throw failure
        }
        log("No stored BDK wallet to load ($reason). Creating one.")

        // Release the database before deleting the file underneath it.
        port.closeStore(store)
        record.clearFullScanCompletion()

        var recreated: C? = null
        try {
            val fresh = port.recreateStore()
            recreated = fresh
            val wallet = port.create(fresh)

            // A new wallet has revealed nothing, so reveal the cached address pool again for syncs to watch.
            topPoolIndex()?.let { topIndex ->
                // Reveal a little beyond the pool too, like manageOnchainAddresses does for channel closures.
                port.revealTo(wallet, fresh, topIndex + REVEAL_BEYOND_POOL)
            }

            // The wallet has been built from scratch, so a requested rebuild is done.
            record.clearRebuildRequest()
            return Opened(fresh, wallet, loaded = false)
        } catch (createFailure: Exception) {
            onError(createFailure, ROW_CREATE_FAILED)
            recreated?.let(port::closeStore)
            throw createFailure
        }
    }

    companion object {
        /** `revealAddresses(toIndex: topIndex + 5)`. */
        const val REVEAL_BEYOND_POOL = 5

        // iOS's `handleError` rows, so a log line can be matched to the iOS branch.
        const val ROW_OPEN_CORRUPT = 211
        const val ROW_OPEN_FAILED = 213
        const val ROW_RECREATE_FAILED = 214
        const val ROW_LOAD_FAILED = 216
        const val ROW_CREATE_FAILED = 218
    }
}
