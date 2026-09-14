package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.core.wallet.ldk.onchain.BdkStore
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
import org.bitcoindevkit.CanonicalTx
import org.bitcoindevkit.Connection
import org.bitcoindevkit.Descriptor
import org.bitcoindevkit.DescriptorSecretKey
import org.bitcoindevkit.ElectrumClient
import org.bitcoindevkit.FullScanRequest
import org.bitcoindevkit.KeychainKind
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
 */
class BdkSyncPort(
    private val wallet: () -> Wallet?,
    private val connection: () -> Connection,
    private val electrum: () -> ElectrumClient,
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
 * `didStartBDK()` from the mnemonic down to the `Wallet` (`BDKManager.swift:99–172`).
 *
 * ## Nothing here decides anything, and the two places it could have are gone
 *
 * The store's path and its wipe-on-start are [BdkStore]'s, tested on the JVM
 * against a real temp directory; the xpub parse is [DescriptorXpub]'s. What is
 * left is six BDK constructors in iOS's order, which is what an adapter should
 * be.
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
     * Open the wallet, clearing and recreating its store first.
     *
     * @param mnemonic the device's twelve words.
     * @param databaseFile `WalletPaths.bdkDatabaseFile`. Passed through
     *   [BdkStore.prepare], which refuses a path outside `bdk_store/` — the
     *   fence that stops this recursive delete from reaching the seed blob.
     * @throws java.io.IOException if the store directory cannot be prepared.
     * @throws org.bitcoindevkit.Bip39Exception if the mnemonic does not parse.
     */
    fun open(mnemonic: String, network: WalletNetwork, databaseFile: File): BdkWallet {
        val bdkNetwork = network(network)
        val databasePath = BdkStore.prepare(databaseFile)

        var connection: Connection? = null
        try {
            // `use` on all four, and the two secret-bearing ones are the reason.
            //
            // ARC frees these at the end of `didStartBDK` on iOS. UniFFI's
            // Kotlin bindings free the Rust object from a `java.lang.ref.Cleaner`
            // instead, at an unspecified time — so a dropped reference to a
            // `Mnemonic` or a `DescriptorSecretKey` is the **seed and the BIP32
            // root key sitting in native heap for an unbounded period**, on a
            // platform where the process is routinely killed and its memory
            // handed back to the system. That is a longer exposure than iOS
            // has, on exactly the material BIT-8 rule 1 is about, and it is the
            // same class of hazard as `ManagedNode.close` — except the thing
            // being held is secret rather than a file handle.
            //
            // Closing after `Wallet(...)` is safe rather than a use-after-free
            // for the reason given in `BdkSyncPort`: UniFFI lowers every object
            // argument through `uniffiClonePointer()`, so the wallet holds its
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

                            val store = Connection(databasePath.absolutePath)
                            connection = store

                            return BdkWallet(
                                wallet = Wallet(external, internal, bdkNetwork, store),
                                connection = store,
                                accountXpub = accountXpub,
                            )
                        }
                    }
                }
            }
        } catch (failure: Exception) {
            // iOS's `clearBdkWalletReferences()` on a failed start. The store is
            // a native handle on a SQLite file; leaving it to the cleaner means
            // the next start's `BdkStore.prepare` may be deleting a directory
            // something still has open.
            runCatching { connection?.close() }
            throw failure
        }
    }
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
 */
class BdkOnchainWalletHolder(
    private val mnemonic: () -> String?,
    private val network: WalletNetwork,
    private val databaseFile: File,
    private val electrumUrl: String,
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

            current = BdkWalletFactory.open(words, network, databaseFile)
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
     * The sync sequence for whatever wallet is open, bound to [scans].
     *
     * Returned star-projected so `di/WalletModule` can hold one: `:app` cannot
     * name `org.bitcoindevkit.Wallet`, because `:core:wallet-ldk` depends on
     * bdk-android with `implementation`. Nothing is lost — `fullScan` and
     * `lightSync` both return `Boolean`.
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
        ),
        scans = scans,
        closures = closures,
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

    private fun closeLocked() {
        // Wallet first, for the ordering `BdkWallet.close` states; the Electrum
        // client holds no reference to either and goes last.
        _opened.value = false
        runCatching { current?.close() }
        current = null
        runCatching { electrum?.close() }
        electrum = null
    }
}
