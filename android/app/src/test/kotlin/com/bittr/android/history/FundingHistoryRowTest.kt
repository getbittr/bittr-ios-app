package com.bittr.android.history

import com.bittr.android.core.swaps.FileSwapStore
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The purchase that funded bittr's channel is not a payment of the node, so the history lists it
 * from the cache — as iOS lists `CacheManager.getLightningTransactions()` (`buy_incoming.yaml` opens
 * it as `history.transactionButton0`).
 */
class FundingHistoryRowTest {

    private val raw = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = true))
    private val funding = MutableStateFlow<List<WalletActivity>>(emptyList())
    private val descriptions = object : TransactionDescriptionStore {
        override val descriptions: StateFlow<Map<String, String>> = MutableStateFlow(emptyMap())
        override fun store(key: String, description: String) = Unit
    }

    private val source = MatchedWalletOverviewSource(
        raw = object : WalletOverviewSource {
            override val overview: StateFlow<WalletOverview> = raw
        },
        descriptions = descriptions,
        swaps = FileSwapStore(Files.createTempDirectory("swaps").toFile()),
        scope = CoroutineScope(Dispatchers.Unconfined),
        fundingRows = funding,
    )

    private fun row(id: String, timestamp: Long, received: Long = 1_000L) = WalletActivity(
        id = id,
        receivedSats = received,
        sentSats = 0L,
        feeSats = 0L,
        timestampSecs = timestamp,
        isLightning = true,
        confirmationHeight = null,
    )

    @Test
    fun `a cached funding purchase shows as soon as it is cached, without a node reading`() {
        assertEquals(emptyList<WalletActivity>(), source.overview.value.transactions)
        funding.value = listOf(row("funding", 100L, received = 187_207L))
        assertEquals(listOf("funding"), source.overview.value.transactions.map { it.id })
        assertEquals(187_207L, source.overview.value.transactions.single().receivedSats)
    }

    @Test
    fun `cached rows sort in with the node's rows, newest first`() {
        raw.value = raw.value.copy(transactions = listOf(row("payment-new", 300L), row("payment-old", 50L)))
        funding.value = listOf(row("funding", 100L))
        assertEquals(listOf("payment-new", "funding", "payment-old"), source.overview.value.transactions.map { it.id })
    }

    @Test
    fun `a cached row the node already lists is not shown twice`() {
        raw.value = raw.value.copy(transactions = listOf(row("same", 200L)))
        funding.value = listOf(row("same", 100L))
        assertEquals(listOf(200L), source.overview.value.transactions.map { it.timestampSecs })
    }
}
