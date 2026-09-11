package com.bittr.android.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * What the nav graph branches on: does a wallet exist, and is it unlocked.
 *
 * It exposes the service's own [StateFlow] rather than a copy, so the PIN screen
 * unlocking the wallet is the same event that moves navigation to home — there is no
 * second source of truth to get out of step.
 */
@HiltViewModel
class WalletGateViewModel @Inject constructor(
    private val wallet: WalletService,
) : ViewModel() {

    val walletState: StateFlow<WalletState> = wallet.state

    /** Check a PIN. False means wrong PIN, which is the expected case, not an error. */
    fun unlock(pin: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val unlocked = wallet.unlock(pin)
            if (unlocked) {
                // No node to bring up until BIT-6 — start() is the stub's no-op today,
                // but calling it here means the lifecycle hook already exists when it
                // is not.
                wallet.start()
            }
            onResult(unlocked)
        }
    }
}
