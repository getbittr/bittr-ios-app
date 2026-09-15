package com.bittr.android.receive

import com.bittr.android.core.network.BittrCustomerStore
import androidx.lifecycle.ViewModel
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.FiatPriceSource
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.di.WalletComposition
import com.bittr.android.feature.receive.ReceiveSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton

/** Receive's bindings: the source over the one wallet composition, and the price it reads. */
@Module
@InstallIn(SingletonComponent::class)
object ReceiveModule {

    @Provides
    @Singleton
    fun provideBitcoinPriceSource(environment: BittrEnvironment, http: HttpClient): BitcoinPriceSource =
        BitcoinPriceSource(environment, http)

    @Provides
    @Singleton
    fun provideFiatPriceSource(prices: BitcoinPriceSource, preferences: AppPreferences): FiatPriceSource =
        AppFiatPriceSource(prices, preferences)

    @Provides
    @Singleton
    fun provideReceiveSource(
        composition: WalletComposition,
        preferences: AppPreferences,
        prices: BitcoinPriceSource,
        descriptions: TransactionDescriptionStore,
        customers: BittrCustomerStore,
    ): ReceiveSource = AppReceiveSource(
        lightning = composition.lightning,
        addressPool = composition.addressPool,
        preferences = preferences,
        prices = prices,
        descriptions = descriptions,
        customers = customers,
    )
}

/**
 * How the navigation graph reaches [ReceiveSource]. `:feature:receive` has no Hilt of its
 * own — it takes the source as a parameter — so the graph asks for this and hands it over.
 */
@HiltViewModel
class ReceiveViewModel @Inject constructor(val source: ReceiveSource) : ViewModel()
