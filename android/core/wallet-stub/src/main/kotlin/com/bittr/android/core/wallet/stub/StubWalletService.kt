package com.bittr.android.core.wallet.stub

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Deterministic in-memory [WalletService], used by CI.
 *
 * It touches no disk, opens no sockets and reaches no Keystore — which is the point:
 * the Maestro harness has to be able to fail for exactly one reason (the app is
 * broken), not for eleven (node won't sync, regtest is down, channel didn't open).
 * Real wallet-backed flows arrive with :core:wallet-ldk in BIT-6.
 *
 * Since BIT-93 it walks the create-wallet arc too, so a flow can drive signup end to
 * end and assert against a phrase it knows in advance. State lives in memory only, so
 * every launch starts at [WalletState.Uninitialized] the way a fresh install does.
 *
 * ### This must never be the binding in a build a user could fund
 *
 * [PHRASE] is the BIP-39 specification's all-zero-entropy test vector. It is public,
 * it is in every BIP-39 test suite on earth, and any bitcoin sent to a wallet derived
 * from it is gone immediately. That is deliberate — a stub that minted plausible
 * *real* seeds would be far more dangerous, because the failure would be silent. The
 * app binds [com.bittr.android.core.wallet.seed.SeedWalletService] in
 * `di/WalletModule.kt`; this class is for tests and flows.
 */
class StubWalletService : WalletService {

    private val _state = MutableStateFlow(WalletState.Uninitialized)
    override val state: StateFlow<WalletState> = _state.asStateFlow()

    private var pin: String? = null

    override suspend fun createWallet(): Mnemonic {
        pin = null
        _state.value = WalletState.Uninitialized
        return PHRASE
    }

    override suspend fun setPin(pin: String) {
        this.pin = pin
        _state.value = WalletState.Locked
    }

    override suspend fun unlock(pin: String): Boolean {
        if (pin != this.pin) return false
        _state.value = WalletState.Ready
        return true
    }

    override suspend fun start() = Unit

    override suspend fun stop() = Unit

    companion object {
        /**
         * The BIP-39 all-zero-entropy test vector. Known to everyone, worth nothing —
         * see the class documentation.
         */
        val PHRASE = Mnemonic(
            listOf(
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about",
            ),
        )
    }
}
