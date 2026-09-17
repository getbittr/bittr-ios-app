package com.bittr.android.home

import com.bittr.android.buy.AppProfits
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.di.WalletComposition
import com.bittr.android.events.TransactionConfirmations
import com.bittr.android.push.BittrPayoutTracker
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Empties everything the app holds in memory about a wallet once there is none — iOS's
 * `performWalletReset`: `resetNodeState()`, `bittrWallet = BittrWallet()` and
 * `CacheManager.deleteClientInfo()`.
 *
 * Without it the node's overview, the profit summary and the transaction-screen bookkeeping outlive
 * the removal, and a wallet created or restored in the same process shows the old one's figures until
 * its first reading replaces them. Runs on every transition to [WalletState.Uninitialized]; at a
 * launch with no wallet there is nothing to empty, which is harmless.
 *
 * Swap files are left alone, as iOS leaves them: they are the user's rescue artifact for Boltz.
 */
class RemovedWalletReset(
    private val walletState: StateFlow<WalletState>,
    private val scope: CoroutineScope,
    private val resets: List<() -> Unit>,
) {

    private val started = AtomicBoolean(false)

    /** Idempotent: the activity calls it from every `onCreate`. */
    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            walletState.collect { state ->
                if (state == WalletState.Uninitialized) resets.forEach { reset -> runCatching(reset) }
            }
        }
    }
}

@Module
@InstallIn(SingletonComponent::class)
object RemovedWalletResetModule {

    @Provides
    @Singleton
    fun provideRemovedWalletReset(
        wallet: WalletService,
        composition: WalletComposition,
        profits: AppProfits,
        customers: BittrCustomerStore,
        confirmations: TransactionConfirmations,
        payouts: BittrPayoutTracker,
        homeCache: HomeCache,
    ): RemovedWalletReset = RemovedWalletReset(
        walletState = wallet.state,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        resets = listOf(
            // `bittrWallet = BittrWallet()`: balance, channels, transactions, height.
            composition.resetOverview,
            // `deleteClientInfo()`: `walletcache`, `device`; and the profit figures computed from them.
            homeCache::clear,
            customers::clearAccount,
            profits::reset,
            // The payout iOS tracks as `lightningNotification`, and which rows were already opened.
            payouts::clear,
            confirmations::reset,
        ),
    )
}
