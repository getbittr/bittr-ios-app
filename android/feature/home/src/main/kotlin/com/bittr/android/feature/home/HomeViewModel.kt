package com.bittr.android.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * What Home knows about the wallet.
 *
 * @property walletHasSynced the port of `CoreViewController.walletHasSynced` — the
 *   single boolean iOS gates Send, Receive, the balance card and the remove-wallet
 *   path on. **It is false for every build that has no wallet engine**, which is
 *   every build until BIT-6 lands, and that is not a placeholder: a wallet with no
 *   node genuinely has not synced. Every guard below is therefore the *iOS* guard,
 *   taking the *iOS* branch, showing the *iOS* alert — not an Android-only stub that
 *   has to be found and unpicked later.
 *
 *   See [HomeViewModel.walletHasSynced] for the one line BIT-6 changes.
 */
data class HomeUiState(
    val walletState: WalletState = WalletState.Uninitialized,
    val walletHasSynced: Boolean = false,
    val alert: HomeAlert? = null,
)

/**
 * An alert Home is showing. One button — `alert.button.0`, matching the index iOS
 * assigns the single dismissing button in `AlertManager`.
 */
data class HomeAlert(val title: String, val message: String)

@HiltViewModel
class HomeViewModel @Inject constructor(
    walletService: WalletService,
) : ViewModel() {

    private val alert = MutableStateFlow<HomeAlert?>(null)

    val uiState: StateFlow<HomeUiState> = walletService.state
        .map { HomeUiState(walletState = it, walletHasSynced = walletHasSynced(it)) }
        .stateIn(
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

    private companion object {
        const val STOP_TIMEOUT_MS = 5_000L

        /**
         * **The BIT-6 line.**
         *
         * `WalletState.Ready` means "key material is unlocked", which on iOS is a
         * strictly weaker claim than "the node has synced" — `CoreViewController`
         * tracks the two separately and only sets `walletHasSynced` in
         * `finalizeSync()`, after the chain sync completes. The seam has no way to
         * report the second one yet because there is no node to report it, so this
         * returns false unconditionally.
         *
         * When BIT-6 widens `WalletService` with a sync state, this becomes a read of
         * it and every guard above starts taking the other branch. Nothing else on
         * Home changes: the balance card, the profit pill and the transaction list are
         * the only things still missing at that point, and they are all additions to
         * [HomeScreen]'s header, not rewrites of it.
         */
        @Suppress("UNUSED_PARAMETER")
        fun walletHasSynced(state: WalletState): Boolean = false
    }
}
