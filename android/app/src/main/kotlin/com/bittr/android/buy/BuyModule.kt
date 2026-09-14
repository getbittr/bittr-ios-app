package com.bittr.android.buy

import android.content.Context
import androidx.lifecycle.ViewModel
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.FileBittrCustomerStore
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.di.WalletComposition
import com.bittr.android.feature.buy.BuySource
import com.bittr.android.feature.buy.ProfitSummary
import com.bittr.android.receive.BitcoinPriceSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow

@Module
@InstallIn(SingletonComponent::class)
object BuyModule {

    /**
     * The customer records, under `no_backup` and one file per backend — iOS scopes the same
     * cache by environment, so a debug build never shows a production deposit code.
     */
    @Provides
    @Singleton
    fun provideCustomerStore(
        @ApplicationContext context: Context,
        environment: BittrEnvironment,
    ): BittrCustomerStore = FileBittrCustomerStore(
        File(File(context.noBackupFilesDir, "bittr"), "customer-${environment.name.lowercase()}.json"),
    )

    @Provides
    @Singleton
    fun provideBuySource(
        @ApplicationContext context: Context,
        store: BittrCustomerStore,
        environment: BittrEnvironment,
        http: HttpClient,
        signer: BittrRequestSigner,
        tokens: DeviceTokenSource,
        composition: WalletComposition,
    ): BuySource = AppBuySource(
        store = store,
        environment = environment,
        http = http,
        signer = signer,
        keys = composition.registration,
        tokens = tokens,
        notifications = NotificationAccess(context),
    )

    @Provides
    @Singleton
    fun provideProfits(
        store: BittrCustomerStore,
        composition: WalletComposition,
        prices: BitcoinPriceSource,
        preferences: AppPreferences,
        http: HttpClient,
        environment: BittrEnvironment,
        signer: BittrRequestSigner,
    ): AppProfits = AppProfits(
        store = store,
        overview = composition.overview,
        prices = prices,
        preferences = preferences,
        http = http,
        environment = environment,
        signer = signer,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    ).also { it.start() }
}

@HiltViewModel
class BuyViewModel @Inject constructor(val source: BuySource) : ViewModel()

@HiltViewModel
class ProfitsViewModel @Inject constructor(profits: AppProfits) : ViewModel() {
    val summary: StateFlow<ProfitSummary?> = profits.summary
}
