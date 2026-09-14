package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.WalletState
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What an FCM data message is allowed to do, decided on the JVM.
 *
 * [BackgroundWake] is the whole of BIT-133's client logic; `BittrMessagingService`
 * is the twenty lines that cannot be tested here, and `FcmWakeTest` is what runs
 * those on a device. The split is the same one [WalletNodeHostTest] makes with
 * [ForegroundPresence]: the *decisions* — what counts as a wake, what happens
 * before the process can be frozen again, what is released when a start throws —
 * are ordinary Kotlin and belong in a suite that runs in seconds.
 *
 * Two of the assertions below are about **order**, and order is the only thing
 * that can be wrong here in a way that still looks right. A promotion that
 * happens after the start is launched is a promotion that may never happen at
 * all, because the process can be frozen in between; and a start that throws
 * without a demotion leaves a permanent notification over nothing.
 */
class BackgroundWakeTest {

    private class RecordingPresence : ForegroundPresence {
        val events = mutableListOf<String>()

        override fun promote() {
            events += "promote"
        }

        override fun demote() {
            events += "demote"
        }
    }

    private fun wake(
        scope: kotlinx.coroutines.CoroutineScope,
        presence: ForegroundPresence = RecordingPresence(),
        state: WalletState = WalletState.Locked,
        start: suspend () -> Unit = {},
        report: (WakeOutcome) -> Unit = {},
    ) = BackgroundWake(
        scope = scope,
        presence = presence,
        walletState = { state },
        start = start,
        report = report,
    )

    @Test
    fun `a keyed data message starts the wallet`() = runTest(UnconfinedTestDispatcher()) {
        val starts = AtomicInteger()
        val subject = wake(this, start = { starts.incrementAndGet() })

        val outcome = subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

        assertEquals(WakeOutcome.Waking("payment"), outcome)
        assertEquals("the wake did not reach WalletService.start()", 1, starts.get())
        assertEquals(WakeOutcome.Woken("payment"), subject.last.value)
    }

    @Test
    fun `the process is held up before the start is launched, not after`() =
        runTest(UnconfinedTestDispatcher()) {
            // The one ordering that matters. onMessageReceived returns and the
            // process becomes freezable again; whatever has not happened by then
            // may never happen. WalletNodeHost.start makes the same call for the
            // same reason and this is the caller above it.
            val presence = RecordingPresence()
            val order = mutableListOf<String>()
            val subject = wake(
                this,
                presence = object : ForegroundPresence {
                    override fun promote() {
                        order += "promote"
                        presence.promote()
                    }

                    override fun demote() {
                        order += "demote"
                        presence.demote()
                    }
                },
                start = { order += "start" },
            )

            subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "channel"))

            assertEquals(listOf("promote", "start"), order)
        }

    @Test
    fun `a message without the wake key is not a wake`() = runTest(UnconfinedTestDispatcher()) {
        // The FCM project this app registers in also carries ordinary pushes —
        // the payment notifications iOS's device token is registered for. If any
        // data message woke the node, every one of those would start a Lightning
        // node and put a permanent notification in front of the user.
        val presence = RecordingPresence()
        val starts = AtomicInteger()
        val subject = wake(this, presence = presence, start = { starts.incrementAndGet() })

        val outcome = subject.onDataMessage(mapOf("title" to "Payment received", "amount" to "1000"))

        assertEquals(WakeOutcome.NotAWake(listOf("amount", "title")), outcome)
        assertEquals(0, starts.get())
        assertEquals("nothing should have been promoted", emptyList<String>(), presence.events)
    }

    @Test
    fun `the reported keys carry no values`() = runTest(UnconfinedTestDispatcher()) {
        // The payload arrives from the network, and the field a wake message is
        // likeliest to grow is a payment hash. NotAWake is the one outcome that
        // gets to describe a message it did not act on, so it describes the
        // shape and not the contents.
        val subject = wake(this)

        val outcome = subject.onDataMessage(mapOf("payment_hash" to "deadbeefcafe"))

        assertTrue(outcome is WakeOutcome.NotAWake)
        assertEquals(listOf("payment_hash"), (outcome as WakeOutcome.NotAWake).keys)
        assertTrue(
            "the outcome quotes a payload value: $outcome",
            "deadbeefcafe" !in outcome.toString(),
        )
    }

    @Test
    fun `a device with no wallet is not woken, and nothing is promoted`() =
        runTest(UnconfinedTestDispatcher()) {
            // A fresh install can hold an FCM token before it holds a seed, and a
            // wiped one holds a token afterwards. Starting here would build a node
            // against a vault that reads null; refusing costs nothing and the
            // notification never goes up.
            val presence = RecordingPresence()
            val starts = AtomicInteger()
            val subject = wake(
                this,
                presence = presence,
                state = WalletState.Uninitialized,
                start = { starts.incrementAndGet() },
            )

            val outcome = subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

            assertEquals(WakeOutcome.NoWallet, outcome)
            assertEquals(0, starts.get())
            assertEquals(emptyList<String>(), presence.events)
        }

    @Test
    fun `a locked wallet is woken, because that is the whole claim`() =
        runTest(UnconfinedTestDispatcher()) {
            // K2. The seed is behind a non-auth-bound Keystore key (BIT-8 rule 2)
            // precisely so a payment can arrive with the user nowhere near the
            // device. A wake that waited for WalletState.Ready would be a wake
            // that only ever fired while the app was already open.
            val starts = AtomicInteger()
            val subject = wake(this, state = WalletState.Locked, start = { starts.incrementAndGet() })

            subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

            assertEquals(1, starts.get())
        }

    @Test
    fun `a start that throws releases the process`() = runTest(UnconfinedTestDispatcher()) {
        // WalletNodeHost demotes on its own definite failures, so on that path
        // this is a second stopService on a stopped service. The path this is
        // for is a start that threw before reaching the host at all — which
        // would otherwise leave a foreground notification the user cannot
        // dismiss over a node that does not exist.
        val presence = RecordingPresence()
        val boom = IllegalStateException("no node")
        val subject = wake(this, presence = presence, start = { throw boom })

        subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

        assertEquals(listOf("promote", "demote"), presence.events)
        val last = subject.last.value
        assertTrue("expected WakeFailed, got $last", last is WakeOutcome.WakeFailed)
        assertSame(boom, (last as WakeOutcome.WakeFailed).cause)
    }

    @Test
    fun `the outcome is settled before the start finishes`() = runTest(UnconfinedTestDispatcher()) {
        // onMessageReceived gets a verdict back on its own thread. The message
        // handler is not allowed to block for the length of a node start — that
        // is tens of seconds, and FirebaseMessagingService's own budget for the
        // callback is about ten.
        val held = CompletableDeferred<Unit>()
        val subject = wake(this, start = { held.await() })

        val outcome = subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

        assertEquals(WakeOutcome.Waking("payment"), outcome)
        assertEquals(WakeOutcome.Waking("payment"), subject.last.value)
        held.complete(Unit)
        assertEquals(WakeOutcome.Woken("payment"), subject.last.value)
    }

    @Test
    fun `two wakes both reach the start, because collapsing them is the host's job`() =
        runTest(UnconfinedTestDispatcher()) {
            // FCM redelivers, and deduplicating here would be a second answer to
            // a question NodeLifecycle.startOnce already answers — with the
            // difference that this one has no way to know whether the node it is
            // suppressing a start for is still up.
            val starts = AtomicInteger()
            val subject = wake(this, start = { starts.incrementAndGet() })

            subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))
            subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

            assertEquals(2, starts.get())
        }

    @Test
    fun `every outcome is reported`() = runTest(UnconfinedTestDispatcher()) {
        // The log line is the only trace a wake leaves on a device nobody is
        // looking at, and the outcomes that did nothing are the ones a bug
        // report needs — "the push arrived and was not a wake" and "the push
        // never arrived" are otherwise the same silence.
        val seen = mutableListOf<WakeOutcome>()
        val subject = wake(this, report = { seen += it })

        subject.onDataMessage(emptyMap())
        subject.onDataMessage(mapOf(BackgroundWake.WAKE_KEY to "payment"))

        assertEquals(
            listOf(
                WakeOutcome.NotAWake(emptyList()),
                WakeOutcome.Waking("payment"),
                WakeOutcome.Woken("payment"),
            ),
            seen,
        )
    }
}
