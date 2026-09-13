package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.node.NodeStartErrorClassifier
import org.lightningdevkit.ldknode.NodeException

/**
 * iOS's retryable-error list, against ldk-node's Kotlin exceptions.
 *
 * `BitcoinManager.isRetryableNodeStartError` (`BitcoinManager.swift:254–265`)
 * retries three cases and nothing else:
 *
 * ```swift
 * case .FeerateEstimationUpdateFailed,
 *      .FeerateEstimationUpdateTimeout,
 *      .ConnectionFailed:
 *     return true
 * ```
 *
 * The list is short for a reason worth keeping: these are the failures where
 * *waiting* is a plausible fix. Everything else — a corrupt store, an invalid
 * network, a persistence failure — is retried into the same result three times
 * while the user watches, and the retry hides the real error behind a timeout.
 *
 * ## Why this is an allowlist and not "retry unless fatal"
 *
 * The tempting widening is `PersistenceFailed`, because it *looks* transient.
 * It is the one case where a retry is actively harmful: on Android a
 * persistence failure during start is how a storage-layer problem — a full
 * disk, a state directory that is mid-quarantine, a second node object holding
 * the same SQLite file — first shows itself, and three more attempts at three
 * more writes is the wrong response to a node that cannot write. BIT-20 rule 3
 * makes the same distinction one layer down for the Keystore: a transient
 * failure is a failure, and the answer is to abort, not to press on.
 *
 * Proved by `LdkNodeStartErrorsTest`, which asserts the three cases retry, a
 * representative sample of the other fifty-odd do not, and — the part that
 * matters after a dependency bump — that the retryable names still exist as
 * `NodeException` subclasses at all.
 */
object LdkNodeStartErrors : NodeStartErrorClassifier {

    override fun isRetryable(error: Throwable): Boolean = when (error) {
        is NodeException.FeerateEstimationUpdateFailed,
        is NodeException.FeerateEstimationUpdateTimeout,
        is NodeException.ConnectionFailed,
        -> true

        else -> false
    }

    /**
     * Whether the node is reporting that it is already up.
     *
     * `StartLightning.swift:156–158` reaches this conclusion by asking
     * `status()?.isRunning` after a failed start. ldk-node 0.7.0 also says it
     * directly, by throwing this, and the direct signal is the one available
     * before a `Node` reference has been published anywhere — see
     * `NodeStartRunner`'s class comment for why that branch is routine on
     * Android and exceptional on iOS.
     */
    fun isAlreadyRunning(error: Throwable): Boolean = error is NodeException.AlreadyRunning
}
