package com.bittr.android

import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.di.WalletGraph
import dagger.hilt.android.EntryPointAccessors
import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/**
 * Getting K8's two tests to a running node, and reading the chain behind its back.
 *
 * BIT-132. Shared by [K8DozeMachineryTest] and [K8ChannelFreshnessTest], which
 * need the same two things and nothing else in common.
 *
 * **[K7InterruptedPaymentTest] deliberately keeps its own copy of the first
 * half.** Its version carries assertions about four instrumented runs sharing
 * one install — *"phase 1 created one and the phases share one install, so the
 * data directory was cleared between them"* — and those sentences are the value:
 * they name the exact harness failure a reader of a red phase 2 needs to check.
 * Generalising them into this file would cost a parameter meaning "which suite am
 * I" and a message that fits neither.
 */
internal object RegtestWallet {

    /**
     * The PIN every regtest suite on this branch uses.
     *
     * The same literal K7 and `SeedReadableWhileLockedTest` use, for the reason
     * K7 gives: one throwaway PIN in the repository is easier to grep for than
     * three, and no two of these suites ever share a device with a wallet that
     * outlives them.
     */
    const val PIN = "2468"

    /** The `WalletService` and ports the running application built for itself. */
    fun graph(): WalletGraph = EntryPointAccessors.fromApplication(
        InstrumentationRegistry.getInstrumentation().targetContext.applicationContext,
        WalletGraph::class.java,
    )

    /**
     * Get the wallet to [WalletState.Ready] with a node running.
     *
     * @param mayCreate whether finding no wallet is acceptable. True for
     *   [K8DozeMachineryTest], which runs in the undirected suite against
     *   whatever install AGP just made and owns its own wallet. **False for
     *   [K8ChannelFreshnessTest]**, which exists to measure the channel K7 left
     *   behind: a fresh wallet there would have no channel, and the test would
     *   then fail for "no channel" — a sentence that reads as a Doze finding and
     *   is really "the install was replaced between K7 and K8".
     *
     * `start()` is called unconditionally because it is the app's own idempotent
     * way in ([com.bittr.android.core.wallet.ldk.host.WalletNodeHost.start]), and
     * a wallet that is `Ready` with a node that has already died is not
     * distinguishable from here.
     */
    fun start(wallet: WalletService, mayCreate: Boolean) = runBlocking {
        if (wallet.state.value == WalletState.Uninitialized) {
            assertTrue(
                "This test found no wallet on the device. It needed the one an " +
                    "earlier run created — K7's four phases and this test share an " +
                    "install, which AGP preserves with `adb install -r` and " +
                    "`leaveApksInstalledAfterRun=true`. A wallet created here would " +
                    "have no channel and no funds, and every assertion below would " +
                    "then fail for a reason that has nothing to do with Doze.",
                mayCreate,
            )
            wallet.createWallet()
            wallet.setPin(PIN)
        }
        if (wallet.state.value != WalletState.Ready) {
            assertTrue(
                "unlock('$PIN') was refused on a wallet this suite created with that " +
                    "PIN. The device is carrying a wallet from something other than " +
                    "the regtest suite.",
                wallet.unlock(PIN),
            )
        }
        wallet.start()
        assertEquals(
            "The wallet did not reach Ready after start(). There is no node to put " +
                "into Doze, so nothing below would be a K8 result.",
            WalletState.Ready,
            wallet.state.value,
        )
    }

    /**
     * The chain's tip height, read from Esplora **by the device**, over a raw
     * socket.
     *
     * K8's freshness half has to establish that blocks were mined *while it was
     * idle*. The host is the only thing that can mine them, so the tempting
     * shape is to let the host state the heights in its hand-off — and then the
     * whole claim is host-asserted. This is the same principle K7 applied to its
     * kill window: *"the window was wide" is a device-side fact*.
     *
     * A raw socket rather than `HttpURLConnection`, for the reason
     * [RegtestEnvironmentTest] gives at length: `http://10.0.2.2:3002` is
     * cleartext, the app declares no `usesCleartextTraffic`, and the platform's
     * Java networking stack would refuse it on a network that is working
     * perfectly. ldk-node is unaffected because its Esplora client is Rust with
     * its own sockets — so a Java-level HTTP check here would measure a rule
     * that does not apply to the code under test.
     *
     * `RegtestEnvironmentTest` hand-writes its own copy of this rather than
     * calling here, and that is on purpose: it is the test that proves this path
     * works at all, and a guard whose green depends on the helper it is
     * validating proves nothing about either.
     *
     * @return the height, or null if Esplora did not answer a number — which
     *   during a forced idle window is a *plausible and interesting* outcome
     *   rather than an error, so the caller decides what it means.
     */
    fun esploraTipHeight(chainSourceUrl: String): Int? {
        val port = chainSourceUrl.substringAfterLast(':').toIntOrNull() ?: return null
        return runCatching {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(EMULATOR_HOST, port), CONNECT_TIMEOUT_MS)
                socket.soTimeout = READ_TIMEOUT_MS
                // HTTP/1.0: the server closes when the body ends, so readText()
                // terminates instead of waiting out soTimeout for a second request.
                socket.getOutputStream().write(
                    "GET /blocks/tip/height HTTP/1.0\r\nHost: $EMULATOR_HOST:$port\r\n\r\n"
                        .toByteArray(),
                )
                socket.getOutputStream().flush()
                socket.getInputStream().reader().readText()
                    .substringAfter("\r\n\r\n")
                    .trim()
                    .toIntOrNull()
            }
        }.getOrNull()
    }

    const val EMULATOR_HOST = "10.0.2.2"
    const val CONNECT_TIMEOUT_MS = 5_000
    const val READ_TIMEOUT_MS = 10_000
}
