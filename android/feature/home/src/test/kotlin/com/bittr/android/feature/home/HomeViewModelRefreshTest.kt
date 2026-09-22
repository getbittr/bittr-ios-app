package com.bittr.android.feature.home

import com.bittr.android.core.wallet.Mnemonic
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

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelRefreshTest {

    private val overview = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 1_000))

    /** Behaves like `WalletResync`: marks the wallet unsynced while it runs. */
    private val refresher = object : WalletRefresher {
        val running = MutableStateFlow(false)
        var starts = 0
        override val isRefreshing: StateFlow<Boolean> = running
        override fun refresh(): Boolean {
            starts++
            running.value = true
            overview.value = overview.value.copy(hasSynced = false)
            return true
        }
    }

    private var online = true

    private val wallet = object : WalletService {
        override val state: StateFlow<WalletState> = MutableStateFlow(WalletState.Ready)
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
            override val overview: StateFlow<WalletOverview> = this@HomeViewModelRefreshTest.overview
        },
        refresher = refresher,
        internet = { online },
        prices = { null },
    )

    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun `pulling a synced Home starts a refresh, which keeps the balance and spins the header`() = runTest {
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }
        assertTrue(home.uiState.value.canRefresh)

        home.refresh()
        assertEquals(1, refresher.starts)
        val state = home.uiState.value
        assertTrue(state.refreshing)
        assertFalse(state.canRefresh)
        assertEquals("the balance stays on screen during the refresh", 1_000L, state.balanceSats)
        assertFalse("Send and Receive stay guarded until the new reading", state.walletHasSynced)
        assertTrue(state.showSyncSpinner)

        home.refresh()
        assertEquals("no second refresh while one runs", 1, refresher.starts)
    }

    @Test
    fun `no refresh before the wallet has synced`() = runTest {
        overview.value = overview.value.copy(hasSynced = false)
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }
        assertFalse(home.uiState.value.canRefresh)

        home.refresh()
        assertEquals(0, refresher.starts)
    }

    /** `checkInternetConnection()`: offline, the pull says so instead of refreshing. */
    @Test
    fun `pulling while offline asks to check the connection and doesn't refresh`() = runTest {
        online = false
        val home = viewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { home.uiState.collect {} }

        home.refresh()
        assertEquals(0, refresher.starts)
        assertEquals(HomeAlert(HomeStrings.CHECK_YOUR_CONNECTION, HomeStrings.TRY_TO_CONNECT), home.currentAlert.value)
        assertTrue(home.uiState.value.canRefresh)
    }
}
