package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.lightning.EventPump
import com.bittr.android.core.wallet.ldk.lightning.EventPumpPort
import java.io.File
import java.io.IOException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The ledger, and the one rule in it that is not deduplication.
 *
 * `EventPumpTest` proves the pump's acknowledgement order against a recording
 * ledger. This proves the ledger itself: that it remembers across a process,
 * that it is bounded, and — the test this issue exists to name — that **a
 * payment failure is never suppressed**.
 *
 * Events are modelled as `String`, which is what they are to everything above
 * the adapter: the pump is generic and the ledger keys on a rendering. The
 * exemption predicate stands in for `LdkEventKey.isPaymentFailed`, which
 * `LdkEventKeyTest` proves separately over the real ldk-node type.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CachedEventLedgerTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var directory: File

    @Before
    fun setUp() {
        directory = temporaryFolder.newFolder("cache")
    }

    private fun ledger(
        cache: WalletCache = FileWalletCache(directory),
        limit: Int = CachedEventLedger.DEFAULT_LIMIT,
        onFailure: (Throwable) -> Unit = {},
    ) = CachedEventLedger<String>(
        cache = cache,
        describe = { it },
        isExemptFromDeduplication = { it.startsWith(PAYMENT_FAILED) },
        limit = limit,
        onFailure = onFailure,
    )

    @Test
    fun `an event that has been recorded reads as handled`() {
        val ledger = ledger()
        assertFalse(ledger.hasHandled("PaymentReceived(hash=abc)"))

        ledger.recordHandled("PaymentReceived(hash=abc)")

        assertTrue(ledger.hasHandled("PaymentReceived(hash=abc)"))
    }

    @Test
    fun `what one process recorded, the next one still knows`() {
        ledger().recordHandled("PaymentReceived(hash=abc)")

        assertTrue(
            "Both the ledger and the cache under it are new instances — the store is " +
                "the only thing carrying the fact across.",
            ledger().hasHandled("PaymentReceived(hash=abc)"),
        )
    }

    /**
     * **The exemption.** `!event.isPaymentFailed()` in
     * `HandlePaymentNotification.swift:308`.
     *
     * A payment that fails, is retried and fails again produces a byte-identical
     * description the second time. Suppressing it leaves the user watching a
     * spinner for a payment that has already failed twice.
     */
    @Test
    fun `a payment failure is never suppressed, however many times it is recorded`() {
        val ledger = ledger()

        repeat(3) { ledger.recordHandled("$PAYMENT_FAILED(hash=abc, reason=RETRIES_EXHAUSTED)") }

        assertFalse(
            "The ledger must answer false for a payment failure before it looks at the " +
                "store at all, or the second failure of a retried payment is hidden and " +
                "the user is left on a spinner.",
            ledger.hasHandled("$PAYMENT_FAILED(hash=abc, reason=RETRIES_EXHAUSTED)"),
        )
    }

    /**
     * The exempt event is still *written*, because iOS's `else` branch calls
     * `didHandleEvent` unconditionally (`HandlePaymentNotification.swift:313`).
     *
     * The ledger has a second reader on iOS — the notification service
     * extension — and the record is what that reader sees. Skipping the write
     * for exempt events would be a divergence hidden behind a passing dedup
     * test, since [hasHandled] answers false for them either way.
     */
    @Test
    fun `an exempt event is still recorded, exactly once`() {
        val cache = FileWalletCache(directory)
        val ledger = ledger(cache)

        ledger.recordHandled("$PAYMENT_FAILED(hash=abc)")
        ledger.recordHandled("$PAYMENT_FAILED(hash=abc)")

        assertEquals(
            listOf("$PAYMENT_FAILED(hash=abc)"),
            cache.strings(CachedEventLedger.KEY),
        )
    }

    @Test
    fun `the oldest description is dropped once the limit is reached`() {
        val cache = FileWalletCache(directory)
        val ledger = ledger(cache, limit = 2)

        ledger.recordHandled("first")
        ledger.recordHandled("second")
        ledger.recordHandled("third")

        assertEquals(listOf("second", "third"), cache.strings(CachedEventLedger.KEY))
        assertFalse("Evicted, so it would be shown again if replayed.", ledger.hasHandled("first"))
    }

    /**
     * Re-recording an event already in the ledger must not move it to the end.
     *
     * If it did, a duplicate delivery of an old event would push a *newer* one
     * out of the window — the ledger would forget the events most likely to be
     * replayed in order to remember one that just was.
     */
    @Test
    fun `re-recording a known event does not reorder the window`() {
        val cache = FileWalletCache(directory)
        val ledger = ledger(cache, limit = 2)

        ledger.recordHandled("first")
        ledger.recordHandled("second")
        ledger.recordHandled("first")

        assertEquals(listOf("first", "second"), cache.strings(CachedEventLedger.KEY))
    }

    /**
     * A ledger write runs inside `EventPump`'s loop and *before* the handler, so
     * a throw would be a handler that never runs and an event that is never
     * acknowledged: a full disk would become a pump replaying one event until
     * the node stops.
     */
    @Test
    fun `a failed write is reported and does not propagate`() {
        val failure = IOException("no space left on device")
        val reported = mutableListOf<Throwable>()
        val ledger = ledger(cache = FailingCache(failure), onFailure = { reported += it })

        ledger.recordHandled("PaymentReceived(hash=abc)")

        assertEquals(1, reported.size)
        assertSame(failure, reported.single())
    }

    /**
     * The claim the issue is really about, end to end: *a replayed event is not
     * shown to the user twice.*
     *
     * The first pump is cancelled after the handler and before the
     * acknowledgement — the window Android has and iOS does not — so ldk-node
     * still holds the event and delivers it again. The second pump, with nothing
     * in memory and only the file to go on, must acknowledge it without handling
     * it a second time.
     */
    @Test
    fun `an event replayed after process death is acknowledged but not handled again`() = runTest {
        val queue = ReplayingQueue(listOf("PaymentReceived(hash=abc)"))
        val firstRun = mutableListOf<String>()

        // Handled, recorded, and then the process dies before the ack: the
        // handler throwing is the observable stand-in, since it leaves the event
        // at the head of the queue exactly as a kill would.
        runCatching {
            EventPump(
                port = queue,
                ledger = ledger(),
                handler = { event ->
                    firstRun += event
                    throw IllegalStateException("process death")
                },
            ).run()
        }

        assertEquals(listOf("PaymentReceived(hash=abc)"), firstRun)
        assertEquals("Never acknowledged, so ldk-node still has it.", 1, queue.remaining.size)

        val secondRun = mutableListOf<String>()
        val outcome = EventPump(queue, ledger(), { secondRun += it }).run()

        assertEquals(
            "The user is not shown the same payment twice. This is the ledger's whole " +
                "job — the replay itself is ldk-node's queue working as intended.",
            emptyList<String>(),
            secondRun,
        )
        assertEquals("And the queue drains, or it would never empty.", 1, outcome.acknowledged)
        assertEquals(emptyList<String>(), queue.remaining)
    }

    /** ldk-node's queue: the head stays put until `eventHandled()`. */
    private class ReplayingQueue(events: List<String>) : EventPumpPort<String> {
        private val queue = ArrayDeque(events)
        val remaining: List<String> get() = queue.toList()

        override suspend fun nextEvent(): String? = queue.firstOrNull()

        override fun eventHandled() {
            queue.removeFirstOrNull()
        }
    }

    private class FailingCache(private val failure: Throwable) : WalletCache {
        override fun strings(key: String): List<String> = emptyList()
        override fun update(key: String, transform: (List<String>) -> List<String>): Unit =
            throw failure
        override fun remove(key: String): Unit = throw failure
    }

    private companion object {
        const val PAYMENT_FAILED = "PaymentFailed"
    }
}
