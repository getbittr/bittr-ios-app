package com.bittr.android.core.wallet.ldk.lightning

/**
 * There is no node to ask.
 *
 * iOS's `WalletError.walletNotInitiated`, thrown from the guards in
 * `sendPayment`, `syncWallets` and friends (`BitcoinManager.swift:600`, `:616`,
 * `:633`, `:647`). The read paths return an empty list or null instead, and that
 * asymmetry is iOS's: a balance that cannot be read shows as nothing, but a
 * payment that cannot be sent has to fail loudly rather than report success.
 *
 * Note the call sites iOS force-unwraps — `connect`, `closeChannel`,
 * `forceCloseChannel`, `connectOpenChannel`, `receivePayment` — crash instead.
 * On Android they throw this, because a foreground-service restart makes a null
 * node an ordinary event rather than a programming error, and `NodeLifecycle`'s
 * own comment already says callers must tolerate `current` being null.
 */
class NodeUnavailableException(
    message: String = "No Lightning node is running.",
) : Exception(message)

/** A BOLT11 invoice description — `Bolt11InvoiceDescription`. */
sealed interface Bolt11DescriptionView {

    /** `Bolt11InvoiceDescription.direct` — `receivePayment` (`BitcoinManager.swift:588`). */
    data class Direct(val description: String) : Bolt11DescriptionView

    /** `Bolt11InvoiceDescription.hash` — `receivePaymentWithHash` (`BitcoinManager.swift:594`). */
    data class Hash(val hash: String) : Bolt11DescriptionView
}

/**
 * The routing limits a BOLT12 send is given — `RouteParametersConfig`.
 *
 * Four numbers, all of which cost the user money if they are wrong, so they are
 * a type with a test rather than a literal in an adapter. See [Bolt12SendPlan].
 */
data class RouteLimitsView(
    val maxTotalRoutingFeeMsat: ULong,
    val maxTotalCltvExpiryDelta: UInt,
    val maxPathCount: UByte,
    val maxChannelSaturationPowerOfHalf: UByte,
)

/**
 * The node's channel, peer and payment surface, with no ldk-node type in it.
 *
 * The seam this issue hangs off `LdkManagedNode.node`, exactly as
 * `ManagedNode`'s comment asks: `ManagedNode` stays at four methods so
 * `NodeLifecycleTest`'s fakes stay small, and everything below lives here
 * instead. `adapter/LdkNodeSurface` is the implementation and is the only file
 * that knows a `Node` exists.
 *
 * ## Reads and writes fail differently, on purpose
 *
 * Every read returns an empty collection or null when there is no node, matching
 * iOS's `guard let node ... else { return [] }`. Every write throws
 * [NodeUnavailableException]. The split is not stylistic: a balance screen that
 * renders zeroes for a second while the node restarts is a cosmetic problem, and
 * a `closeChannel` that silently does nothing is a channel the user believes they
 * closed.
 */
interface LightningNodePort {

    // ---- Reads. Empty or null when the node is gone. ----

    /** `listPeers()` (`BitcoinManager.swift:420–426`). */
    fun listPeers(): List<PeerView>

    /** `listChannels()` (`BitcoinManager.swift:433–436`). */
    fun listChannels(): List<ChannelView>

    /** `listPayments()` (`BitcoinManager.swift:428–431`). */
    fun listPayments(): List<PaymentView>

    /** `payment(paymentId:)` — iOS's `getPaymentDetails` (`BitcoinManager.swift:659–662`). */
    fun payment(paymentId: String): PaymentView?

    /**
     * `listBalances()`.
     *
     * Null means no node. It does **not** mean zero — see
     * [WalletBalanceSnapshot.ldkSpendableSats] for what collapsing the two costs.
     */
    fun listBalances(): BalanceView?

    /**
     * [listChannels], [listBalances] and [listPayments] through **one** node
     * handle — iOS's "take the node handle up front" (`LoadWalletData.swift:15`).
     *
     * Not sugar over the three reads above, and a default implementation calling
     * them in turn would defeat the point. `NodeLifecycle.current` can go null
     * between two statements, so three separate reads can return two thirds of a
     * wallet and an empty list, and nothing downstream can tell that apart from a
     * wallet that really has no channels. [WalletBalanceSnapshot]'s class comment
     * has the full argument; this is the method that honours it, which is why it
     * belongs on the port — the port is the only thing that holds the handle.
     *
     * Null means **no node**, exactly as [listBalances] does, and for the same
     * reason: a caller must be able to tell "nothing was read" from "nothing is
     * there". It never means an empty wallet — that is a [WalletNodeReading] with
     * empty lists and zeroed balances.
     */
    fun readWalletState(): WalletNodeReading?

    /**
     * `syncWallets()` (`BitcoinManager.swift`) — sync the node's on-chain and Lightning
     * wallets now, so a payment just sent shows up in [listPayments] without waiting for
     * the background sync.
     *
     * @throws NodeUnavailableException when no node is running.
     */
    fun syncWallets()

    // ---- Peers. ----

    /** `connect(nodeId:address:persist:)` (`BitcoinManager.swift:457–463`). */
    fun connect(nodeId: String, address: String, persist: Boolean)

    /** `disconnect(nodeId:)` (`BitcoinManager.swift:324`). */
    fun disconnect(nodeId: String)

    // ---- Channels. ----

    /**
     * `openChannel` — iOS's `connectOpenChannel` (`BitcoinManager.swift:733–749`).
     *
     * @return the user channel id, which is what [closeChannel] and
     *   [forceCloseChannel] take.
     */
    fun openChannel(
        nodeId: String,
        address: String,
        channelAmountSats: ULong,
        pushToCounterpartyMsat: ULong?,
    ): String

    /** `closeChannel(userChannelId:counterpartyNodeId:)` (`BitcoinManager.swift:726–731`). */
    fun closeChannel(userChannelId: String, counterpartyNodeId: String)

    /**
     * `forceCloseChannel(userChannelId:counterpartyNodeId:reason:)`
     * (`BitcoinManager.swift:751–755`).
     *
     * iOS passes `reason: ""` and carries a TODO saying the call does not work
     * against the Bittr node because it sits in `trusted_peers_no_reserve`. Both
     * are ported: the empty default keeps the signature honest, and the caveat is
     * recorded here because it is the kind of thing that gets rediscovered
     * expensively during a real force-close.
     */
    fun forceCloseChannel(userChannelId: String, counterpartyNodeId: String, reason: String = "")

    /**
     * `updateChannelConfig(userChannelId:counterpartyNodeId:channelConfig:)`.
     *
     * **No iOS caller exists.** `connectOpenChannel` accepts a `channelConfig`
     * parameter and then passes `nil` to `openChannel`
     * (`BitcoinManager.swift:738`, `:746`) — the argument is ignored, which is a
     * live iOS bug rather than a design to copy, and `updateChannelConfig` is
     * never called at all.
     *
     * So this forwards ldk-node's own `ChannelConfig` and takes it as an opaque
     * [Any], not as a view type. Inventing a `ChannelConfigView` would mean
     * choosing defaults for `forwardingFeeProportionalMillionths`,
     * `cltvExpiryDelta` and `maxDustHtlcExposure` with no iOS values to pin them
     * to — a fund-handling decision made by an Android port on its own, which is
     * the thing BIT-6 says to flag rather than write. When a caller appears, the
     * values it needs get a view type and a test alongside.
     */
    fun updateChannelConfig(userChannelId: String, counterpartyNodeId: String, channelConfig: Any)

    // ---- Payments. ----

    /**
     * `bolt11Payment().receive(...)` — iOS's `receivePayment` and
     * `receivePaymentWithHash` (`BitcoinManager.swift:587–597`), which differ only
     * in their [Bolt11DescriptionView].
     *
     * ## The LSPS2 just-in-time path is configured and not used
     *
     * ldk-node 0.7 has `receiveViaJitChannel`, and the node is built with
     * `setLiquiditySourceLsps2` (`BitcoinManager.swift:169–173`, ported in
     * `LdkNodeConfig`). It would be easy to read those two facts together and
     * conclude the JIT receive is the path to port. It is not: iOS calls plain
     * `receive` everywhere, and the builder comment says why in as many words —
     * the liquidity source is configured to lift LDK's 10% channel-capacity limit
     * for receives, *"though we're not yet using the full LSP2 specification"*.
     *
     * Switching Android to `receiveViaJitChannel` would change what the
     * counterparty is allowed to skim from an incoming payment and would make the
     * two platforms produce different invoices for the same request. That is a
     * product and fund-handling deviation, so it is flagged here and left
     * unported rather than quietly introduced.
     *
     * @return the invoice, as the BOLT11 string. The `Bolt11Invoice` object is a
     *   native handle and does not cross this seam.
     */
    fun receiveBolt11(
        amountMsat: ULong,
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String

    /**
     * `bolt11Payment().receiveVariableAmount(...)` — iOS's `getZeroInvoice`
     * (`ReceiveLightning.swift:15–47`), the invoice Receive shows when no amount was entered.
     * The payer chooses the amount.
     *
     * @return the invoice, as the BOLT11 string.
     */
    fun receiveBolt11VariableAmount(
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String

    /**
     * `bolt11Payment().send(invoice:routeParameters:)`
     * (`BitcoinManager.swift:599–602`).
     *
     * @param invoice the BOLT11 string. Parsing it is the adapter's job —
     *   `Bolt11Invoice.fromStr` is an FFI call and its failure is
     *   `String.bolt11Invoice()`'s `nil` on iOS (`BitcoinManager.swift:790–797`).
     * @param routeLimits null for iOS's `routeParameters: nil` — ldk-node's
     *   defaults. Only the BOLT12 path sets them; see [Bolt12SendPlan].
     * @return the payment hash.
     */
    fun sendBolt11(invoice: String, routeLimits: RouteLimitsView?): String

    /**
     * `bolt11Payment().sendUsingAmount(...)` — iOS's `sendZeroAmountPayment`
     * (`BitcoinManager.swift:604–607`), for an invoice that names no amount.
     */
    fun sendBolt11UsingAmount(invoice: String, amountMsat: ULong, routeLimits: RouteLimitsView?): String

    /**
     * `bolt12Payment().sendUsingAmount(...)` — iOS's `sendBolt12Payment`
     * (`BitcoinManager.swift:609–619`).
     *
     * @return the payment id.
     */
    fun sendBolt12UsingAmount(offer: String, amountMsat: ULong, routeLimits: RouteLimitsView): String
}
