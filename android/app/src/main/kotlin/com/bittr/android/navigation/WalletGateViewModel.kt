package com.bittr.android.navigation

import androidx.lifecycle.ViewModel
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

/**
 * What the nav graph branches on: does a wallet exist, and is it unlocked.
 *
 * It exposes the service's own [StateFlow] rather than a copy, so the PIN screen
 * unlocking the wallet is the same event that moves navigation to home — there is no
 * second source of truth to get out of step. That is also why it is the *only* thing
 * here: checking the PIN, counting the failures and running the lockout all belong to
 * one screen and moved to [UnlockViewModel] with BIT-97, leaving this as the question
 * the graph asks and nothing else.
 */
@HiltViewModel
class WalletGateViewModel @Inject constructor(
    private val wallet: WalletService,
) : ViewModel() {

    val walletState: StateFlow<WalletState> = wallet.state
}
