package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.WalletRefresher
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Home's pull-to-refresh over the running wallet — `HomeViewController.scrollViewDidScroll`,
 * `resetWallet()` and what follows it (`ios/bittr/Home/ReloadWallet.swift`).
 *
 * The order is iOS's:
 *  1. **Reset at once.** [markResyncing] reports the wallet as not synced, so Home hides the
 *     balance and history and spins `home.headerSpinner`.
 *  2. **One second later**, sync the node ([syncNode] — `startWallet()`'s `syncWallets()`),
 *     then the on-chain wallet ([syncOnchain] — `didSyncBdkWallet`), which ends with a fresh
 *     balance reading published to Home (`finalizeSync()`).
 *  3. If the on-chain sync did not produce a reading — it timed out, or the node could not be
 *     read — take one directly ([readNow]).
 *  4. [endResync] always runs last. It is a no-op when a reading landed, and otherwise puts the
 *     previous overview back, so a refresh that failed half-way never leaves Home spinning with
 *     no balance.
 *
 * A failed step is reported to [onFailure] and the refresh carries on, as iOS's `try?` does.
 *
 * @param canResync the wallet has a node and has synced — iOS only reacts to the pull when the
 *   header spinner is not already spinning.
 * @param syncOnchain one on-chain sync through the sync loop's own coroutine, returning whether a
 *   balance reading was published. Run through the loop so it never races the loop's timer.
 */
class WalletResync(
    private val scope: CoroutineScope,
    private val canResync: () -> Boolean,
    private val markResyncing: () -> Unit,
    private val endResync: () -> Unit,
    private val syncNode: () -> Unit,
    private val syncOnchain: suspend () -> Boolean,
    private val readNow: () -> Boolean,
    private val settleMillis: Long = SETTLE_MILLIS,
    private val onchainTimeoutMillis: Long = ONCHAIN_TIMEOUT_MILLIS,
    private val onFailure: (Throwable) -> Unit = {},
) : WalletRefresher {

    private val _isRefreshing = MutableStateFlow(false)
    override val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    override fun refresh(): Boolean {
        if (!canResync()) return false
        if (!_isRefreshing.compareAndSet(false, true)) return false
        markResyncing()
        scope.launch {
            try {
                delay(settleMillis)
                step { syncNode() }
                val read = withTimeoutOrNull(onchainTimeoutMillis) { step { syncOnchain() } ?: false } ?: false
                if (!read) step { readNow() }
            } finally {
                endResync()
                _isRefreshing.value = false
            }
        }
        return true
    }

    private inline fun <T> step(block: () -> T): T? = try {
        block()
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (failure: Exception) {
        onFailure(failure)
        null
    }

    companion object {
        /** iOS's `asyncAfter(deadline: .now() + 1)` between the reset and the sync. */
        const val SETTLE_MILLIS: Long = 1_000L

        /** How long the on-chain sync may take before Home reads the wallet directly. */
        const val ONCHAIN_TIMEOUT_MILLIS: Long = 90_000L
    }
}
