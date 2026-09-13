package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.WalletNetwork
import com.bittr.android.core.wallet.ldk.onchain.BdkStore
import com.bittr.android.core.wallet.ldk.onchain.DescriptorXpub
import com.bittr.android.core.wallet.ldk.onchain.FullScanParameters
import com.bittr.android.core.wallet.ldk.onchain.LightSyncParameters
import com.bittr.android.core.wallet.ldk.onchain.OnchainSyncPort
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
