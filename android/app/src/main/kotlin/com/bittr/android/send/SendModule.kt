package com.bittr.android.send

import androidx.lifecycle.ViewModel
import com.bittr.android.BuildConfig
import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.di.WalletComposition
import com.bittr.android.feature.send.SendSource
import com.bittr.android.receive.BitcoinPriceSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton

/** Send's bindings: the source over the one wallet composition, and the fee estimates it reads. */
@Module
@InstallIn(SingletonComponent::class)
object SendModule {

    @Provides
    @Singleton
    fun provideMempoolFeeEstimates(http: HttpClient): MempoolFeeEstimates = MempoolFeeEstimates(http)

    @Provides
    @Singleton
    fun provideSendSource(
        composition: WalletComposition,
        fees: MempoolFeeEstimates,
        preferences: AppPreferences,
        prices: BitcoinPriceSource,
    ): SendSource = AppSendSource(
        lightning = composition.lightning,
        onchain = composition.onchain,
        onchainSend = composition.onchainSend,
        overview = composition.overview,
        refresh = composition.refresh,
        fees = fees,
        preferences = preferences,
        prices = prices,
        network = BitcoinNetwork.fromBuildConfig(BuildConfig.BITCOIN_NETWORK),
    )
}

/** How the navigation graph reaches [SendSource] — `:feature:send` has no Hilt of its own. */
@HiltViewModel
class SendViewModel @Inject constructor(val source: SendSource) : ViewModel()
