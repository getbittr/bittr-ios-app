package com.bittr.android.di

import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.stub.StubWalletService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * The one place the app names a wallet implementation.
 *
 * BIT-6 replaces the body of [provideWalletService] with the ldk-node/BDK-backed
 * service and swaps the `:core:wallet-stub` dependency in `app/build.gradle.kts`.
 * Nothing else in the app should need to change — if it does, something has taken
 * a dependency on the implementation instead of on [WalletService], and that is
 * the seam leaking.
 */
@Module
@InstallIn(SingletonComponent::class)
object WalletModule {

    @Provides
    @Singleton
    fun provideWalletService(): WalletService = StubWalletService()
}
