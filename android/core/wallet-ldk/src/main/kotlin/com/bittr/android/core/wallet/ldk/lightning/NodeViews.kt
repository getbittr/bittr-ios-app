package com.bittr.android.core.wallet.ldk.lightning

import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint

/**
 * ldk-node's node surface, as plain data this module may reason about.
 *
 * ## Why these types exist at all, when ldk-node's are already data classes
 *
 * UniFFI generates `ChannelDetails`, `PeerDetails`, `PaymentDetails` and
 * `BalanceDetails` as ordinary Kotlin data classes, so a test *could* construct
 * them on the JVM — `LdkNodeConfigTest` does exactly that with `BuilderInterface`
 * and its records. The reason the decisions below do not name them anyway is
 * `WalletLayeringGuardTest`'s rule, and the rule is right for a reason this
 * package makes concrete: `ChannelDetails` reaches `OutPoint`, `PaymentKind`
 * reaches `ConfirmationStatus` and `LspFeeLimits`, and every one of those is a
 * type whose *next* version can change under us. A decision about how much money
 * the user may spend should not recompile because ldk-node added a field.
 *
 * So the mapping lives in `adapter/LdkNodeSurface`, is a file of field copies
 * with no branches worth arguing about, and is itself JVM-tested by
 * `LdkNodeSurfaceTest` — which is the part that would otherwise be untestable.
 *
 * ## What was left out, and why that is the interesting half
 *
 * These views carry only what a *decision* reads. `ChannelDetails` has 30-odd
 * fields; six of them decide the number the user sees next to their on-chain
 * balance, and those six are here. Adding a field because it exists upstream is
 * how a view type becomes a second copy of the binding with none of its
 * guarantees.
 */
data class ChannelView(
    /** `ChannelDetails.channelId`. The id the *balances* are keyed by — see [ClosureBalances]. */
    val channelId: String,

    /**
     * `ChannelDetails.userChannelId`.
     *
     * Distinct from [channelId] and not interchangeable: `closeChannel` and
     * `forceCloseChannel` take the *user* channel id, while
     * `LightningBalance.channelId` is the other one. iOS's `closeChannel`
     * signature says `userChannelId: ChannelId` and both are `String` after
     * UniFFI, so nothing but this comment stands between the two.
     */
    val userChannelId: String,

    val counterpartyNodeId: String,

    /**
     * The channel's funding output, or null before it is known.
     *
     * What `LoadWalletData.swift:24–27` caches, and what
     * `ChannelClosureScan.shouldScan` later asks about.
     */
    val fundingTxo: TxOutpoint?,

    val channelValueSats: ULong,
    val outboundCapacityMsat: ULong,
    val inboundCapacityMsat: ULong,

    /** Nullable upstream, and the null is load-bearing — see [ChannelBalance]. */
    val unspendablePunishmentReserveSats: ULong?,

    val counterpartyUnspendablePunishmentReserveSats: ULong,

    /** `isChannelReady`. What `getActiveChannel()` selects on (`QuestionViewController.swift:131–139`). */
    val isChannelReady: Boolean,

    /**
     * `isUsable`.
     *
     * Not the same as [isChannelReady] — a ready channel whose peer is
     * disconnected is not usable. iOS logs both when a Lightning send fails
     * (`SendLightning.swift:231–232`) and selects on `isChannelReady` alone, so
     * that asymmetry is ported rather than tidied.
     */
    val isUsable: Boolean,
)

/** `PeerDetails`, whole — it is four fields and all four are read. */
data class PeerView(
    val nodeId: String,
    val address: String,
    val isPersisted: Boolean,
    val isConnected: Boolean,
)

/** `PaymentStatus`. */
enum class PaymentStatusView { Pending, Succeeded, Failed }

/**
 * `ConfirmationStatus`: confirmed at a height and block time, or not yet.
 *
 * Only on-chain payments carry one. Home colours an unconfirmed row differently, and a
 * confirmed row is dated by its block rather than by its last update.
 */
sealed interface OnchainConfirmationView {
    data class Confirmed(val height: Int, val timestampSecs: Long) : OnchainConfirmationView
    data object Unconfirmed : OnchainConfirmationView
}

/** `PaymentDirection`. */
enum class PaymentDirectionView { Inbound, Outbound }

/**
 * `PaymentKind`, reduced to the three questions the app asks of it.
 *
 * iOS asks exactly these, as computed properties on the enum
 * (`PaymentKind.swift:13–63`), and each one is a `switch` that a careless port
 * flattens:
 *
 * - [transactionId] is the **txid for on-chain and the preimage for everything
 *   else**. Those are not the same kind of thing, and the app uses this value as
 *   a cache key and as the id it hands Bittr's API
 *   (`HandlePaymentNotification.swift:323`).
 * - [stableId] is the **txid for on-chain and the payment hash for everything
 *   else** — the hash, not the preimage, because the preimage is nil until the
 *   payment settles and a cache key that changes on settlement is a cache miss
 *   on the one read that mattered. iOS records that history in `cacheIDs`.
 * - [isBolt12] is a metric label (`HandlePaymentNotification.swift:382`).
 *
 * Modelling it as a sealed hierarchy rather than as three nullable strings keeps
 * the `when` exhaustive: a seventh `PaymentKind` upstream becomes a compile error
 * in [com.bittr.android.core.wallet.ldk.adapter.LdkNodeSurface] — the one place
 * equipped to classify it — instead of a silent `null` id.
 */
sealed interface PaymentKindView {

    /** iOS's `transactionID`. */
    val transactionId: String?

    /** iOS's `stableID`. */
    val stableId: String?

    /** iOS's `isOnchain`. */
    val isOnchain: Boolean get() = false

    /** iOS's `isBolt12`. */
    val isBolt12: Boolean get() = false

    /**
     * @param confirmation `PaymentKind.onchain(txid:status:)`'s status. iOS reads it in
     *   `createTransaction` for the row's timestamp and height; defaulted so a caller
     *   that only cares about the txid does not have to invent one.
     */
    data class Onchain(
        val txId: String,
        val confirmation: OnchainConfirmationView = OnchainConfirmationView.Unconfirmed,
    ) : PaymentKindView {
        override val transactionId: String get() = txId
        override val stableId: String get() = txId
        override val isOnchain: Boolean get() = true
    }

    /** The BOLT11 family: plain, and the LSPS2 just-in-time variant. */
    sealed interface Bolt11Like : PaymentKindView {
        val hash: String
        val preimage: String?
        override val transactionId: String? get() = preimage
        override val stableId: String get() = hash
    }

    data class Bolt11(
        override val hash: String,
        override val preimage: String?,
    ) : Bolt11Like

    /**
     * A payment received over a channel the LSP opened to deliver it.
     *
     * This is the receive path the issue calls out, and it arrives here rather
     * than as a separate API: the app never asks for a JIT channel, it
     * configures `setLiquiditySourceLsps2` at build time
     * (`BitcoinManager.swift:169–173`, ported in `LdkNodeConfig`) and then
     * receives an ordinary BOLT11 invoice. ldk-node opens the channel, takes its
     * fee out of the incoming amount, and reports the payment back as
     * `Bolt11Jit` with [counterpartySkimmedFeeMsat] set.
     *
     * **The skimmed fee is why this is not just `Bolt11`.** The user asked for an
     * invoice of N and received N minus the LSP's cut. `PaymentDetails.amountMsat`
     * is the amount that arrived, so the balance is right either way — but any
     * screen that reconciles "what I invoiced" against "what I got" has to be able
     * to see the difference, and it cannot if the adapter maps this to [Bolt11].
     */
    data class Bolt11Jit(
        override val hash: String,
        override val preimage: String?,
        val counterpartySkimmedFeeMsat: ULong?,
    ) : Bolt11Like

    /**
     * BOLT12, offer or refund.
     *
     * **[hash] is nullable here and not in the BOLT11 cases, and that is
     * upstream's doing, not a defensive `?`.** A BOLT12 payment starts from an
     * offer; the payment hash does not exist until the recipient returns an
     * invoice, so ldk-node declares `PaymentKind.Bolt12Offer.hash` as optional
     * where `Bolt11.hash` is not.
     *
     * The consequence is visible in [PaymentView.cacheId]: a BOLT12 payment in
     * flight has no [stableId] and falls back to the payment id. iOS has the
     * same fallback (`PaymentKind.swift:70–72`) for the same reason.
     */
    data class Bolt12(
        val hash: String?,
        val preimage: String?,
        /** Offer or refund. Both are BOLT12 and the app distinguishes them nowhere else. */
        val isRefund: Boolean,
    ) : PaymentKindView {
        override val transactionId: String? get() = preimage
        override val stableId: String? get() = hash
        override val isBolt12: Boolean get() = true
    }

    data class Spontaneous(
        val hash: String,
        val preimage: String?,
    ) : PaymentKindView {
        override val transactionId: String? get() = preimage
        override val stableId: String get() = hash
    }
}

/**
 * `PaymentDetails`, plus the three classifications iOS hangs off it
 * (`Extensions/PaymentDetails.swift:13–35`).
 *
 * The classifications are properties here rather than free functions because
 * every one of them is a conjunction that reads as obvious and is not:
 * [isPendingOutbound] in particular has an amount test in it that has nothing to
 * do with direction, and dropping it puts zero-value rows in the user's
 * transaction history.
 */
data class PaymentView(
    val id: String,
    val kind: PaymentKindView,
    val amountMsat: ULong?,
    val feePaidMsat: ULong?,
    val direction: PaymentDirectionView,
    val status: PaymentStatusView,
    /**
     * `PaymentDetails.latestUpdateTimestamp`, in seconds. What iOS dates an unconfirmed
     * on-chain row by (`Transaction.swift:163`). Defaulted for the fixtures that predate it.
     */
    val latestUpdateTimestampSecs: Long = 0L,
) {

    /** `hasSucceeded()`. */
    val hasSucceeded: Boolean get() = status == PaymentStatusView.Succeeded

    /**
     * `isPendingOutbound()`.
     *
     * The amount clause is iOS's and it is doing real work: an outbound payment
     * that is pending with **neither** an amount nor a fee yet is a payment
     * ldk-node has recorded but not priced, and showing it lists a transaction of
     * zero sats in the user's history. Note iOS divides by 1000 before the
     * comparison — `Int(amountMsat/1000) > 0` — so a payment of 999 msat or less
     * does not count. That is sub-satoshi dust and the truncation is deliberate;
     * porting it as `amountMsat > 0` would resurrect exactly the rows the clause
     * exists to hide.
     */
    val isPendingOutbound: Boolean
        get() = status == PaymentStatusView.Pending &&
            direction == PaymentDirectionView.Outbound &&
            ((amountMsat ?: 0uL) / 1000uL > 0uL || (feePaidMsat ?: 0uL) / 1000uL > 0uL)

    /** `isUnconfirmedOnchainInbound()`. */
    val isUnconfirmedOnchainInbound: Boolean
        get() = status == PaymentStatusView.Pending &&
            kind.isOnchain &&
            direction == PaymentDirectionView.Inbound

    /**
     * The key this payment's cached data is written under — iOS's `cacheID`
     * (`PaymentKind.swift:70–72`).
     */
    val cacheId: String get() = kind.stableId ?: id
}

/**
 * The first channel that is ready — iOS's `getActiveChannel()`
 * (`QuestionViewController.swift:131–139`).
 *
 * "First", not "the one with the most capacity" and not "the only one": iOS
 * returns the first `isChannelReady` channel in `listChannels()` order and every
 * balance and send-limit screen reads that one. The app is single-channel in
 * practice, so the choice rarely bites — but a wallet that has just force-closed
 * one channel and opened another can hold two, and taking the second would show
 * a balance from a channel the rest of the app is not using.
 *
 * Ported exactly, including the order dependence, because changing it changes
 * which number the user sees.
 */
fun List<ChannelView>.activeChannel(): ChannelView? = firstOrNull { it.isChannelReady }

/**
 * The funding txids of every channel in this list — iOS's
 * `listChannels().compactMap { $0.fundingTxo?.txid }` (`BDKManager.swift:492`).
 *
 * **Every channel, not only the ready ones**, which is the one way this differs
 * from [activeChannel] above and the difference that matters. A channel that is
 * still pending is a channel whose funding output has not been spent by a
 * closing transaction; leaving it out would tell
 * [com.bittr.android.core.wallet.ldk.onchain.ChannelClosureScan] that a channel
 * which is *opening* has closed, and start the scan on it after every sync for
 * as long as it takes to confirm.
 *
 * One function and not two identical `mapNotNull`s, because it now has two
 * callers that have to agree. [WalletBalanceSnapshot.openChannelFundingTxIds] is
 * one — the home screen's read — and the lambda `WalletModule` hands
 * `ChannelClosureRecorder` is the other, on the sync's own thread. Both answer
 * "which funding transactions are still backing a live channel", and a copy that
 * drifted would let the balance and the closure scan disagree about whether a
 * channel has closed.
 */
fun List<ChannelView>.openChannelFundingTxIds(): List<String> = mapNotNull { it.fundingTxo?.txId }
