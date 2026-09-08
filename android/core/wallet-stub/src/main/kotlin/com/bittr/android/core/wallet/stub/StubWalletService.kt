package com.bittr.android.core.wallet.stub

import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Deterministic no-op [WalletService], used by the scaffold and by CI.
 *
 * It holds no key material, touches no disk, and opens no sockets — which is the
 * point: the Maestro harness has to be able to fail for exactly one reason (the
 * app is broken), not for eleven (node won't sync, regtest is down, channel
 * didn't open). Real wallet-backed flows arrive with :core:wallet-ldk in BIT-6.
 *
 * Reports [WalletState.Uninitialized] so the app lands on the signup entry point,
 * matching a fresh install on iOS.
 */
class StubWalletService : WalletService {

    private val _state = MutableStateFlow(WalletState.Uninitialized)
    override val state: StateFlow<WalletState> = _state.asStateFlow()

    override suspend fun start() = Unit

    override suspend fun stop() = Unit
}
