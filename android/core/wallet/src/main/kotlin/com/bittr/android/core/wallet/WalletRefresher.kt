package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Home's pull-to-refresh — `ios/bittr/Home/ReloadWallet.swift`: resync the wallet now.
 *
 * While a refresh runs the wallet reports itself as not synced
 * ([WalletOverview.hasSynced] false), which is iOS's `walletHasSynced = false` after
 * `resetWallet()`: the balance and history are hidden, `home.headerSpinner` spins, and Send
 * and Receive take their syncing guard until the fresh reading lands.
 */
interface WalletRefresher {

    /** A refresh is running. */
    val isRefreshing: StateFlow<Boolean>

    /**
     * Start a refresh, unless one is already running or the wallet has not synced yet (iOS
     * ignores the pull while `headerSpinner` is animating).
     *
     * @return true when a refresh was started.
     */
    fun refresh(): Boolean

    /** A build with no node: nothing to resync. */
    object None : WalletRefresher {
        override val isRefreshing: StateFlow<Boolean> = MutableStateFlow(false)
        override fun refresh(): Boolean = false
    }
}
