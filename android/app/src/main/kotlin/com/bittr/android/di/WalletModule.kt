package com.bittr.android.di

import android.content.Context
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.keystore.KeystoreSecureStore
import com.bittr.android.core.wallet.seed.SeedWalletService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * The one place the app names a wallet implementation.
 *
 * Today that is [SeedWalletService] over a Keystore-backed [SecureStore]: a real
 * BIP-39 seed, a real PIN gate, and no funds. `:core:wallet-stub` is still in the
 * build for the flows that must not touch key material.
 *
 * BIT-6 replaces the body of [provideWalletService] with the ldk-node/BDK-backed
 * service and swaps the dependency in `app/build.gradle.kts`. Nothing else in the
 * app should need to change — if it does, something has taken a dependency on the
 * implementation instead of on [WalletService], and that is the seam leaking.
 */
@Module
@InstallIn(SingletonComponent::class)
object WalletModule {

    @Provides
    @Singleton
    fun provideSecureStore(@ApplicationContext context: Context): SecureStore =
        KeystoreSecureStore(context)

    @Provides
    @Singleton
    fun provideWalletService(store: SecureStore): WalletService = SeedWalletService(store)
}
