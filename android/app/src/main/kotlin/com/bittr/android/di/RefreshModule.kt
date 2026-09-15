package com.bittr.android.di

import com.bittr.android.core.wallet.WalletRefresher
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/** Home's pull-to-refresh, over the one wallet composition — see `WalletResync`. */
@Module
@InstallIn(SingletonComponent::class)
object RefreshModule {

    @Provides
    fun provideWalletRefresher(composition: WalletComposition): WalletRefresher = composition.refresher
}
