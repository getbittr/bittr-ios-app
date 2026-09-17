package com.bittr.android.buy

import android.content.Context
import androidx.lifecycle.ViewModel
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.DeviceTokenLifecycle
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
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.HomeCache
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

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
        deviceTokens: DeviceTokenLifecycle,
    ): BuySource = AppBuySource(
        store = store,
        environment = environment,
        http = http,
        signer = signer,
        keys = composition.registration,
        tokens = tokens,
        notifications = NotificationAccess(context),
        onRegistered = deviceTokens::onRegistered,
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
        homeCache: HomeCache,
    ): AppProfits = AppProfits(
        store = store,
        overview = composition.overview,
        fundingTxId = composition.channelFundingTxId,
        prices = prices,
        preferences = preferences,
        http = http,
        environment = environment,
        signer = signer,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
        homeCache = homeCache,
    ).also { it.start() }
}

@HiltViewModel
class BuyViewModel @Inject constructor(val source: BuySource) : ViewModel()

/**
 * Home's profit pill and the Profits screen: this launch's summary once it is computed, and the last
 * launch's cached one until then — `showCachedData()` runs `calculateProfit()` on the cached history.
 */
@HiltViewModel
class ProfitsViewModel @Inject constructor(profits: AppProfits, cache: HomeCache) : ViewModel() {
    val summary: StateFlow<ProfitSummary?> = combine(profits.summary, cache.cached) { live, cached ->
        live ?: cached?.profit?.toSummary()
    }.stateIn(viewModelScope, SharingStarted.Eagerly, profits.summary.value ?: cache.cached.value?.profit?.toSummary())
}

private fun CachedProfit.toSummary() = ProfitSummary(totalProfit, totalInvestment, currentValue, currencySymbol)
