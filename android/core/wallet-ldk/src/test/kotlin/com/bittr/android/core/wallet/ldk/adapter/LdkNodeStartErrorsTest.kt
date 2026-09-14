package com.bittr.android.core.wallet.ldk.adapter

import java.io.IOException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.lightningdevkit.ldknode.NodeException

/**
 * iOS's three retryable start failures, against ldk-node 0.7.0's real exception
 * types.
 *
 * This runs on the JVM without the native library because `NodeException` and
 * its subclasses are ordinary Kotlin exception classes — UniFFI generates the
 * error types in Kotlin and only crosses into Rust when a *call* is made. That
 * is worth stating because it is the whole reason the port-parity claim here has
 * a test at all: nothing below touches a `Node`.
 *
 * The failure this is really aimed at is a dependency bump. If ldk-node renames
 * `FeerateEstimationUpdateTimeout`, the `when` in [LdkNodeStartErrors] stops
 * matching it — and a `when` with an `else` branch does not fail to compile when
 * a case disappears, it silently reclassifies it as non-retryable. So the last
 * test asserts the names still exist as subclasses, separately from asserting
 * what they classify as.
 */
class LdkNodeStartErrorsTest {

    @Test
    fun `the three connectivity failures iOS retries are retryable`() {
        listOf(
            NodeException.FeerateEstimationUpdateFailed("fee estimation failed"),
            NodeException.FeerateEstimationUpdateTimeout("fee estimation timed out"),
            NodeException.ConnectionFailed("connection failed"),
        ).forEach {
            assertTrue(
                "${it.javaClass.simpleName} is one of the three cases " +
                    "BitcoinManager.swift:258–260 retries.",
                LdkNodeStartErrors.isRetryable(it),
            )
        }
    }

    @Test
    fun `persistence and store failures are not retried`() {
        // The tempting widening, and the harmful one. On Android a persistence
        // failure during start is how a full disk, a state directory mid-
        // quarantine, or a second node object over the same SQLite file first
        // shows itself. Three more attempts at three more writes is the wrong
        // answer to a node that cannot write — and it buries the error the user
        // and Sentry need under a ten-second timeout.
        listOf(
            NodeException.PersistenceFailed("could not persist"),
            NodeException.InvalidNetwork("wrong network"),
            NodeException.AlreadyRunning("already running"),
            NodeException.NotRunning("not running"),
            NodeException.WalletOperationFailed("wallet operation failed"),
            NodeException.InvalidSecretKey("invalid secret key"),
        ).forEach {
            assertFalse(
                "${it.javaClass.simpleName} must not be retried.",
                LdkNodeStartErrors.isRetryable(it),
            )
        }
    }

    @Test
    fun `a failure that is not a NodeException at all is not retried`() {
        // JNA can throw before ldk-node does — an UnsatisfiedLinkError on a
        // device whose ABI the packaged .so does not cover, for instance. That
        // will not be fixed by waiting one second.
        assertFalse(LdkNodeStartErrors.isRetryable(IOException("no such file")))
        assertFalse(LdkNodeStartErrors.isRetryable(UnsatisfiedLinkError("no ldk_node in java.library.path")))
    }

    @Test
    fun `AlreadyRunning is recognised, and it is not a retry`() {
        // These two answers have to differ. Retrying an already-running node
        // wastes ten seconds and then reports failure; recognising it is what
        // turns a healthy node into a successful start. See NodeStartRunner.
        val alreadyRunning = NodeException.AlreadyRunning("already running")

        assertTrue(LdkNodeStartErrors.isAlreadyRunning(alreadyRunning))
        assertFalse(LdkNodeStartErrors.isRetryable(alreadyRunning))
        assertFalse(LdkNodeStartErrors.isAlreadyRunning(NodeException.ConnectionFailed("nope")))
    }

    @Test
    fun `the retryable exception types still exist under these names`() {
        // Guards the rename case described in the class comment: `when` with an
        // `else` branch reclassifies a vanished case instead of failing to
        // compile. If ldk-node is bumped and a name below has moved, this goes
        // red with the name in the message rather than the retry quietly
        // stopping.
        listOf(
            "FeerateEstimationUpdateFailed",
            "FeerateEstimationUpdateTimeout",
            "ConnectionFailed",
            "AlreadyRunning",
        ).forEach { name ->
            val type = Class.forName("org.lightningdevkit.ldknode.NodeException\$$name")
            assertTrue(
                "org.lightningdevkit.ldknode.NodeException.$name is no longer a " +
                    "NodeException subclass. LdkNodeStartErrors classifies on type, and " +
                    "its `else` branch would silently make this case non-retryable.",
                NodeException::class.java.isAssignableFrom(type),
            )
        }
    }
}
