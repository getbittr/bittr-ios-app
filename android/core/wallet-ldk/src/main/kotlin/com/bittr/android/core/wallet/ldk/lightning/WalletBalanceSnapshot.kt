package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint

/**
 * The three lists a [WalletBalanceSnapshot] is made of, taken from one node.
 *
 * A record rather than three return values because that is the guarantee it
 * carries: everything in it was read through the *same* `Node` handle, in one
 * block, so no two fields can describe different wallets. See
 * [WalletBalanceSnapshot]'s class comment for why that is a hazard on Android
 * rather than a tidiness argument, and [LightningNodePort.readWalletState] for
 * the contract that produces it.
 *
 * [balances] is non-null here, unlike [LightningNodePort.listBalances]. The
 * nullable case is the whole reading: no node, no [WalletNodeReading]. Carrying
 * the null inwards would put "there is no node" and "the node reports nothing"
 * back in the same value, which is what [WalletBalanceSnapshot.ldkSpendableSats]
 * exists to keep apart.
 */
data class WalletNodeReading(
    /** `listChannels()`. */
    val channels: List<ChannelView>,
    /** `listBalances()`, which answered. */
    val balances: BalanceView,
    /** `listPayments()`. */
    val payments: List<PaymentView>,
    /**
     * `status().currentBestBlock.height` — iOS's `bittrWallet.currentHeight`, which the
     * history and the transaction screen count confirmations from. Null when the status
     * read failed; nothing about the balance depends on it.
     */
    val bestBlockHeight: Int? = null,
)

/**
 * One consistent read of the wallet's money, and the cache writes that go with
 * it.
 *
 * Port of `loadWalletData()` (`LoadWalletData.swift:13–80`) — the computation,
 * not the UIKit. iOS's function interleaves four `CacheManager` writes with the
 * arithmetic and then applies the result on the main thread; here the arithmetic
 * produces a value and the writes are named in it, so the caller performs them
 * and a test can assert which ones a given wallet state asks for.
 *
 * ## Why this is one object rather than four calls
 *
 * iOS's first comment says it:
 *
 * > Take the node handle up front — everything below reads through it, and
 * > bailing halfway (after caching a txo ID, before any of the balances) leaves
 * > the cache describing a snapshot we never applied.
 *
 * On Android that hazard is worse, not better. `NodeLifecycle.current` can go
 * null between two statements — a foreground-service restart or a wipe does it
 * routinely — so a caller reading channels, then balances, then payments through
 * three separate port calls can get two thirds of a snapshot and a null. [of]
 * takes the three lists it needs as arguments for that reason: assembling them
 * is one block in the caller, and this function cannot be the place the wallet
 * disappears.
 *
 * That block is [LightningNodePort.readWalletState], which takes the node handle
 * once and returns a [WalletNodeReading] or null. [WalletBalanceReader] is the
 * production caller that joins the two and performs the cache writes named below.
 *
 * Proved by `WalletBalanceSnapshotTest`.
 */
data class WalletBalanceSnapshot(

    /** `bittrWallet.satoshisLightning`. See [ChannelBalance]. */
    val satoshisLightning: Long,

    /** `bittrWallet.satoshisOnchain` — `balances.totalOnchainBalanceSats`. */
    val satoshisOnchain: Long,

    /**
     * `bittrWallet.satoshisOnchainSpendable` — `balances.spendableOnchainBalanceSats`.
     *
     * LDK's authority figure for the drain clamp. It is net of the anchor-channel
     * reserve, which is the whole reason it differs from what BDK would say.
     */
    val satoshisOnchainSpendable: Long,

    /** `bittrWallet.pendingBalancesFromChannelClosures`. See [ClosureBalances]. */
    val pendingClosureSatoshis: Long,

    /** `bittrWallet.allTransactions.count` — the only thing the light-sync comparison uses. */
    val paymentCount: Int,

    /**
     * The active channel's funding output, to cache
     * (`CacheManager.storeTxoID` + `storeChannelFundingOutpoint`), or null when
     * there is no active channel or it has no funding txo yet.
     *
     * Null means **do not write**, not "write null". iOS reaches those two calls
     * only inside `if let channelTxo`, and clearing a cached funding outpoint
     * because a read happened while the channel was still pending would lose the
     * outpoint `ChannelClosureScan` later needs to find the closing transaction.
     */
    val channelFundingOutpointToStore: TxOutpoint?,

    /** `CacheManager.storeChannelClosureTxIDs(txIDs:)`. Written unconditionally, empty list included. */
    val closureSpendingTxIds: List<String>,

    /**
     * `CacheManager.removeChannelFundingOutpoint()` — iOS's
     * `if pendingBalancesFromChannelClosures > 0`.
     *
     * A force-close has happened, so there is no longer a live funding outpoint
     * to watch. Dropping it is what stops [com.bittr.android.core.wallet.ldk.onchain.ChannelClosureScan]
     * scanning after every sync for the rest of the wallet's life.
     */
    val clearChannelFundingOutpoint: Boolean,

    /**
     * Funding txids of every channel currently open.
     *
     * This is the argument `ChannelClosureScan.shouldScan` has been waiting for
     * since `3371cb99` — `OnchainSync` could not supply it because it had no
     * channel list. iOS calls `storeChannelClosureTxIDIfFound()` at the end of
     * both the full scan and the light sync (`BDKManager.swift:301`, `:369`);
     * on Android the sync sequence takes this from the latest snapshot.
     *
     * Every channel, not only the ready ones: a channel that is still pending is
     * a channel whose funding transaction has not been spent by a closure, and
     * treating it as closed would start the scan early.
     */
    val openChannelFundingTxIds: List<String>,
) {

    /**
     * Whether anything the light sync watches has moved
     * (`BitcoinManager.swift:496`).
     *
     * iOS compares three fields against the previously applied snapshot — on-chain
     * total, pending closures, payment count — and reloads the UI only if one
     * differs. Lightning balance is deliberately *not* among them, which is iOS's
     * choice and is ported as-is: a Lightning receive changes the payment count
     * too, so the third clause already catches it.
     *
     * @param previous the last applied snapshot, or null if none has been
     *   applied. Null is a change: there is nothing on screen yet.
     */
    fun differsFrom(previous: WalletBalanceSnapshot?): Boolean {
        if (previous == null) return true
        return satoshisOnchain != previous.satoshisOnchain ||
            pendingClosureSatoshis != previous.pendingClosureSatoshis ||
            paymentCount != previous.paymentCount
    }

    companion object {

        /**
         * @param channels `listChannels()`.
         * @param balances `listBalances()`.
         * @param payments `listPayments()`. Only its size is read here; the rows
         *   themselves belong to the transaction history, which is `:app`'s.
         */
        fun of(
            channels: List<ChannelView>,
            balances: BalanceView,
            payments: List<PaymentView>,
        ): WalletBalanceSnapshot {
            val pendingClosure = ClosureBalances.pendingClosureSatoshis(
                balances = balances,
                openChannelIds = channels.map { it.channelId },
            )

            return WalletBalanceSnapshot(
                satoshisLightning = ChannelBalance.spendableSatoshis(channels),
                satoshisOnchain = balances.totalOnchainBalanceSats.toLong(),
                satoshisOnchainSpendable = balances.spendableOnchainBalanceSats.toLong(),
                pendingClosureSatoshis = pendingClosure,
                paymentCount = payments.size,
                channelFundingOutpointToStore = channels.activeChannel()?.fundingTxo,
                closureSpendingTxIds = ClosureBalances.spendingTxIds(
                    balances.pendingBalancesFromChannelClosures,
                ),
                clearChannelFundingOutpoint = pendingClosure > 0L,
                // The shared definition, not a `mapNotNull` of its own: the sync
                // loop reads the same thing through the same function so the two
                // cannot drift. See `List<ChannelView>.openChannelFundingTxIds`.
                openChannelFundingTxIds = channels.openChannelFundingTxIds(),
            )
        }
    }
}

/**
 * What `OnchainDrainClamp.clampToLdkSpendable` must be given.
 *
 * The extension is on the **nullable** snapshot on purpose. `OnchainDrainClamp`'s
 * contract is that `null` and `0` mean different things — no balance read has
 * happened yet, versus a read that found nothing spendable — and its class
 * comment spells out how a one-character `?: 0` turns the first into the second
 * and stops the user emptying their own wallet for the whole window between node
 * start and the first read.
 *
 * Making "no snapshot yet" the only way to produce `null` puts that distinction
 * in the type system instead of in a convention: a caller holding
 * `WalletBalanceSnapshot?` cannot reach a `Long` without saying what it wants the
 * absent case to be.
 *
 * `coerceAtLeast(0)` is **not** applied here. The clamp takes a signed value and
 * floors it itself, and iOS carries the figure as `Int` and clamps at the call
 * sites rather than at the source — duplicating the floor would hide a negative
 * that should be visible to whatever reports it.
 */
fun WalletBalanceSnapshot?.ldkSpendableSats(): Long? = this?.satoshisOnchainSpendable

/**
 * Whether the wallet may be deleted from the device.
 *
 * Port of `channelsFullyClosedAndSwept()` (`BitcoinManager.swift:449–455`), and
 * the single most expensive decision in this package to get wrong. iOS's comment
 * is the specification:
 *
 * > Returns true only when there are no open channels AND no closed-channel funds
 * > are still settling on-chain. Wiping before this is true deletes the LDK
 * > channel state (channel monitors) needed to sweep those funds — and a BIP39
 * > seed alone CANNOT reconstruct it. For a force-closed channel the to_local
 * > output is locked behind a CSV delay (~1 day) and only swept once it expires,
 * > so wiping early means permanent loss.
 * >
 * > If the node isn't running we can't verify the state, so we return false
 * > (refuse the wipe) rather than risk it.
 *
 * That last paragraph is why [balances] is nullable and why null answers *false*.
 * iOS reaches it through `guard let node = self.ldkNode else { return false }`.
 * On Android the node is null far more often — process death, service restart,
 * a wipe that has already begun — so the case iOS treats as unusual is the one
 * this function will see most, and the fail-safe direction has to be the one
 * that costs a retry rather than the one that costs the user's coins.
 *
 * Proved by `WipeSafetyTest`.
 */
object WipeSafety {

    /**
     * @param channels `listChannels()`, or null if there is no node to ask.
     * @param balances `listBalances()`, or null if there is no node to ask.
     * @return true only when a wipe is safe. Every uncertain case is false.
     */
    fun channelsFullyClosedAndSwept(
        channels: List<ChannelView>?,
        balances: BalanceView?,
    ): Boolean {
        // No node, no answer, no wipe.
        if (channels == null || balances == null) return false

        return channels.isEmpty() &&
            balances.totalLightningBalanceSats == 0uL &&
            balances.pendingBalancesFromChannelClosures.isEmpty()
    }
}
