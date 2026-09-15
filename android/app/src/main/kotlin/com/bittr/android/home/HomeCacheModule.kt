package com.bittr.android.home

import android.content.Context
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

@Module
@InstallIn(SingletonComponent::class)
object HomeCacheModule {

    /**
     * What Home last showed, one file per backend under `no_backup` — iOS scopes `walletcache` by
     * environment the same way. Its writer starts with it, over the matched overview Home reads.
     */
    @Provides
    @Singleton
    fun provideHomeCache(
        @ApplicationContext context: Context,
        environment: BittrEnvironment,
        overview: WalletOverviewSource,
        wallet: WalletService,
    ): HomeCache = FileHomeCache(
        File(File(context.noBackupFilesDir, "bittr"), "home-cache-${environment.name.lowercase()}.json"),
    ).also { cache ->
        HomeCacheWriter(
            cache = cache,
            overview = overview,
            walletState = wallet.state,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
        ).start()
    }
}
