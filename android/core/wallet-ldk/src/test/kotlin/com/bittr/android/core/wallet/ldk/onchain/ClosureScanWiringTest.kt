package com.bittr.android.core.wallet.ldk.onchain

import com.bittr.android.core.wallet.ldk.adapter.lightningNodePort
import com.bittr.android.core.wallet.ldk.cache.CachedChannelClosureStore
import com.bittr.android.core.wallet.ldk.cache.FileWalletCache
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.PendingSweepView
import com.bittr.android.core.wallet.ldk.lightning.ReadingOnlyPort
import com.bittr.android.core.wallet.ldk.lightning.WalletBalanceReader
import com.bittr.android.core.wallet.ldk.lightning.balances
import com.bittr.android.core.wallet.ldk.lightning.channel
import com.bittr.android.core.wallet.ldk.lightning.openChannelFundingTxIds
import com.bittr.android.core.wallet.ldk.lightning.reading
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The closure scan as `di/WalletModule` composes it, minus the one part that
 * needs a device.
 *
 * `ChannelClosureRecorder` has three collaborators and they come from three
 * layers — `cache/` holds the store, `adapter/` holds the wallet's transaction
 * list, and the channel list comes from `lightning/`. Each has its own test and
 * every one of those tests passes with the recorder wired to nothing, which is
 * exactly the state BIT-124 and BIT-128 left production in: `OnchainSync` was
 * constructed without `closures` and no closure was ever recorded on a running
 * app.
 *
 * So what this asserts is the **join**, in the shape `WalletModule` writes it:
 *
 * ```kotlin
 * ChannelClosureRecorder(
 *     store = CachedChannelClosureStore(cache),
 *     transactions = onchainWallet.transactions,
 *     openChannelFundingTxIds = { lightning.listChannels().openChannelFundingTxIds() },
 * )
 * ```
 *
 * with a real `FileWalletCache` for the store and the real channel-list
 * expression for the third argument. `transactions` is the substitution: it is
 * `BdkWalletTransactions` in production and every call on that path crosses into
 * Rust, so it is stubbed here and belongs to the regtest suite instead. That
 * split is the module's rule rather than a shortcut — a claim whose test needs
 * hardware CI does not have is a claim with no test.
 */
class ClosureScanWiringTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var directory: File

    private val funding = TxOutpoint(txId = "f".repeat(64), vout = 1u)

    /** The only transaction the wallet knows, and it spends the funding output. */
    private val closingTransaction = listOf("closing-txid" to listOf(funding))

    @Before
    fun setUp() {
        directory = temporaryFolder.newFolder("cache")
        store().store(funding)
    }

    private fun store() = CachedChannelClosureStore(FileWalletCache(directory))

    /**
     * @param channels what `listChannels()` answers at the moment the scan runs.
     *   Read through the same extension the production lambda uses, which is the
     *   part being asserted.
     */
    private fun recorder(
        channels: () -> List<ChannelView>,
        transactions: WalletTransactions = WalletTransactions { closingTransaction },
    ) = ChannelClosureRecorder(
        store = store(),
        transactions = transactions,
        openChannelFundingTxIds = { channels().openChannelFundingTxIds() },
    )

    @Test
    fun `a channel that is still open is not scanned for its own closure`() {
        var walks = 0
        val recorded = recorder(
            channels = { listOf(channel(fundingTxo = funding)) },
            transactions = { walks++; closingTransaction },
        ).record()

        assertNull(
            "The funding transaction is still backing a live channel, so nothing has " +
                "closed. Scanning here is how iOS's guard gets dropped in a port.",
            recorded,
        )
        assertEquals("The wallet's transactions were not walked at all.", 0, walks)
        assertEquals(
            "The outpoint is still being watched, because the closure has not happened.",
            funding,
            store().channelFundingOutpoint(),
        )
    }

    /**
     * The case `activeChannel()` would get wrong. A channel that is opening has
     * an unspent funding output, so treating it as closed starts the scan on
     * every sync until it confirms — and `openChannelFundingTxIds` is the
     * function that must not filter on `isChannelReady`.
     */
    @Test
    fun `a channel that is still pending is not scanned either`() {
        val recorded = recorder(
            channels = { listOf(channel(isChannelReady = false, fundingTxo = funding)) },
        ).record()

        assertNull(recorded)
        assertEquals(funding, store().channelFundingOutpoint())
    }

    @Test
    fun `a channel that has gone records its closing transaction`() {
        val recorded = recorder(channels = { emptyList() }).record()

        assertEquals("closing-txid", recorded)
        assertEquals(listOf("closing-txid"), store().closureTxIds())
        assertNull(
            "Watched no longer, so the next sync short-circuits.",
            store().channelFundingOutpoint(),
        )
    }

    /**
     * The claim `WalletModule`'s comment makes, as a test.
     *
     * A torn-down node — or the unconfigured build, which is what
     * `lightningNodePort(null)` is — answers `listChannels()` with an empty list
     * rather than throwing, per `LightningNodePort`'s read contract. That makes
     * `shouldScan` say yes about a channel that may still be open, and the
     * question is what that costs.
     *
     * It costs a walk of the transaction list and nothing else, because the
     * second step matches on the funding **outpoint** and an open channel's
     * funding output has not been spent. A wallet full of ordinary payments —
     * including one spending the *other* output of the very transaction that
     * funded the channel — records no closure. Had `ChannelClosureScan` matched
     * on the txid alone, this test would be the user being shown a channel
     * closure that has not happened, with the outpoint cleared so the real one
     * is never found.
     */
    @Test
    fun `no node answers no open channels, and the scan still records nothing`() {
        val noNode = lightningNodePort(null)
        assertEquals(emptyList<String>(), noNode.listChannels().openChannelFundingTxIds())

        val recorded = recorder(
            channels = { noNode.listChannels() },
            transactions = {
                listOf(
                    // Spends the funding transaction's *change* output, not the
                    // channel's. Same txid, different vout.
                    "change-spend" to listOf(TxOutpoint(txId = funding.txId, vout = 0u)),
                    "unrelated" to listOf(TxOutpoint(txId = "a".repeat(64), vout = 0u)),
                )
            },
        ).record()

        assertNull(
            "An open channel whose node has gone is not a closed channel.",
            recorded,
        )
        assertEquals(funding, store().channelFundingOutpoint())
    }

    // ---- The other half of the join: who writes the outpoint. ----

    /**
     * BIT-144's premise, as a test that fails on the code as it stood.
     *
     * Every test above begins by calling `store().store(funding)` in [setUp] — a
     * write no production code made. That is what the issue is about: the scan
     * was reachable and could never fire, because `channel_funding_outpoint` had
     * no writer in `main` and `shouldScan` short-circuits on a null outpoint.
     *
     * So this one does **not** seed the cache. It runs the real
     * `WalletBalanceReader` over a wallet with one live channel, exactly as
     * `WalletModule` composes it, and then runs the real recorder against the
     * same file-backed store — first while the channel is open, then after it has
     * gone. Delete the `?.let(closures::store)` from the reader and the second
     * half records nothing.
     */
    @Test
    fun `the balance read writes the outpoint the closure scan later needs`() {
        val fresh = temporaryFolder.newFolder("unseeded")
        val cache = CachedChannelClosureStore(FileWalletCache(fresh))
        var channels = listOf(channel(fundingTxo = funding))

        assertNull(
            "The state this issue found production in: nothing has written the " +
                "outpoint, so the scan cannot run.",
            cache.channelFundingOutpoint(),
        )

        val reader = WalletBalanceReader(
            node = ReadingOnlyPort(reading(channels = channels)),
            closures = cache,
        )
        val recorder = ChannelClosureRecorder(
            store = cache,
            transactions = WalletTransactions { closingTransaction },
            openChannelFundingTxIds = { channels.openChannelFundingTxIds() },
        )

        assertNotNull(reader.read())
        assertEquals(
            "iOS's storeChannelFundingOutpoint, on Android's trigger.",
            funding,
            cache.channelFundingOutpoint(),
        )

        // The channel is still open, so the scan still stands down — the outpoint
        // being present is not on its own a reason to record a closure.
        assertNull(recorder.record())

        // And now it has gone. The recorder finds the transaction spending the
        // outpoint the reader cached, which is the sequence that recorded nothing
        // on a running app before this issue.
        channels = emptyList()
        assertEquals("closing-txid", recorder.record())
        assertEquals(listOf("closing-txid"), cache.closureTxIds())
        assertNull(cache.channelFundingOutpoint())
    }

    /**
     * The key's two writers, over one real store.
     *
     * `storeChannelClosureTxIds` is a union rather than a replace, and this is
     * the pair that argument is about: the recorder writes the cooperative
     * closure it found, and the balance read writes the sweep txids from
     * `pendingBalancesFromChannelClosures`. Under replace semantics whichever ran
     * last would erase the other's, and the loop runs them one after another on
     * every tick — so the erasure would be permanent rather than occasional.
     */
    @Test
    fun `the recorder's closure and the balance read's sweeps both survive`() {
        val fresh = temporaryFolder.newFolder("two-writers")
        val cache = CachedChannelClosureStore(FileWalletCache(fresh))
        cache.store(funding)

        assertEquals(
            "closing-txid",
            ChannelClosureRecorder(
                store = cache,
                transactions = WalletTransactions { closingTransaction },
                openChannelFundingTxIds = { emptyList() },
            ).record(),
        )

        WalletBalanceReader(
            node = ReadingOnlyPort(
                reading(
                    balances = balances(
                        pendingBalancesFromChannelClosures = listOf(
                            PendingSweepView.AwaitingThresholdConfirmations(9_000uL, "sweep-tx"),
                        ),
                    ),
                ),
            ),
            closures = cache,
        ).read()

        assertEquals(
            "A replace in either writer loses the other's txid, and the user loses " +
                "sight of a closure that has happened.",
            listOf("closing-txid", "sweep-tx"),
            cache.closureTxIds(),
        )
    }
}
