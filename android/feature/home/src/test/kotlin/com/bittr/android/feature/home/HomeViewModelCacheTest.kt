package com.bittr.android.feature.home

import com.bittr.android.core.wallet.CachedHome
import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletRefresher
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** `showCachedData()`: the last launch's balance, conversion and history while the wallet syncs. */
@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelCacheTest {

    private val overview = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = false))
    private val walletState = MutableStateFlow(WalletState.Ready)

    private val cachedRow = WalletActivity("cached-tx", 50_000, 0, 0, 1_789_000_000, false, 800)

    private val cache = object : HomeCache {
        val prices = mutableListOf<FiatPrice>()
        override val cached = MutableStateFlow<CachedHome?>(
            CachedHome(
                hasReading = true,
                satoshisOnchain = 293_076,
                transactions = listOf(cachedRow),
                currentHeight = 810,
                prices = mapOf("CHF" to 64_000.0),
                profit = CachedProfit(1, 2, 3, "CHF"),
            ),
        )
        override fun saveOverview(overview: WalletOverview) = Unit
        override fun savePrice(price: FiatPrice) {
            prices += price
        }
        override fun saveProfit(profit: CachedProfit) = Unit
        override fun clear() {
            cached.value = null
        }
    }

    private var livePrice: FiatPrice? = null

    private val refresher = object : WalletRefresher {
        val running = MutableStateFlow(false)
        override val isRefreshing: StateFlow<Boolean> = running
        override fun refresh(): Boolean {
            running.value = true
            overview.value = overview.value.copy(hasSynced = false)
            return true
        }
    }

    private val wallet = object : WalletService {
        override val state: StateFlow<WalletState> = walletState
        override fun lock() = Unit

        override suspend fun createWallet(): Mnemonic = error("unused")
        override suspend fun restoreWallet(mnemonic: Mnemonic) = Unit
        override suspend fun setPin(pin: String) = Unit
        override suspend fun unlock(pin: String) = true
        override suspend fun failedUnlockAttempts() = 0
        override suspend fun holdsSeed(mnemonic: Mnemonic) = true
        override suspend fun resetPin(mnemonic: Mnemonic, pin: String) = Unit
        override suspend fun removeWallet() = Unit
        override suspend fun start() = Unit
        override suspend fun stop() = Unit
    }

    private fun viewModel() = HomeViewModel(
        walletService = wallet,
        overview = object : WalletOverviewSource {
            override val overview: StateFlow<WalletOverview> = this@HomeViewModelCacheTest.overview
        },
        refresher = refresher,
        cache = cache,
        prices = object : FiatPriceSource {
            override suspend fun current(): FiatPrice? = livePrice
            override fun currentSymbol(): String = "CHF"
        },
    )

    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun `before the first sync Home shows the cached balance, conversion and history, and stays guarded`() = runTest {
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }
        val state = home.uiState.value

        assertTrue(state.showingCachedData)
        assertEquals(293_076L, state.balanceSats)
        assertEquals(balanceFiat(293_076, FiatPrice(64_000.0, "CHF")), state.balanceFiat)
        assertEquals(1, state.history.size)
        // iOS keeps `walletHasSynced` false: Send and Receive still say syncing, the spinner runs,
        // and the pull does nothing.
        assertFalse(state.walletHasSynced)
        assertTrue(state.showSyncSpinner)
        assertFalse(state.canRefresh)
    }

    @Test
    fun `the first live reading replaces the cached one`() = runTest {
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        overview.value = WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 1_000)
        val state = home.uiState.value
        assertFalse(state.showingCachedData)
        assertTrue(state.walletHasSynced)
        assertEquals(1_000L, state.balanceSats)
        assertTrue(state.history.isEmpty())
    }

    @Test
    fun `a live conversion rate replaces the cached one and is kept for next time`() = runTest {
        livePrice = FiatPrice(70_000.0, "CHF")
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        assertEquals(balanceFiat(293_076, FiatPrice(70_000.0, "CHF")), home.uiState.value.balanceFiat)
        assertEquals(listOf(FiatPrice(70_000.0, "CHF")), cache.prices)
    }

    @Test
    fun `a pull-to-refresh keeps the live figures rather than falling back to the cache`() = runTest {
        overview.value = WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 1_000)
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        home.refresh()
        val state = home.uiState.value
        assertTrue(state.refreshing)
        assertFalse(state.showingCachedData)
        assertEquals(1_000L, state.balanceSats)
        assertFalse(state.walletHasSynced)
    }

    @Test
    fun `no wallet, no cached data`() = runTest {
        walletState.value = WalletState.Uninitialized
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        assertFalse(home.uiState.value.showingCachedData)
        assertNull(home.uiState.value.balanceSats)
    }

    @Test
    fun `a cleared cache shows nothing`() = runTest {
        cache.clear()
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        assertFalse(home.uiState.value.showingCachedData)
        assertNull(home.uiState.value.balanceSats)
    }
}
