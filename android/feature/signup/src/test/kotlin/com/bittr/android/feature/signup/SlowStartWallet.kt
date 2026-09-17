package com.bittr.android.feature.signup

import com.bittr.android.core.wallet.WalletService
import kotlinx.coroutines.CompletableDeferred

/**
 * A wallet whose node start hangs until the test releases [nodeUp].
 *
 * iOS lowers the PIN view and then starts the wallet behind Home; the tests that use
 * this prove Android does the same — that the screen moves on while the start is
 * still pending, and that the start was asked for at all.
 */
class SlowStartWallet(
    delegate: WalletService,
    private val nodeUp: CompletableDeferred<Unit> = CompletableDeferred(),
) : WalletService by delegate {

    var startRequested = false
        private set

    override suspend fun start() {
        startRequested = true
        nodeUp.await()
    }
}
