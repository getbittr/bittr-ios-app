package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.BalanceSourceView
import com.bittr.android.core.wallet.ldk.lightning.BalanceView
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.EventPumpPort
import com.bittr.android.core.wallet.ldk.lightning.LightningBalanceView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.NodeUnavailableException
import com.bittr.android.core.wallet.ldk.lightning.PaymentDirectionView
import com.bittr.android.core.wallet.ldk.lightning.OnchainConfirmationView
import com.bittr.android.core.wallet.ldk.lightning.PaymentKindView
import com.bittr.android.core.wallet.ldk.lightning.PaymentStatusView
import com.bittr.android.core.wallet.ldk.lightning.PaymentView
import com.bittr.android.core.wallet.ldk.lightning.PeerView
import com.bittr.android.core.wallet.ldk.lightning.PendingSweepView
import com.bittr.android.core.wallet.ldk.lightning.RouteLimitsView
import com.bittr.android.core.wallet.ldk.lightning.WalletNodeReading
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.onchain.TxOutpoint
import org.lightningdevkit.ldknode.BalanceDetails
import org.lightningdevkit.ldknode.BalanceSource
import org.lightningdevkit.ldknode.Bolt11Invoice
import org.lightningdevkit.ldknode.Bolt11InvoiceDescription
import org.lightningdevkit.ldknode.ChannelConfig
import org.lightningdevkit.ldknode.ChannelDetails
import org.lightningdevkit.ldknode.Event
import org.lightningdevkit.ldknode.LightningBalance
import org.lightningdevkit.ldknode.Node
import org.lightningdevkit.ldknode.Offer
import org.lightningdevkit.ldknode.PaymentDetails
import org.lightningdevkit.ldknode.PaymentDirection
import org.lightningdevkit.ldknode.ConfirmationStatus
import org.lightningdevkit.ldknode.PaymentKind
import org.lightningdevkit.ldknode.PaymentStatus
import org.lightningdevkit.ldknode.PeerDetails
import org.lightningdevkit.ldknode.PendingSweepBalance
import org.lightningdevkit.ldknode.RouteParametersConfig

/**
 * [LightningNodePort] over whatever node [lifecycle] currently holds.
 *
 * The composition `:app` cannot write. `wallet-ldk` depends on
 * `ldk-node-android` with `implementation`, so `Node` is not on the app's
 * compile classpath and `di/WalletModule` could not name [LdkNodeSurface]'s
 * constructor even if the layering allowed it — the same reason
 * [LdkEventPumpRunner] is assembled here.
 *
 * ## A null [lifecycle] is a real case, not a defensive one
 *
 * It is the **unconfigured build**: `LdkEnvironmentConfig.fromBuildConfig()`
 * returned null, the app composed `SeedWalletService`, and there is no
 * `NodeLifecycle` anywhere in the process and never will be in this one. That
 * build still has to produce a [LightningNodePort] for the graph, and
 * [LightningNodePort]'s own contract already says what it should do: reads
 * answer empty or null, writes throw [NodeUnavailableException]. So the
 * unconfigured build gets a port that is permanently in the state a configured
 * one is in between a stop and a start, rather than a second implementation or
 * a nullable binding every caller has to check.
 *
 * That is not the same as hiding the difference. A caller that needs to know
 * whether this build has a node asks `LdkEnvironmentConfig`, which is the one
 * place that decides it; a caller that only wants to send a payment gets the
 * same exception either way, because "no node" is the same answer.
 *
 * `LightningNodePortTest` proves the no-node half on the JVM, which is the half
 * that does not need a native library; the forwarding half needs a device and
 * belongs to BIT-132's regtest suite.
 */
fun lightningNodePort(lifecycle: NodeLifecycle?): LightningNodePort =
    LdkNodeSurface { lifecycle?.current.ldkNode() }

/**
 * ldk-node's channel, peer and payment surface as a [LightningNodePort].
 *
 * The second half of the FFI boundary, after [LdkManagedNode]. Everything above
 * it — the balance arithmetic, the wipe guard, the reconnect, the event pump —
 * is in `lightning/` and names none of these types.
 *
 * ## The node is fetched per call, never held
 *
 * [node] is a function, not a field. `NodeLifecycle.current` can go null between
 * any two statements — a wipe, a foreground-service restart — and its own comment
 * says callers must tolerate that. Caching the node here would produce exactly
 * the bug `NodeLifecycle` was written to prevent: work continuing against a
 * `Node` the rest of the app has already let go of.
 *
 * ## Reads and writes fail differently
 *
 * [LightningNodePort]'s contract, and iOS's: reads answer empty/null when there
 * is no node, writes throw [NodeUnavailableException]. iOS force-unwraps on the
 * write side and crashes; on Android a null node is an ordinary event, so it is
 * a thrown exception the caller can act on.
 *
 * ## What is testable here, and what is not
 *
 * The **mapping** is — [LdkNodeMapping] below is pure field copying over UniFFI
 * records, which are plain Kotlin data classes, and `LdkNodeSurfaceTest`
 * constructs them on the JVM and asserts every branch. That is the same argument
 * `LdkNodeConfigTest` makes for `BuilderInterface`, and it matters most here
 * because [LdkNodeMapping.toView] for `PaymentKind` and `LightningBalance` has
 * real branches in it.
 *
 * The **calls** are not: `node.listBalances()` crosses into Rust. Those are
 * one-line forwards with nothing left to get wrong that review cannot see, and
 * proving them needs a running node — BIT-123's device work.
 */
class LdkNodeSurface(
    private val node: () -> Node?,
) : LightningNodePort {

    private fun require(operation: String): Node = node()
        ?: throw NodeUnavailableException(
            "Cannot $operation: no Lightning node is running. This is a teardown or a " +
                "service restart racing the call, not a programming error — see " +
                "NodeLifecycle.current.",
        )

    // ---- Reads. iOS's `guard let node ... else { return [] }`. ----

    override fun listPeers(): List<PeerView> =
        node()?.listPeers().orEmpty().map(LdkNodeMapping::toView)

    override fun listChannels(): List<ChannelView> =
        node()?.listChannels().orEmpty().map(LdkNodeMapping::toView)

    override fun listPayments(): List<PaymentView> =
        node()?.listPayments().orEmpty().map(LdkNodeMapping::toView)

    override fun payment(paymentId: String): PaymentView? =
        node()?.payment(paymentId)?.let(LdkNodeMapping::toView)

    override fun listBalances(): BalanceView? =
        node()?.listBalances()?.let(LdkNodeMapping::toView)

    /**
     * The one place in this class that reads [node] once and then uses it more
     * than once, and the only place that may.
     *
     * Every other read re-reads the field per call, which is right for them — see
     * the class comment. Here the requirement is the opposite and it is stronger:
     * the three lists have to describe one wallet at one moment, so the handle is
     * taken up front and the three FFI calls go through the local. A teardown
     * during them does not produce a mixed reading; UniFFI's `callCounter` holds
     * the handle open for an in-flight call and the next call throws, which
     * propagates to [com.bittr.android.core.wallet.ldk.lightning.WalletBalanceReader]'s
     * swallow rather than producing a half-read.
     */
    override fun readWalletState(): WalletNodeReading? {
        val node = node() ?: return null
        return WalletNodeReading(
            channels = node.listChannels().map(LdkNodeMapping::toView),
            balances = LdkNodeMapping.toView(node.listBalances()),
            payments = node.listPayments().map(LdkNodeMapping::toView),
            bestBlockHeight = runCatching { node.status().currentBestBlock.height.toInt() }.getOrNull(),
        )
    }

    override fun syncWallets() = require("sync the wallets").syncWallets()

    // ---- Peers. ----

    override fun connect(nodeId: String, address: String, persist: Boolean) =
        require("connect to $nodeId").connect(nodeId, address, persist)

    override fun disconnect(nodeId: String) =
        require("disconnect from $nodeId").disconnect(nodeId)

    // ---- Channels. ----

    /**
     * iOS's `connectOpenChannel` passes `channelConfig: nil` while *accepting* a
     * `channelConfig` argument it then ignores (`BitcoinManager.swift:738`,
     * `:746`). That is an iOS bug, not a design, so this signature does not have
     * the parameter at all rather than reproducing a silently-dropped one.
     */
    override fun openChannel(
        nodeId: String,
        address: String,
        channelAmountSats: ULong,
        pushToCounterpartyMsat: ULong?,
    ): String = require("open a channel to $nodeId").openChannel(
        nodeId = nodeId,
        address = address,
        channelAmountSats = channelAmountSats,
        pushToCounterpartyMsat = pushToCounterpartyMsat,
        channelConfig = null,
    )

    override fun closeChannel(userChannelId: String, counterpartyNodeId: String) =
        require("close channel $userChannelId").closeChannel(userChannelId, counterpartyNodeId)

    override fun forceCloseChannel(
        userChannelId: String,
        counterpartyNodeId: String,
        reason: String,
    ) = require("force-close channel $userChannelId")
        .forceCloseChannel(userChannelId, counterpartyNodeId, reason)

    /**
     * @param channelConfig must be a [ChannelConfig]. Typed as `Any` at the port
     *   for the reason [LightningNodePort.updateChannelConfig] gives: there is no
     *   iOS caller to pin a view type's defaults to, and inventing them would be a
     *   fund-handling decision made unilaterally.
     */
    override fun updateChannelConfig(
        userChannelId: String,
        counterpartyNodeId: String,
        channelConfig: Any,
    ) {
        val config = channelConfig as? ChannelConfig
            ?: throw IllegalArgumentException(
                "updateChannelConfig needs an ldk-node ChannelConfig, got " +
                    "${channelConfig::class.java.name}.",
            )
        require("update the config of channel $userChannelId")
            .updateChannelConfig(userChannelId, counterpartyNodeId, config)
    }

    // ---- Payments. ----

    /**
     * Plain `receive`, not `receiveViaJitChannel` — see
     * [LightningNodePort.receiveBolt11] for why that is a deliberate choice and
     * not an omission.
     *
     * The returned `Bolt11Invoice` is a native handle, so it is closed here and
     * only its string crosses the seam. `Node` objects get the same treatment in
     * [LdkManagedNode.close] and for the same reason: UniFFI frees from a
     * `Cleaner`, at an unspecified time.
     */
    override fun receiveBolt11(
        amountMsat: ULong,
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String {
        val ldkDescription = when (description) {
            is Bolt11DescriptionView.Direct ->
                Bolt11InvoiceDescription.Direct(description.description)
            is Bolt11DescriptionView.Hash ->
                Bolt11InvoiceDescription.Hash(description.hash)
        }
        val invoice = require("create an invoice")
            .bolt11Payment()
            .receive(amountMsat, ldkDescription, expirySecs)
        return invoice.use { it.toString() }
    }

    override fun receiveBolt11VariableAmount(
        description: Bolt11DescriptionView,
        expirySecs: UInt,
    ): String {
        val ldkDescription = when (description) {
            is Bolt11DescriptionView.Direct ->
                Bolt11InvoiceDescription.Direct(description.description)
            is Bolt11DescriptionView.Hash ->
                Bolt11InvoiceDescription.Hash(description.hash)
        }
        val invoice = require("create an invoice")
            .bolt11Payment()
            .receiveVariableAmount(ldkDescription, expirySecs)
        return invoice.use { it.toString() }
    }

    override fun sendBolt11(invoice: String, routeLimits: RouteLimitsView?): String =
        Bolt11Invoice.fromStr(invoice).use {
            require("send a payment").bolt11Payment().send(it, routeLimits?.toLdk())
        }

    override fun sendBolt11UsingAmount(
        invoice: String,
        amountMsat: ULong,
        routeLimits: RouteLimitsView?,
    ): String = Bolt11Invoice.fromStr(invoice).use {
        require("send a payment")
            .bolt11Payment()
            .sendUsingAmount(it, amountMsat, routeLimits?.toLdk())
    }

    override fun sendBolt12UsingAmount(
        offer: String,
        amountMsat: ULong,
        routeLimits: RouteLimitsView,
    ): String = Offer.fromStr(offer).use {
        require("send a BOLT12 payment").bolt12Payment().sendUsingAmount(
            offer = it,
            amountMsat = amountMsat,
            quantity = null,
            payerNote = null,
            routeParameters = routeLimits.toLdk(),
        )
    }

    private fun RouteLimitsView.toLdk() = RouteParametersConfig(
        maxTotalRoutingFeeMsat = maxTotalRoutingFeeMsat,
        maxTotalCltvExpiryDelta = maxTotalCltvExpiryDelta,
        maxPathCount = maxPathCount,
        maxChannelSaturationPowerOfHalf = maxChannelSaturationPowerOfHalf,
    )
}

/**
 * `nextEventAsync()` / `eventHandled()`, bound to whatever node is current.
 *
 * The node is read **once per [nextEvent] call**, which is iOS's per-iteration
 * binding (`BitcoinManager.swift:704–709`) expressed at the only place the loop
 * touches the node. A null here is what `EventPump` reports as
 * `EventPumpStop.NodeGone`.
 *
 * `nextEventAsync` is a genuine suspend function in ldk-node's Kotlin bindings,
 * so no dispatcher is needed: unlike `connect`, it does not block a thread while
 * it waits.
 */
class LdkEventPumpPort(
    private val node: () -> Node?,
) : EventPumpPort<Event> {

    override suspend fun nextEvent(): Event? = node()?.nextEventAsync()

    /**
     * Not guarded by a null check that throws: `EventPump` calls this after a
     * successful read, and if the node has gone in between there is nothing to
     * acknowledge and nothing the loop would do differently. The pump swallows
     * the failure and carries on to the next read, which reports `NodeGone`.
     */
    override fun eventHandled() {
        node()?.eventHandled()
    }
}

/**
 * ldk-node's records, as this module's views.
 *
 * Pure, and therefore the part of the adapter that gets a test. Internal rather
 * than private so `LdkNodeSurfaceTest` can drive each branch directly instead of
 * through a `Node` it cannot construct.
 */
internal object LdkNodeMapping {

    fun toView(peer: PeerDetails) = PeerView(
        nodeId = peer.nodeId,
        address = peer.address,
        isPersisted = peer.isPersisted,
        isConnected = peer.isConnected,
    )

    fun toView(channel: ChannelDetails) = ChannelView(
        channelId = channel.channelId,
        userChannelId = channel.userChannelId,
        counterpartyNodeId = channel.counterpartyNodeId,
        fundingTxo = channel.fundingTxo?.let { TxOutpoint(txId = it.txid, vout = it.vout) },
        channelValueSats = channel.channelValueSats,
        outboundCapacityMsat = channel.outboundCapacityMsat,
        inboundCapacityMsat = channel.inboundCapacityMsat,
        unspendablePunishmentReserveSats = channel.unspendablePunishmentReserve,
        counterpartyUnspendablePunishmentReserveSats =
            channel.counterpartyUnspendablePunishmentReserve,
        isChannelReady = channel.isChannelReady,
        isUsable = channel.isUsable,
    )

    fun toView(payment: PaymentDetails) = PaymentView(
        id = payment.id,
        kind = toView(payment.kind),
        amountMsat = payment.amountMsat,
        feePaidMsat = payment.feePaidMsat,
        direction = when (payment.direction) {
            PaymentDirection.INBOUND -> PaymentDirectionView.Inbound
            PaymentDirection.OUTBOUND -> PaymentDirectionView.Outbound
        },
        status = when (payment.status) {
            PaymentStatus.PENDING -> PaymentStatusView.Pending
            PaymentStatus.SUCCEEDED -> PaymentStatusView.Succeeded
            PaymentStatus.FAILED -> PaymentStatusView.Failed
        },
        latestUpdateTimestampSecs = payment.latestUpdateTimestamp.toLong(),
    )

    /**
     * The `switch` iOS spreads over three computed properties
     * (`PaymentKind.swift:13–63`), collapsed into the one place that can see the
     * variant.
     *
     * On-chain is the odd one out twice over: its id is a txid rather than a
     * preimage, and it is the only kind whose `stableID` and `transactionID` are
     * the same value. [PaymentKindView] carries both so no call site has to
     * remember which it wanted.
     */
    fun toView(kind: PaymentKind): PaymentKindView = when (kind) {
        is PaymentKind.Onchain -> PaymentKindView.Onchain(
            txId = kind.txid,
            confirmation = when (val status = kind.status) {
                is ConfirmationStatus.Confirmed -> OnchainConfirmationView.Confirmed(
                    height = status.height.toInt(),
                    timestampSecs = status.timestamp.toLong(),
                )
                is ConfirmationStatus.Unconfirmed -> OnchainConfirmationView.Unconfirmed
            },
        )

        is PaymentKind.Bolt11 -> PaymentKindView.Bolt11(
            hash = kind.hash,
            preimage = kind.preimage,
        )

        is PaymentKind.Bolt11Jit -> PaymentKindView.Bolt11Jit(
            hash = kind.hash,
            preimage = kind.preimage,
            counterpartySkimmedFeeMsat = kind.counterpartySkimmedFeeMsat,
        )

        is PaymentKind.Bolt12Offer -> PaymentKindView.Bolt12(
            hash = kind.hash,
            preimage = kind.preimage,
            isRefund = false,
        )

        is PaymentKind.Bolt12Refund -> PaymentKindView.Bolt12(
            hash = kind.hash,
            preimage = kind.preimage,
            isRefund = true,
        )

        is PaymentKind.Spontaneous -> PaymentKindView.Spontaneous(
            hash = kind.hash,
            preimage = kind.preimage,
        )
    }

    fun toView(balances: BalanceDetails) = BalanceView(
        totalOnchainBalanceSats = balances.totalOnchainBalanceSats,
        spendableOnchainBalanceSats = balances.spendableOnchainBalanceSats,
        totalAnchorChannelsReserveSats = balances.totalAnchorChannelsReserveSats,
        totalLightningBalanceSats = balances.totalLightningBalanceSats,
        lightningBalances = balances.lightningBalances.map(::toView),
        pendingBalancesFromChannelClosures =
            balances.pendingBalancesFromChannelClosures.map(::toView),
    )

    fun toView(balance: LightningBalance): LightningBalanceView = when (balance) {
        is LightningBalance.ClaimableOnChannelClose ->
            LightningBalanceView.ClaimableOnChannelClose(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
            )

        is LightningBalance.ClaimableAwaitingConfirmations ->
            LightningBalanceView.ClaimableAwaitingConfirmations(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
                source = when (balance.source) {
                    BalanceSource.HOLDER_FORCE_CLOSED -> BalanceSourceView.HolderForceClosed
                    BalanceSource.COUNTERPARTY_FORCE_CLOSED ->
                        BalanceSourceView.CounterpartyForceClosed
                    BalanceSource.COOP_CLOSE -> BalanceSourceView.CoopClose
                    BalanceSource.HTLC -> BalanceSourceView.Htlc
                },
            )

        is LightningBalance.ContentiousClaimable ->
            LightningBalanceView.ContentiousClaimable(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
            )

        is LightningBalance.MaybeTimeoutClaimableHtlc ->
            LightningBalanceView.MaybeTimeoutClaimableHtlc(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
            )

        is LightningBalance.MaybePreimageClaimableHtlc ->
            LightningBalanceView.MaybePreimageClaimableHtlc(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
            )

        is LightningBalance.CounterpartyRevokedOutputClaimable ->
            LightningBalanceView.CounterpartyRevokedOutputClaimable(
                channelId = balance.channelId,
                amountSatoshis = balance.amountSatoshis,
            )
    }

    fun toView(sweep: PendingSweepBalance): PendingSweepView = when (sweep) {
        is PendingSweepBalance.PendingBroadcast ->
            PendingSweepView.PendingBroadcast(amountSatoshis = sweep.amountSatoshis)

        is PendingSweepBalance.BroadcastAwaitingConfirmation ->
            PendingSweepView.BroadcastAwaitingConfirmation(
                amountSatoshis = sweep.amountSatoshis,
                latestSpendingTxId = sweep.latestSpendingTxid,
            )

        is PendingSweepBalance.AwaitingThresholdConfirmations ->
            PendingSweepView.AwaitingThresholdConfirmations(
                amountSatoshis = sweep.amountSatoshis,
                latestSpendingTxId = sweep.latestSpendingTxid,
            )
    }
}
