package com.bittr.android.buy

import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.push.DepositCodeSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * The customer store behind the push handlers' deposit code — the first non-empty
 * `ibanEntities[].yourUniqueCode`, which `htlc-interceptor/ready` and the payouts are keyed on.
 * `PushHandlingModule` declares the hook optional; this is what fills it.
 */
@Module
@InstallIn(SingletonComponent::class)
object BuyPushHooksModule {

    @Provides
    fun provideDepositCodeSource(store: BittrCustomerStore): DepositCodeSource =
        DepositCodeSource { store.firstDepositCode() }
}
