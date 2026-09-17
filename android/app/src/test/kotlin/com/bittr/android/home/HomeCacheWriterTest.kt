package com.bittr.android.home

import com.bittr.android.core.wallet.CachedHome
import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HomeCacheWriterTest {

    private val saved = mutableListOf<WalletOverview>()
    private var clears = 0

    private val cache = object : HomeCache {
        override val cached = MutableStateFlow<CachedHome?>(null)
        override fun saveOverview(overview: WalletOverview) {
            saved += overview
            cached.value = CachedHome.of(overview, cached.value)
        }
        override fun savePrice(price: FiatPrice) = Unit
        override fun saveProfit(profit: CachedProfit) = Unit
        override fun clear() {
            clears++
            cached.value = null
        }
    }

    private val overview = MutableStateFlow(WalletOverview(hasNode = true))
    private val state = MutableStateFlow(WalletState.Locked)
    private val scope = CoroutineScope(Dispatchers.Unconfined)

    private fun start() = HomeCacheWriter(
        cache = cache,
        overview = object : WalletOverviewSource {
            override val overview: StateFlow<WalletOverview> = this@HomeCacheWriterTest.overview
        },
        walletState = state,
        scope = scope,
    ).start()

    @After
    fun tearDown() = scope.cancel()

    @Test
    fun `every synced reading is saved, an unsynced one is not`() {
        start()
        overview.value = WalletOverview(hasNode = true, hasSynced = false, satoshisOnchain = 5)
        assertEquals(emptyList<WalletOverview>(), saved)

        val reading = WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 10)
        overview.value = reading
        assertEquals(listOf(reading), saved)
    }

    @Test
    fun `no wallet clears the cache, and the removed wallet's reading is not written back`() {
        state.value = WalletState.Ready
        start()
        val oldWallet = WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 99)
        overview.value = oldWallet
        assertEquals(1, saved.size)

        state.value = WalletState.Uninitialized
        assertEquals(1, clears)
        assertNull(cache.cached.value)

        // A new wallet, but the node has not read it yet: the old reading must not come back.
        state.value = WalletState.Ready
        overview.value = oldWallet.copy()
        assertEquals(1, saved.size)
        assertNull(cache.cached.value)

        val newWallet = WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 1)
        overview.value = newWallet
        assertEquals(newWallet, saved.last())
        assertEquals(1L, cache.cached.value!!.totalSatoshis)
    }

    @Test
    fun `a launch with no wallet clears a leftover cache`() {
        cache.cached.value = CachedHome(hasReading = true, satoshisOnchain = 42)
        state.value = WalletState.Uninitialized
        start()
        assertEquals(1, clears)
        assertNull(cache.cached.value)
    }
}
