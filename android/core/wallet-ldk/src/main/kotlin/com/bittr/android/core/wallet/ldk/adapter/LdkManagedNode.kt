package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.ManagedNodeFactory
import com.bittr.android.core.wallet.ldk.node.MnemonicUnavailableException
import com.bittr.android.core.wallet.ldk.node.NodeConfigPlan
import com.bittr.android.core.wallet.ldk.seed.SeedVault
import org.lightningdevkit.ldknode.Builder
import org.lightningdevkit.ldknode.Node
import org.lightningdevkit.ldknode.NodeException

/**
 * ldk-node's `Node` as a [ManagedNode].
 *
 * The whole of the FFI boundary for node lifecycle is this file plus
 * [LdkNodeConfig.configure]'s call sites. Everything above it —
 * `NodeLifecycle`, `NodeStartGate`, `NodeStartRunner` — decides; this only
 * translates.
 *
 * Two translations are doing real work rather than forwarding.
 */
class LdkManagedNode(
    /**
     * Exposed because the rest of BIT-122 needs it: sync, channels and payments
     * are all methods on this object, and they will hang their own seams off it
     * rather than widening [ManagedNode] — see that interface's comment.
     */
    val node: Node,
) : ManagedNode {

    override fun start() = node.start()

    /**
     * `status()?.isRunning == true` (`BitcoinManager.swift:88`).
     *
     * `status()` is an FFI call and can fail for reasons that are not an answer
     * to the question — a node mid-teardown, a handle already freed. The caller
     * that matters (`NodeLifecycle.isNodeRunning`) reads this while holding a
     * lock and treats an exception as "not running", so the direction of the
     * failure is decided there rather than swallowed here.
     */
    override fun isRunning(): Boolean = node.status().isRunning

    /**
     * `stop()`, with the one divergence [ManagedNode.stop] promises.
     *
     * ldk-node throws `NotRunning` when asked to stop a node that is not up.
     * iOS's callers — `AppDelegate.applicationWillTerminate`, the reset path —
     * call stop unconditionally and treat it as idempotent, and
     * `WalletService.stop` was specified to match. So that single case is
     * absorbed. Nothing else is: a `PersistenceFailed` on the way down means the
     * channel state may not have been written, and a caller that is told the
     * wallet stopped cleanly when it did not is the start of a stale-state
     * problem the user pays for.
     */
    override fun stop() {
        try {
            node.stop()
        } catch (notRunning: NodeException.NotRunning) {
            // Already down. The outcome the caller asked for.
        }
    }

    /**
     * Hand the native object back now.
     *
     * See [ManagedNode.close] for why this is not something to leave to the
     * cleaner. `Node` is UniFFI-generated and implements `AutoCloseable`;
     * `close()` is idempotent and safe to call on a node that never started,
     * which is the path that calls it most.
     */
    override fun close() = node.close()
}

/**
 * The ldk-node `Node` inside whatever [ManagedNode] is current, or null.
 *
 * `NodeLifecycle` is written against [ManagedNode] so its custody rules can be
 * proved without a native library — `WalletLayeringGuardTest` — and
 * [LdkNodeFactory] is the only thing in the app that builds one. The cast is
 * therefore total in practice, and null when it is not: a lifecycle over some
 * other implementation has no ldk-node node to reach, and answering null is the
 * right result rather than a crash.
 *
 * `internal` and shared, rather than private to one file: both live callers —
 * the event pump's port and [lightningNodePort] — have to agree about what
 * "the current node" means, and two copies of a cast are two places for that to
 * stop being true.
 */
internal fun ManagedNode?.ldkNode(): Node? = (this as? LdkManagedNode)?.node

/**
 * Builds a node from a plan and the device's mnemonic — iOS's `didStartLDK()`
 * down to `nodeBuilder.build()` (`BitcoinManager.swift:119–207`).
 *
 * ## What is not here, and where it went
 *
 * iOS's `didStartLDK` also rotates the LDK log and calls
 * `LightningStorage.excludeFromBackup()` before configuring anything
 * (`BitcoinManager.swift:121–125`). Neither is ported into this function:
 *
 * - **Backup exclusion is not a start-time action on Android.** It is a property
 *   of the path. Everything ldk-node writes is under
 *   `WalletPaths.ldkStateDir`, inside `getNoBackupFilesDir()`, so exclusion
 *   holds from the first byte written rather than from whenever a start next
 *   happens. That is BIT-8 rule 4 / BIT-20 rule 5, and `StateDirLocationTest`
 *   proves it. Re-asserting it here would be a call that cannot fail and
 *   therefore cannot be trusted to mean anything.
 * - **Log rotation** has no equivalent because no filesystem logger is
 *   installed; iOS's is commented out too (`BitcoinManager.swift:189–197`).
 *
 * ## The build is not retried, and that is iOS's shape
 *
 * `NodeStartRetryPolicy` covers `start()`, not `build()`. iOS builds once and
 * returns false if it throws (`BitcoinManager.swift:200–207`); the retryable
 * failures are all connectivity, and a `BuildException` is a configuration or
 * storage problem that three more attempts will reproduce. Keeping the build
 * outside the retry loop also keeps it to one object per start attempt — a
 * builder that ran three times would leave two nodes behind on the way to
 * succeeding.
 */
class LdkNodeFactory(
    private val plan: () -> NodeConfigPlan,
    private val vault: SeedVault,
) : ManagedNodeFactory {

    /**
     * @throws MnemonicUnavailableException when the device has no readable
     *   mnemonic — iOS's early `return false`, as a cause the caller can log.
     * @throws org.lightningdevkit.ldknode.BuildException from `build()`.
     */
    override fun build(): ManagedNode {
        val currentPlan = plan()

        // `read()` throws on a transient Keystore failure and returns null only
        // for genuine absence — the three-valued distinction SeedVault exists to
        // make. Both end the start, but only one of them should ever be read as
        // "this device has no wallet", so the throw is left to propagate rather
        // than being flattened into the null case here.
        val mnemonic = vault.read()
            ?: throw MnemonicUnavailableException(
                "No mnemonic on this device; refusing to build a node. This is either a " +
                    "wallet being torn down while a start was in flight, or a start that " +
                    "reached the node layer before setup finished.",
            )

        val builder = Builder.fromConfig(LdkNodeConfig.config(currentPlan))
        val node = try {
            LdkNodeConfig.configure(builder, currentPlan, mnemonic)
            builder.build()
        } finally {
            // The builder holds a Rust object of its own. iOS drops it with ARC
            // at the end of `didStartLDK`; here it has to be said, for the same
            // reason ManagedNode.close has to be said.
            runCatching { builder.close() }
        }
        return LdkManagedNode(node)
    }
}
