package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.node.ManagedNode
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import com.bittr.android.core.wallet.ldk.node.NodeStartErrorClassifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The wire: `WalletService.start`/`stop` reaching a node, and `removeWallet`
 * reaching it in the right order.
 *
 * Until BIT-126 these three were `SeedWalletService`'s no-ops, and the interface
 * said so — *"[start] and [stop] are still the stub's no-ops until BIT-6
 * lands"*. The tests below are what stops them quietly becoming no-ops again:
 * each asserts against the node, not against the decorator.
 */
class NodeBackedWalletServiceTest {

    /**
     * The seed half, recording what reached it.
     *
     * Not `SeedWalletService`. What is under test is the decoration — that nine
     * methods pass through untouched and three do not — and a real seed service
     * would make every assertion here depend on PBKDF2 and on a `SecureStore`
     * that has nothing to do with the question.
     */
    private class RecordingSeed(private val log: MutableList<String>) : WalletService {
        override val state: StateFlow<WalletState> = MutableStateFlow(WalletState.Locked)

        var unlockAnswer = true
        var removals = 0
            private set

        override suspend fun createWallet(): Mnemonic {
            log += "createWallet"
            return Mnemonic(List(12) { "abandon" })
        }

        override suspend fun restoreWallet(mnemonic: Mnemonic) {
            log += "restoreWallet"
        }

        override suspend fun setPin(pin: String) {
            log += "setPin"
        }

        override suspend fun unlock(pin: String): Boolean {
            log += "unlock"
            return unlockAnswer
        }

        override suspend fun failedUnlockAttempts(): Int {
            log += "failedUnlockAttempts"
            return 3
        }

        override suspend fun holdsSeed(mnemonic: Mnemonic): Boolean {
            log += "holdsSeed"
            return true
        }

        override suspend fun resetPin(mnemonic: Mnemonic, pin: String) {
            log += "resetPin"
        }

        override suspend fun removeWallet() {
            log += "seed erased"
            removals++
        }

        /** Fails the test if it is ever reached: the decorator must override these. */
        override suspend fun start() {
            log += "SEED START — the decorator did not override start"
        }

        override suspend fun stop() {
            log += "SEED STOP — the decorator did not override stop"
        }
    }

    private class FakeNode(private val log: MutableList<String>) : ManagedNode {
        private var running = false

        override fun start() {
            log += "node started"
            running = true
        }

        override fun isRunning() = running

        override fun stop() {
            log += "node stopped"
            running = false
        }

        override fun close() = Unit
    }

    private fun hostOf(scope: CoroutineScope, log: MutableList<String>) = WalletNodeHost(
        scope = scope,
        lifecycle = NodeLifecycle(
            scope = scope,
            factory = { FakeNode(log) },
            classifier = NodeStartErrorClassifier { false },
            elapsedRealtimeMillis = { 0L },
            wait = {},
        ),
        presence = ForegroundPresence.None,
    )

    /** `UnlockViewModel` calls this after a correct PIN. It has to reach a node. */
    @Test
    fun `start brings a node up`() = runTest(UnconfinedTestDispatcher()) {
        val log = mutableListOf<String>()
        val host = hostOf(this, log)
        val wallet = NodeBackedWalletService(RecordingSeed(log), host)

        wallet.start()

        assertEquals(listOf("node started"), log)
        assertTrue(host.isRunning)
    }

    /** `WalletService.stop`'s stated contract: safe when already stopped. */
    @Test
    fun `stop is safe on a wallet that was never started`() = runTest(UnconfinedTestDispatcher()) {
        val log = mutableListOf<String>()
        val wallet = NodeBackedWalletService(RecordingSeed(log), hostOf(this, log))

        wallet.stop()

        assertEquals(emptyList<String>(), log)
    }

    /**
     * **The node goes down before any key material goes.**
     *
     * iOS's ordering — `CacheManager.deleteClientInfo()` runs only once the node
     * has stopped — and on Android it is load-bearing rather than tidy: ldk-node
     * holds its SQLite store open, and erasing the seed beside a live node is
     * how the next start builds against a wallet that no longer exists.
     */
    @Test
    fun `removeWallet stops the node before erasing anything`() =
        runTest(UnconfinedTestDispatcher()) {
            val log = mutableListOf<String>()
            val seed = RecordingSeed(log)
            val wallet = NodeBackedWalletService(
                seed = seed,
                host = hostOf(this, log),
                wipeNodeState = { log += "node state erased" },
            )

            wallet.start()
            wallet.removeWallet()

            assertEquals(
                listOf("node started", "node stopped", "node state erased", "seed erased"),
                log,
            )
            assertEquals(1, seed.removals)
        }

    /**
     * **A new seed never meets a running node's state.** The node goes down,
     * the seed is written, and the state is fitted to it — in that order, so
     * the quarantine does not move a directory a live node has open.
     */
    @Test
    fun `createWallet stops the node and prepares its state for the new seed`() =
        runTest(UnconfinedTestDispatcher()) {
            val log = mutableListOf<String>()
            val prepared = mutableListOf<Mnemonic>()
            val wallet = NodeBackedWalletService(
                seed = RecordingSeed(log),
                host = hostOf(this, log),
                prepareNodeState = { mnemonic ->
                    log += "node state prepared"
                    prepared += mnemonic
                },
            )

            wallet.start()
            val mnemonic = wallet.createWallet()

            assertEquals(
                listOf("node started", "node stopped", "createWallet", "node state prepared"),
                log,
            )
            assertEquals(listOf(mnemonic.phrase), prepared.map { it.phrase })
        }

    @Test
    fun `restoreWallet prepares the state for the restored phrase`() =
        runTest(UnconfinedTestDispatcher()) {
            val log = mutableListOf<String>()
            val prepared = mutableListOf<String>()
            val wallet = NodeBackedWalletService(
                seed = RecordingSeed(log),
                host = hostOf(this, log),
                prepareNodeState = { prepared += it.phrase },
            )
            val phrase = Mnemonic(List(12) { "zoo" })

            wallet.restoreWallet(phrase)

            assertEquals(listOf("restoreWallet"), log)
            assertEquals(listOf(phrase.phrase), prepared)
        }

    /**
     * **Node state before key material.**
     *
     * The direction a failure between the two should fail in. The LDK state
     * directory is the only thing that can sweep a force-closed channel and a
     * BIP-39 seed cannot reconstruct it — so a half-finished removal should
     * leave the *recoverable* half. Erasing the seed first and then failing
     * leaves channel monitors for a wallet nobody can open.
     */
    @Test
    fun `a failed node-state wipe leaves the seed intact`() = runTest(UnconfinedTestDispatcher()) {
        val log = mutableListOf<String>()
        val seed = RecordingSeed(log)
        val wallet = NodeBackedWalletService(
            seed = seed,
            host = hostOf(this, log),
            wipeNodeState = { throw IllegalStateException("could not delete the state directory") },
        )

        wallet.start()
        val failure = runCatching { wallet.removeWallet() }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals("the seed must still be there to retry with", 0, seed.removals)
        assertFalse("and the wallet stays down", log.contains("node started") && log.last() == "node started")
    }

    /**
     * Everything that is not about a node reaches the seed unchanged.
     *
     * Nine methods, because the PIN gate — the constant-time comparison, the
     * failed-attempt counter, the wipe ordering — has one implementation and one
     * test suite, and a decorator that reimplemented any of it would be a second
     * place for an attacker to be given extra guesses.
     */
    @Test
    fun `every non-node method is the seed service's`() = runTest(UnconfinedTestDispatcher()) {
        val log = mutableListOf<String>()
        val seed = RecordingSeed(log)
        val wallet = NodeBackedWalletService(seed, hostOf(this, log))
        val mnemonic = Mnemonic(List(12) { "abandon" })

        wallet.createWallet()
        wallet.restoreWallet(mnemonic)
        wallet.setPin("1234")
        wallet.unlock("1234")
        wallet.failedUnlockAttempts()
        wallet.holdsSeed(mnemonic)
        wallet.resetPin(mnemonic, "1234")

        assertEquals(
            listOf(
                "createWallet",
                "restoreWallet",
                "setPin",
                "unlock",
                "failedUnlockAttempts",
                "holdsSeed",
                "resetPin",
            ),
            log,
        )
        assertEquals(WalletState.Locked, wallet.state.value)
    }
}
