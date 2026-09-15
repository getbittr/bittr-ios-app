package com.bittr.android.feature.home

import com.bittr.android.core.wallet.InternetConnection
import com.bittr.android.core.wallet.WalletRefresher

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * What Home knows about the wallet.
 *
 * @property walletHasSynced the port of `CoreViewController.walletHasSynced` — the
 *   single boolean iOS gates Send, Receive, the balance card and the remove-wallet
 *   path on. It becomes true with the wallet's first balance reading after the
 *   on-chain scan (`finalizeSync()`), and it is false for ever in a build with no
 *   node, because a wallet with no node genuinely has not synced.
 * @property showSyncSpinner `home.headerSpinner`: a node is running and has not synced
 *   yet. A build with no node shows none — there is nothing to wait for, and a spinner
 *   that never stops would hold every flow that waits for it to disappear.
 * @property balanceSats `setTotalSats()`, once synced; null before, so Home never shows a
 *   zero balance it has not read.
 */
data class HomeUiState(
    val walletState: WalletState = WalletState.Uninitialized,
    val walletHasSynced: Boolean = false,
    val showSyncSpinner: Boolean = false,
    val balanceSats: Long? = null,
    /** `conversionLabel` — the balance in the display currency, e.g. "CHF 190". */
    val balanceFiat: String? = null,
    val history: List<HistoryRow> = emptyList(),
    /** The sync overlay's first row: a conversion rate has been fetched. */
    val conversionFetched: Boolean = false,
    /** A pull-to-refresh resync is running (`ReloadWallet.swift`); the balance and history are hidden meanwhile. */
    val refreshing: Boolean = false,
    /** Pulling Home down resyncs the wallet: it has a node, has synced, and no refresh is running. */
    val canRefresh: Boolean = false,
)

/**
 * An alert Home is showing. One button — `alert.button.0`, matching the index iOS
 * assigns the single dismissing button in `AlertManager`.
 */
data class HomeAlert(val title: String, val message: String)

@HiltViewModel
class HomeViewModel @Inject constructor(
    walletService: WalletService,
    private val overview: WalletOverviewSource,
    private val refresher: WalletRefresher = WalletRefresher.None,
    private val internet: InternetConnection = InternetConnection.Always,
    prices: FiatPriceSource,
) : ViewModel() {

    private val alert = MutableStateFlow<HomeAlert?>(null)

    /** Re-fetched whenever the history changes, which is when a row needs converting. */
    private val price = MutableStateFlow<FiatPrice?>(null)

    init {
        // iOS fetches conversion rates first thing at start (`SyncType.conversion`), before the
        // wallet has synced; the sync overlay's first row reports it.
        viewModelScope.launch { prices.current()?.let { if (price.value == null) price.value = it } }
        // Refetched when the history changes and when Settings switches the currency —
        // Home stays on the back stack under Settings, so without the second trigger it
        // would keep showing the old currency until the next transaction.
        viewModelScope.launch {
            merge(
                overview.overview.map { it.hasSynced to it.transactions }.distinctUntilChanged(),
                prices.currencyChanges,
            ).collect {
                if (overview.overview.value.hasSynced) prices.current()?.let { price.value = it }
            }
        }
    }

    val uiState: StateFlow<HomeUiState> = combine(
        walletService.state,
        overview.overview,
        price,
        refresher.isRefreshing,
    ) { state, wallet, price, refreshing ->
        HomeUiState(
            walletState = state,
            walletHasSynced = wallet.hasSynced,
            showSyncSpinner = wallet.hasNode && !wallet.hasSynced,
            balanceSats = if (wallet.hasSynced) wallet.totalSatoshis else null,
            balanceFiat = if (wallet.hasSynced) balanceFiat(wallet.totalSatoshis, price) else null,
            history = if (wallet.hasSynced) historyRows(wallet.transactions, price, wallet.currentHeight) else emptyList(),
            conversionFetched = price != null,
            refreshing = refreshing,
            canRefresh = wallet.hasNode && wallet.hasSynced && !refreshing,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS),
        initialValue = HomeUiState(),
    )

    /**
     * The alert currently on screen, kept separate from [uiState] so that raising or
     * dismissing one does not have to re-derive wallet state.
     */
    val currentAlert: StateFlow<HomeAlert?> = alert.asStateFlow()

    fun showAlert(alert: HomeAlert) {
        this.alert.value = alert
    }

    fun dismissAlert() {
        alert.value = null
    }

    /**
     * Home was pulled down — `scrollViewDidScroll`'s `contentOffset.y < -200`. Ignored until the
     * wallet has synced and while a refresh is running, as iOS ignores it while `headerSpinner`
     * spins.
     */
    fun refresh() {
        if (!overview.overview.value.hasSynced || refresher.isRefreshing.value) return
        // `guard self.coreVC!.checkInternetConnection() else { return }`.
        if (!internet.isConnected()) {
            alert.value = HomeAlert(HomeStrings.CHECK_YOUR_CONNECTION, HomeStrings.TRY_TO_CONNECT)
            return
        }
        refresher.refresh()
    }

    private companion object {
        const val STOP_TIMEOUT_MS = 5_000L
    }
}
