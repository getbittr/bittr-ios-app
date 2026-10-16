package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.core.wallet.ldk.onchain.BdkOpenPort
import com.bittr.android.core.wallet.ldk.onchain.BdkScanRecord
import com.bittr.android.core.wallet.ldk.onchain.BdkStore
import com.bittr.android.core.wallet.ldk.onchain.BdkWalletOpener
import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureRecorder
import com.bittr.android.core.wallet.ldk.onchain.ChannelClosureScan
import com.bittr.android.core.wallet.ldk.onchain.DescriptorXpub
import com.bittr.android.core.wallet.ldk.onchain.FullScanParameters
import com.bittr.android.core.wallet.ldk.onchain.LightSyncParameters
import com.bittr.android.core.wallet.ldk.onchain.OnchainSync
import com.bittr.android.core.wallet.ldk.onchain.OnchainSyncPort
import com.bittr.android.core.wallet.ldk.onchain.OnchainWalletPort
import com.bittr.android.core.wallet.ldk.onchain.ScanCoordinator
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import com.bittr.android.core.wallet.ldk.onchain.WalletTransactions
import com.bittr.android.core.wallet.ldk.onchain.OnchainDrainPreview
import org.bitcoindevkit.Address
import org.bitcoindevkit.Amount
import org.bitcoindevkit.CanonicalTx
import org.bitcoindevkit.FeeRate
import org.bitcoindevkit.Script
import org.bitcoindevkit.SqliteException
import org.bitcoindevkit.TxBuilder
import org.bitcoindevkit.Connection
import org.bitcoindevkit.Descriptor
import org.bitcoindevkit.DescriptorSecretKey
import org.bitcoindevkit.ElectrumClient
import org.bitcoindevkit.FullScanRequest
import org.bitcoindevkit.KeychainKind
import org.bitcoindevkit.LoadWithPersistException
import org.bitcoindevkit.Mnemonic
import org.bitcoindevkit.Network
import org.bitcoindevkit.SyncRequest
import org.bitcoindevkit.Update
import org.bitcoindevkit.Wallet
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * BDK's `Wallet` behind [OnchainSyncPort] — the FFI half of `didSyncBdkWallet`.
 *
 * Every method is a forward. That is the point: the order of the calls, what
 * each failure means, and the parameters going in are all decided in
 * `onchain/OnchainSync`, where they are asserted on the JVM, and nothing is left
 * here that a device would have to be present to catch.
 *
 * ## The request builders are closed, and the reason is checkable
 *
 * `startFullScan()` returns a `FullScanRequestBuilder`, which is a Rust object
 * with a JNA pointer behind it, and Kotlin frees those from a `Cleaner` at an
 * unspecified time — the same hazard [LdkManagedNode.close] exists for. Closing
 * it after `build()` is safe rather than a double free because UniFFI's Kotlin
 * bindings call every method through `uniffiClonePointer()`: the Rust side gets
 * its own `Arc` clone and the Kotlin object still owns the handle it was given.
 * That is readable in the binding itself — `bdk-android-1.2.0.aar` declares
 * `uniffiClonePointer()` and `callWithPointer$lib_release` on every object class
 * — so it is a fact about the library rather than an assumption about it.
 *
 * @param wallet the live wallet field, read on every call. **A lambda and not a
 *   value**: `OnchainSync` re-reads it after the network round trip to catch a
 *   wallet replaced mid-scan, and a captured instance would make that check
 *   compare an object to itself and always pass.
 * @param connection the store `wallet` was opened against, for `persist`.
 * @param electrum the Electrum client. Also a lambda, because iOS rebuilds it
 *   lazily when it has been cleared (`BDKManager.swift:225–233`).
 * @param reconnect replace the Electrum client with a new one, after a light sync hung.
 */
class BdkSyncPort(
    private val wallet: () -> Wallet?,
    private val connection: () -> Connection,
    private val electrum: () -> ElectrumClient,
    private val reconnect: () -> Unit,
) : OnchainSyncPort<Wallet, FullScanRequest, SyncRequest, Update> {

    override fun currentWallet(): Wallet? = wallet()

    override fun startFullScan(wallet: Wallet): FullScanRequest =
        wallet.startFullScan().use { it.build() }

    override fun fullScan(request: FullScanRequest, parameters: FullScanParameters): Update =
        electrum().fullScan(
            request = request,
            stopGap = parameters.stopGap,
            batchSize = parameters.batchSize,
            fetchPrevTxouts = parameters.fetchPrevTxouts,
        )

    override fun startSyncWithRevealedSpks(wallet: Wallet): SyncRequest =
        wallet.startSyncWithRevealedSpks().use { it.build() }

    override fun sync(request: SyncRequest, parameters: LightSyncParameters): Update =
        electrum().sync(
            request = request,
            batchSize = parameters.batchSize,
            fetchPrevTxouts = parameters.fetchPrevTxouts,
        )

    override fun applyUpdate(wallet: Wallet, update: Update) = wallet.applyUpdate(update)

    override fun persist(wallet: Wallet) {
        wallet.persist(connection())
    }

    override fun reconnectElectrum() = reconnect()
}

/**
 * `bdkWallet.transactions()` as the pairs [ChannelClosureScan] compares —
 * iOS's `for tx in bdkWallet.transactions()` loop (`BDKManager.swift:497–508`).
 *
 * A forward and a field copy, like the rest of this file. The decision it feeds
 * — match on the **whole** outpoint rather than on the txid, because a funding
 * transaction can pay change back to this same wallet from another output — is
 * [ChannelClosureScan]'s and is asserted on the JVM. What is left here is the
 * mapping, and the one thing the mapping has to get right that iOS does not:
 * freeing what it walked.
 *
 * ## Every object this touches is a native handle, and none of them is reused
 *
 * `transactions()` returns a fresh `CanonicalTx` per call, each holding a
 * `Transaction`; `input()` returns fresh `TxIn`s, each holding a `Script`.
 * UniFFI's Kotlin bindings free all of them from a `java.lang.ref.Cleaner` at an
 * unspecified time — the hazard [LdkManagedNode.close] and [BdkWalletFactory]
 * exist for — so on a wallet with a hundred transactions a scan that dropped
 * them would leave several hundred Rust objects alive for an unbounded period,
 * on a platform that kills the process to reclaim memory. `destroy()` is what
 * hands them back at a known moment, and it cascades: `CanonicalTx.destroy()`
 * reaches its `Transaction` and `TxIn.destroy()` reaches its `Script`
 * (`javap -c org/bitcoindevkit/CanonicalTx.class`, `TxIn.class` — both call
 * `Disposable.Companion.destroy(...)` over their own fields).
 *
 * `OutPoint` is the exception and is why the values can outlive the walk: it is
 * a plain Kotlin class with a `String` and a `UInt` and no pointer behind it, so
 * the [TxOutpoint]s built here own nothing.
 *
 * **No JVM test, deliberately.** Every call on this path crosses into Rust and
 * returns a concrete native type, so there is no seam to fake below it — the
 * seam is [WalletTransactions] itself, which is where `ChannelClosureRecorder`
 * is proved. This class is the part that needs a device; it belongs to the
 * regtest suite in `wallet-node-device-tests.md`.
 *
 * @param wallet the live wallet field, read on every call, for the reason
 *   [BdkSyncPort] gives. Null is an ordinary answer — a teardown racing a sync —
 *   and it maps to no transactions rather than to a failure, which
 *   `ChannelClosureScan` then reads as "no closing transaction found".
 */
class BdkWalletTransactions(
    private val wallet: () -> Wallet?,
) : WalletTransactions {

    override fun transactions(): List<Pair<String, List<TxOutpoint>>> =
        wallet()?.transactions().orEmpty().map(::spentOutpoints)

    private fun spentOutpoints(canonical: CanonicalTx): Pair<String, List<TxOutpoint>> = try {
        val transaction = canonical.transaction
        transaction.computeTxid() to transaction.input().map { input ->
            try {
                // `previousOutput` is iOS's `eachInput.previousOutput`. The vout
                // is carried, not dropped: it is the half of the match that
                // stops a change-spending transaction being reported as the
                // channel's closure.
                TxOutpoint(txId = input.previousOutput.txid, vout = input.previousOutput.vout)
            } finally {
                input.destroy()
            }
        }
    } finally {
        canonical.destroy()
    }
}

/**
 * What a BDK start produced.
 *
 * The three objects are handed back together because they are freed together:
 * a `Wallet` whose `Connection` has been closed is a wallet that cannot persist,
 * and iOS's `clearBdkWalletReferences()` nils all three in one place for exactly
 * that reason (`BDKManager.swift:173–178`).
 *
 * @param accountXpub the BIP84 account xpub parsed out of the external
 *   descriptor, or null if it did not parse. Null rather than a failed start —
 *   see [DescriptorXpub], which is where that decision is stated and tested.
 */
class BdkWallet(
    val wallet: Wallet,
    val connection: Connection,
    val accountXpub: String?,
) : AutoCloseable {

    override fun close() {
        // Wallet first: it holds the connection, and closing the store out from
        // under it would be the wrong order to discover a bug in.
        runCatching { wallet.close() }
        runCatching { connection.close() }
    }
}

/**
 * `didStartBDK()` from the mnemonic down to the `Wallet` (`BDKManager.swift`, PR #99).
 *
 * ## Nothing here decides anything
 *
 * Whether to load the stored wallet or build a new one, and when a database is
 * thrown away, is [BdkWalletOpener]'s, tested on the JVM. The store's path is
 * [BdkStore]'s and the xpub parse is [DescriptorXpub]'s. What is left is the BDK
 * constructors in iOS's order, which is what an adapter should be.
 *
 * ## The empty passphrase is the same decision as on the Lightning side
 *
 * iOS builds the root key with `password: nil` (`BDKManager.swift:124`), and
 * this passes [LdkNodeConfig.MNEMONIC_PASSPHRASE] — the same empty string
 * ldk-node gets — rather than its own literal. The two must agree: BDK derives
 * the on-chain addresses and ldk-node derives the node's keys, both from these
 * twelve words, and a passphrase applied to one and not the other is a wallet
 * whose on-chain half and Lightning half belong to different seeds. Sharing the
 * constant makes that a compile-time fact instead of a convention.
 */
object BdkWalletFactory {

    /** [WalletNetwork] as BDK's enum. Total, so a new case fails to compile. */
    fun network(network: WalletNetwork): Network = when (network) {
        WalletNetwork.Bitcoin -> Network.BITCOIN
        WalletNetwork.Testnet -> Network.TESTNET
        WalletNetwork.Signet -> Network.SIGNET
        WalletNetwork.Regtest -> Network.REGTEST
    }

    /**
     * Open the wallet: load the stored one, or build a new one — see [BdkWalletOpener].
     *
     * @param mnemonic the device's twelve words.
     * @param databaseFile `WalletPaths.bdkDatabaseFile`. [BdkStore] refuses a path
     *   outside `bdk_store/` — the fence that stops its recursive delete from
     *   reaching the seed blob.
     * @param topPoolIndex the highest index in the cached on-chain address pool.
     * @throws Exception when no wallet could be opened.
     */
    fun open(
        mnemonic: String,
        network: WalletNetwork,
        databaseFile: File,
        record: BdkScanRecord,
        topPoolIndex: () -> Int?,
        log: (String) -> Unit,
        onError: (Throwable, Int) -> Unit,
    ): BdkWallet {
        val bdkNetwork = network(network)

        // `use` on all four, and the two secret-bearing ones are the reason.
        //
        // ARC frees these at the end of `didStartBDK` on iOS. UniFFI's Kotlin
        // bindings free the Rust object from a `java.lang.ref.Cleaner` instead, at
        // an unspecified time — so a dropped reference to a `Mnemonic` or a
        // `DescriptorSecretKey` is the **seed and the BIP32 root key sitting in
        // native heap for an unbounded period**, on a platform where the process is
        // routinely killed and its memory handed back to the system.
        //
        // Closing after `Wallet.load` or `Wallet(...)` is safe rather than a
        // use-after-free for the reason given in `BdkSyncPort`: UniFFI lowers every
        // object argument through `uniffiClonePointer()`, so the wallet holds its
        // own `Arc` and these four handles are ours to return.
        Mnemonic.fromString(mnemonic).use { words ->
            DescriptorSecretKey(
                network = bdkNetwork,
                mnemonic = words,
                password = LdkNodeConfig.MNEMONIC_PASSPHRASE,
            ).use { rootKey ->
                Descriptor.newBip84(rootKey, KeychainKind.EXTERNAL, bdkNetwork).use { external ->
                    Descriptor.newBip84(rootKey, KeychainKind.INTERNAL, bdkNetwork).use { internal ->
                        // `toString()` is the descriptor with the key material
                        // *replaced by the xpub*. `toStringWithSecret()` is the
                        // other one, and it is the one that must never reach a
                        // log or the signup request. Named here because the two
                        // are one word apart at a call site that ships a string
                        // to our backend (`Transfer2ViewController.swift:344–362`).
                        val accountXpub = DescriptorXpub.extract(external.toString())

                        val opened = BdkWalletOpener(
                            port = BdkOpen(databaseFile, bdkNetwork, external, internal),
                            record = record,
                            topPoolIndex = topPoolIndex,
                            log = log,
                            onError = onError,
                        ).open()
                        return BdkWallet(
                            wallet = opened.wallet,
                            connection = opened.store,
                            accountXpub = accountXpub,
                        )
                    }
                }
            }
        }
    }

    /** [BdkOpenPort] over bdk-android: one-line forwards, as [BdkSyncPort] is. */
    private class BdkOpen(
        private val databaseFile: File,
        private val network: Network,
        private val external: Descriptor,
        private val internal: Descriptor,
    ) : BdkOpenPort<Connection, Wallet> {

        override fun openStore(): Connection = Connection(BdkStore.open(databaseFile).absolutePath)

        override fun recreateStore(): Connection = Connection(BdkStore.recreate(databaseFile).absolutePath)

        override fun closeStore(store: Connection) {
            runCatching { store.close() }
        }

        override fun load(store: Connection): Wallet = Wallet.load(external, internal, store)

        override fun isOnThisNetwork(wallet: Wallet): Boolean = wallet.network() == network

        override fun closeWallet(wallet: Wallet) {
            runCatching { wallet.close() }
        }

        override fun create(store: Connection): Wallet = Wallet(external, internal, network, store)

        override fun revealTo(wallet: Wallet, store: Connection, index: Int) {
            val revealed = wallet.revealAddressesTo(KeychainKind.EXTERNAL, index.toUInt())
            try {
                if (revealed.isNotEmpty()) wallet.persist(store)
            } finally {
                revealed.forEach { it.destroy() }
            }
        }

        override fun isCorruptDatabase(failure: Throwable): Boolean {
            // SQLite's own wording for a damaged file, or one that isn't a database at all.
            val message = when (failure) {
                is SqliteException.Sqlite -> failure.rusqliteError
                is LoadWithPersistException.Persist -> failure.errorMessage
                else -> return false
            }
            return CORRUPT_DATABASE_MESSAGES.any { it in message }
        }

        override fun nothingToLoadReason(failure: Throwable): String? = when (failure) {
            is LoadWithPersistException.CouldNotLoad -> "nothing stored"
            is LoadWithPersistException.InvalidChangeSet -> "stored data did not match"
            else -> null
        }
    }

    /** `Error.isCorruptDatabase`'s two SQLite messages. */
    private val CORRUPT_DATABASE_MESSAGES = listOf("database disk image is malformed", "file is not a database")
}

/**
 * The three references iOS keeps as fields, as the one object that owns them.
 *
 * `BitcoinManager` holds `bdkWallet`, `connection`, `electrumClient` and `xpub`
 * as properties of a singleton, sets them in `didStartBDK()` and nils them in
 * `clearBdkWalletReferences()` / the node-teardown block
 * (`BDKManager.swift:178–183`, `BitcoinManager.swift:678–692`). This is that,
 * scoped to a node's lifetime instead of the process's, because
 * `OnchainSyncLoop` is a `NodeRunner` and a wallet outliving its node is exactly
 * what [OnchainSync]'s identity re-check exists to catch.
 *
 * ## Why it is a class here and four fields there
 *
 * [OnchainSyncLoop] has to be able to say "open the wallet" and "let it go"
 * without naming a BDK type, or the loop would live in `adapter/` and its
 * sequence would stop being JVM-provable. [OnchainWalletPort] is that pair of
 * calls; this is the only implementation, and everything in it is a field
 * assignment around [BdkWalletFactory.open].
 *
 * [reopen] is `didRebuildBdkWallet()`'s release-and-start: with a rebuild requested
 * in [record], the open it runs builds the wallet from an empty database.
 *
 * ## The locking is iOS's `bdkStartLock`, plus one Android-only read
 *
 * [open] and [close] are `synchronized` for the reason `didStartBDK` takes a
 * lock: two starts racing would build two wallets over one SQLite file. The
 * extra piece is [current] being `@Volatile` — it is read from a *third* place,
 * the full scan running in `ScanCoordinator`'s own scope, and that read is
 * `OnchainSync`'s `===` check on whether the wallet was replaced mid-scan. A
 * non-volatile field could hand that check a stale reference and turn a genuine
 * replacement into a silent pass.
 *
 * @param mnemonic read on every [open] and never cached. iOS's
 *   `CacheManager.getMnemonic()` with its `guard ... else` — a null is *not* an
 *   error, it is a wallet being torn down, and it reports `false` for the same
 *   reason.
 * @param electrumUrl `EnvironmentConfig.electrumURL`. **Not the node's chain
 *   source**: on every network but mainnet iOS points ldk-node at Esplora and
 *   BDK at Electrum, so reusing `LdkEnvironment.chainSourceUrl` here would hand
 *   `ElectrumClient` an HTTP Esplora endpoint on every development build and
 *   fail as "sync failed" with nothing naming the cause.
 * @param record the stored full scan and rebuild request.
 * @param topPoolIndex the highest index in the cached on-chain address pool, revealed
 *   again (plus five) on a newly built wallet.
 */
class BdkOnchainWalletHolder(
    private val mnemonic: () -> String?,
    private val network: WalletNetwork,
    private val databaseFile: File,
    private val electrumUrl: String,
    private val record: BdkScanRecord,
    private val topPoolIndex: () -> Int?,
    private val log: (String) -> Unit = {},
    /** A failure iOS hands `handleError`, with its row. */
    private val onError: (Throwable, Int) -> Unit = { _, _ -> },
    /** A start that failed, with the exception iOS hands `handleError`. */
    private val onOpenFailure: (Throwable) -> Unit = {},
) : OnchainWalletPort {

    private val lock = Any()

    @Volatile
    private var current: BdkWallet? = null

    @Volatile
    private var electrum: ElectrumClient? = null

    private val _opened = MutableStateFlow(false)

    /**
     * Whether a wallet is open. The address pool waits on it: every address it hands out
     * is peeked from this wallet, and before `didStartBDK` there is nothing to peek.
     */
    val opened: StateFlow<Boolean> = _opened.asStateFlow()

    /** The BIP84 account xpub of the open wallet, or null. iOS's `self.xpub`. */
    val accountXpub: String? get() = current?.accountXpub

    /**
     * The open wallet's transactions, for the closure scan.
     *
     * Exposed as [WalletTransactions] rather than built inside [sync] so
     * `di/WalletModule` can compose the recorder itself: the other two things
     * `ChannelClosureRecorder` needs are the cache store and the node's channel
     * list, and neither of them is this class's to reach for — a holder that
     * went looking for a `NodeLifecycle` would be an on-chain wallet that knows
     * about Lightning.
     *
     * Valid across opens, like [sync]: it re-reads [current] on every call, so a
     * wallet closed and reopened by a node restart needs no new recorder.
     */
    val transactions: WalletTransactions = BdkWalletTransactions { current?.wallet }

    override fun open(): Boolean = synchronized(lock) {
        // `guard self.bdkWallet == nil else { return true }`. Idempotent, and the
        // loop relies on it: a node restart within one process re-runs `open`.
        if (current != null) return true

        return try {
            // Inside the `try`, not above it. `SeedVault.read` returns null for
            // "there is no seed" and *throws* for "the Keystore could not answer
            // right now" — a distinction iOS does not have, because
            // `CacheManager.getMnemonic()` only ever returns nil. A throw
            // escaping here would leave `OnchainSyncLoop.run` via its `finally`
            // and reach `WalletNodeHost.onRunnerStopped`, so a transient unlock
            // failure would end the sync loop for the life of the node rather
            // than failing one open.
            val words = mnemonic() ?: return false

            current = BdkWalletFactory.open(words, network, databaseFile, record, topPoolIndex, log, onError)
            _opened.value = true
            // Built here as well as lazily below, because iOS builds it inside
            // `didStartBDK` (`BDKManager.swift:166`) and treats a failure there
            // as a failed start rather than as a failed sync. A wallet that
            // cannot reach its Electrum server is not a wallet that opened.
            electrum = ElectrumClient(electrumUrl)
            true
        } catch (failure: Exception) {
            onOpenFailure(failure)
            closeLocked()
            false
        }
    }

    override fun close() = synchronized(lock) { closeLocked() }

    /**
     * Release the open wallet and open it again — `didRebuildBdkWallet()`'s
     * `bdkWallet = nil; connection = nil; didStartBDK()`. With a rebuild requested in
     * [record], the open builds the wallet from an empty database.
     */
    fun reopen(): Boolean = synchronized(lock) {
        closeLocked()
        open()
    }

    /**
     * The sync sequence for whatever wallet is open, bound to [scans].
     *
     * Returned star-projected so `di/WalletModule` can hold one: `:app` cannot
     * name `org.bitcoindevkit.Wallet`, because `:core:wallet-ldk` depends on
     * bdk-android with `implementation`. Nothing is lost — neither `fullScan` nor
     * `lightSync` returns a BDK type.
     *
     * Built once and valid across opens: every lambda in [BdkSyncPort] re-reads
     * the field, which is the property its own KDoc says the identity check
     * depends on.
     *
     * @param closures the closure scan [OnchainSync] runs at the end of a sync
     *   that applied, or null for a wallet that does not record closures. Not
     *   defaulted, for the reason [OnchainSync]'s own parameter is not: this is
     *   the last call site between a composed wallet and a closure that is never
     *   recorded, and a forgotten argument here would be invisible.
     */
    fun sync(
        scans: ScanCoordinator,
        closures: ChannelClosureRecorder?,
    ): OnchainSync<*, *, *, *> = OnchainSync(
        port = BdkSyncPort(
            wallet = { current?.wallet },
            connection = { requireNotNull(current).connection },
            // iOS's `if self.electrumClient == nil` inside `didSyncBdkWallet`
            // (`BDKManager.swift:232–239`): rebuilt on demand when a teardown
            // cleared it, rather than failing the sync.
            electrum = { electrum ?: ElectrumClient(electrumUrl).also { electrum = it } },
            // A hung light sync may have left the Electrum connection stuck, so open a new one.
            reconnect = {
                val previous = electrum
                electrum = ElectrumClient(electrumUrl)
                runCatching { previous?.close() }
            },
        ),
        scans = scans,
        closures = closures,
        record = record,
        reopenWallet = ::reopen,
        log = log,
    )

    /**
     * `getAddress(atIndex:doReveal: false)` — the external address at [index], without
     * revealing it. Null when no wallet is open.
     *
     * The `AddressInfo` is a native handle, and so is the `Address` inside it; both are
     * freed here once the string is out, for the reason [BdkWalletTransactions] frees what
     * it walks.
     */
    fun peekAddress(index: Int): String? {
        val wallet = current?.wallet ?: return null
        val info = wallet.peekAddress(KeychainKind.EXTERNAL, index.toUInt())
        return try {
            info.address.use { it.toString() }
        } finally {
            info.destroy()
        }
    }

    /**
     * `revealAddresses(toIndex:)` — reveal every external address up to [index] and persist,
     * so a light sync watches them. A no-op when nothing new was revealed, as on iOS.
     */
    fun revealAddressesTo(index: Int) = synchronized(lock) {
        val open = current ?: return@synchronized
        val revealed = open.wallet.revealAddressesTo(KeychainKind.EXTERNAL, index.toUInt())
        try {
            if (revealed.isNotEmpty()) open.wallet.persist(open.connection)
        } finally {
            revealed.forEach { it.destroy() }
        }
    }

    /**
     * `maximumSendableOnchainDrain`'s BDK half (`BDKManager.swift:388`): drain the whole
     * wallet to [address] at [satPerVb], sign, and read the one output, the fee and the
     * vsize. With no or an unparseable address the largest common output script stands in
     * for the recipient, so the quoted fee is never an underestimate.
     *
     * Null when no wallet is open. Throws BDK's error when the drain cannot be built — an
     * empty wallet, or fees above the balance — which callers treat as "nothing sendable".
     */
    fun drainPreview(address: String?, satPerVb: ULong): OnchainDrainPreview? = synchronized(lock) {
        val open = current ?: return null
        val script = address?.let { recipientScript(it) } ?: Script(LARGEST_COMMON_OUTPUT_SCRIPT)
        FeeRate.fromSatPerVb(maxOf(satPerVb, 1uL)).use { rate ->
            val psbt = TxBuilder().drainWallet().drainTo(script).feeRate(rate).finish(open.wallet)
            psbt.use {
                open.wallet.sign(psbt, null)
                psbt.extractTx().use { tx ->
                    OnchainDrainPreview(
                        sendableSats = tx.output().first().value,
                        feeSats = psbt.fee(),
                        vsize = tx.vsize(),
                    )
                }
            }
        }
    }

    /**
     * `getSize(address:amountSats:selectedVbyte:)` — the vsize of a transaction paying
     * [amountSats] to [address], signed so the witness is counted. Null when no wallet is open.
     */
    fun transactionVsize(address: String, amountSats: Long, satPerVb: ULong): ULong? = synchronized(lock) {
        val open = current ?: return null
        val script = recipientScript(address) ?: throw IllegalArgumentException("Not an address on this network")
        FeeRate.fromSatPerVb(maxOf(satPerVb, 1uL)).use { rate ->
            val psbt = TxBuilder()
                .addRecipient(script, Amount.fromSat(amountSats.toULong()))
                .feeRate(rate)
                .finish(open.wallet)
            psbt.use {
                open.wallet.sign(psbt, null)
                psbt.extractTx().use { it.vsize() }
            }
        }
    }

    private fun recipientScript(address: String): Script? = runCatching {
        Address(address, BdkWalletFactory.network(network)).use { it.scriptPubkey() }
    }.getOrNull()

    private fun closeLocked() {
        // Wallet first, for the ordering `BdkWallet.close` states; the Electrum
        // client holds no reference to either and goes last.
        _opened.value = false
        runCatching { current?.close() }
        current = null
        runCatching { electrum?.close() }
        electrum = null
    }

    private companion object {
        /** `BitcoinManager.largestCommonOutputScript`: a P2TR script, the largest common output. */
        val LARGEST_COMMON_OUTPUT_SCRIPT: List<UByte> =
            listOf(0x51.toUByte(), 0x20.toUByte()) + List(32) { 0.toUByte() }
    }
}
