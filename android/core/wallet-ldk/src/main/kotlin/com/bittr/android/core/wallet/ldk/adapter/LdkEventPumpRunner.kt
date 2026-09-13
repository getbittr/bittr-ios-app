package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.cache.CachedEventLedger
import com.bittr.android.core.wallet.ldk.cache.WalletCache
import com.bittr.android.core.wallet.ldk.host.NodeRunner
import com.bittr.android.core.wallet.ldk.lightning.EventPump
import com.bittr.android.core.wallet.ldk.lightning.EventPumpOutcome
import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import org.lightningdevkit.ldknode.Event
import org.lightningdevkit.ldknode.Node

/**
 * The event the ledger keys on, rendered so that two processes agree.
 *
 * iOS keys on `"\(event)"`, and the naive Kotlin translation — `event.toString()`
 * — is *nearly* the same thing. ldk-node 0.7.0's `Event` variants are Kotlin data
 * classes, so their renderings are structural, and so are the records inside them
 * (`CustomTlvRecord`, `OutPoint`) and `PaymentFailureReason`, which is an enum.
 *
 * ## The exception, and why it is worth a class
 *
 * `ClosureReason`'s data-free variants — `CommitmentTxConfirmed`,
 * `DisconnectedPeer`, `FundingTimedOut` and the rest — are generated as Kotlin
 * `object`s with no `toString` override. Their rendering is therefore
 * `java.lang.Object`'s: `org.lightningdevkit.ldknode.ClosureReason$…@1b6d3586`,
 * where the tail is an **identity hash**, freshly assigned in every process.
 *
 * That is checkable rather than assumed — `javap` on
 * `ldk-node-android-0.7.0.aar` shows `INSTANCE` and no `toString` on those
 * classes, and `toString`/`hashCode` on every data variant beside them.
 *
 * So an `Event.ChannelClosed` renders differently after a restart, and a ledger
 * keyed on that rendering can never suppress a replayed channel closure — the
 * one event class most likely to be replayed, because a closure arrives while
 * the app is not running and the queue holds it until it is. It fails in the
 * safe direction (a notification twice, not a payment lost) and it fails
 * silently, which is the part worth removing.
 *
 * ## Repaired generally rather than per variant
 *
 * [of] strips any `<class>@<hex>` fragment down to the class's simple name. A
 * `when` over the variants would have to restate every field of the ones it
 * touched — and would go stale on the next ldk-node upgrade, quietly, in the
 * direction of the bug it exists to fix. The substitution is crude, in the same
 * way and for the same reason as `WalletSourceTree.codeOf`: an event payload is
 * txids, node ids, hashes and numbers, none of which contain `@`.
 *
 * Proved by `LdkEventKeyTest`.
 */
object LdkEventKey {

    /**
     * `<fully.qualified.Class>@<hex>` — `Object.toString`'s shape, and nothing
     * else in an event rendering.
     */
    private val IDENTITY_RENDERING = Regex("""[\w.$]+@[0-9a-f]+""")

    /** The ledger key for [event]. iOS's `"\(event)"`, made process-independent. */
    fun of(event: Event): String = IDENTITY_RENDERING.replace(event.toString()) { match ->
        match.value.substringBefore('@').substringAfterLast('.').substringAfterLast('$')
    }

    /**
     * `Event.isPaymentFailed()` (`Extensions/Event.swift:12–17`).
     *
     * The one event the ledger must never suppress: a retried payment fails
     * again with a byte-identical description, and hiding the second failure
     * leaves the user watching a spinner.
     */
    fun isPaymentFailed(event: Event): Boolean = event is Event.PaymentFailed

    /**
     * The variant name alone — what may safely leave this module.
     *
     * [of] is a full rendering, and a full rendering of `Event.PaymentSuccessful`
     * contains `paymentPreimage`: the proof of payment, the one field in an event
     * that is a secret rather than an identifier. iOS logs the whole event
     * (`HandlePaymentNotification.swift:306`), and that is not a reason to. It
     * stays inside the ledger, which is a file under `no_backup`; what goes to a
     * log or to a caller is this.
     */
    fun summary(event: Event): String = event.javaClass.simpleName
}

/**
 * The ldk-node `Node` inside whatever [ManagedNode] is current, or null.
 *
 * `NodeLifecycle` is written against [ManagedNode] so its custody rules can be
 * proved without a native library — `WalletLayeringGuardTest` — and
 * `LdkNodeFactory` is the only thing in the app that builds one. The cast is
 * therefore total in practice, and null when it is not: a lifecycle over some
 * other implementation has no ldk-node node to pump, and the pump reporting
 * `NodeGone` is the right answer rather than a crash.
 */
private fun ManagedNode?.ldkNode(): Node? = (this as? LdkManagedNode)?.node

/**
 * `EventPump` as a [NodeRunner], with its ledger bound to durable storage.
 *
 * This is the composition BIT-126 left as `runners = emptyList()`: the pump was
 * the first runner and could not be constructed, because its ledger wanted a
 * `CacheManager`-shaped store Android did not have. It is assembled in
 * `adapter/` because two of the four pieces name ldk-node types — the port and
 * the ledger's two lambdas — and `:app` cannot see them: `wallet-ldk` depends on
 * `ldk-node-android` with `implementation`, so `Event` is not on the app's
 * compile classpath and `di/WalletModule` could not write this expression even
 * if the layering allowed it.
 *
 * ## What the handler is, and what it is not
 *
 * [onEvent] receives the event's variant name and nothing else, because there is
 * nothing else yet: Android has no payment screen, no notification for an
 * incoming payment, and no transaction list to insert a row into. iOS's
 * `ldkEventReceived` does all three (`HandlePaymentNotification.swift:305–…`),
 * and porting it is not this issue. The name rather than the rendering because
 * the caller is a log line and the rendering can contain a payment preimage —
 * see [LdkEventKey.summary].
 *
 * That has a consequence worth stating rather than discovering. The pump
 * acknowledges what it handles, and an acknowledged event is dropped from
 * ldk-node's queue — so events arriving before there is a real handler are
 * reported and then gone. They would be gone either way: an event the ledger has
 * recorded is suppressed on any later delivery. What the queue is *not* is a
 * place to accumulate a backlog for a UI that does not exist. A real handler
 * replaces this lambda; nothing else here changes.
 *
 * A handler that throws is not an acknowledgement — `EventPump`'s point 2 — so
 * whatever lands here must be allowed to fail. A `Log` call cannot.
 */
class LdkEventPumpRunner(
    lifecycle: NodeLifecycle,
    cache: WalletCache,
    /** The handler. See the class comment for how little it is allowed to be. */
    onEvent: (String) -> Unit,
    /**
     * A ledger write that failed — a full disk, most likely. Swallowed inside
     * [CachedEventLedger] so it cannot stop the pump; the consequence is an
     * event that may be shown twice.
     */
    onLedgerFailure: (Throwable) -> Unit = {},
    /** `eventHandled()` threw. Expected while the node is going down. */
    onAcknowledgeFailure: (Throwable) -> Unit = {},
    /**
     * How the pump ended, once per node.
     *
     * `WalletNodeHost.onRunnerStopped` sees *that* a runner stopped; only this
     * sees whether it was a cancellation, a node that went away, or the terminal
     * `ReadFailed`. What a dead pump should cost the user is BIT-123's to decide,
     * and this is what it will read.
     */
    private val onStopped: (EventPumpOutcome) -> Unit = {},
) : NodeRunner {

    override val name: String = NAME

    /**
     * Built once and re-run on every node start.
     *
     * `EventPump.run` keeps no state between calls — its only accumulator is a
     * local — and the node is re-read on every iteration through
     * [LdkEventPumpPort], so a pump that outlives one node is not a pump attached
     * to a stale one.
     */
    private val pump = EventPump(
        port = LdkEventPumpPort { lifecycle.current.ldkNode() },
        ledger = CachedEventLedger(
            cache = cache,
            describe = LdkEventKey::of,
            isExemptFromDeduplication = LdkEventKey::isPaymentFailed,
            onFailure = onLedgerFailure,
        ),
        handler = { event -> onEvent(LdkEventKey.summary(event)) },
        onAcknowledgeFailure = onAcknowledgeFailure,
    )

    override suspend fun run() = onStopped(pump.run())

    private companion object {

        /** Appears in `onRunnerStopped` reports and nowhere a user can see. */
        const val NAME = "event-pump"
    }
}
