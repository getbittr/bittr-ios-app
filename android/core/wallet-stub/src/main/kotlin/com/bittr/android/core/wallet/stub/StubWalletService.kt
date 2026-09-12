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

    /** The phrase the last [restoreWallet] was given, or null on the create path. */
    var restored: Mnemonic? = null
        private set

    override suspend fun createWallet(): Mnemonic {
        pin = null
        _state.value = WalletState.Uninitialized
        return PHRASE
    }

    /**
     * Accept whatever phrase the flow typed in, and remember it.
     *
     * [restored] is what makes the restore flow assertable: a stub that dropped the
     * phrase on the floor would let a build that restores the *wrong* wallet pass, so
     * the one thing this has to prove — that the words the user typed are the words
     * that got stored — would go untested.
     */
    override suspend fun restoreWallet(mnemonic: Mnemonic) {
        restored = mnemonic
        pin = null
        _state.value = WalletState.Uninitialized
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
