package com.bittr.android.swap

import android.content.Context
import androidx.lifecycle.ViewModel
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.swaps.BoltzApi
import com.bittr.android.core.swaps.BoltzEndpoints
import com.bittr.android.core.swaps.BoltzWebhookMinter
import com.bittr.android.core.swaps.InvoiceFacts
import com.bittr.android.core.swaps.InvoiceInspector
import com.bittr.android.core.swaps.SwapCoordinator
import com.bittr.android.core.swaps.SwapStore
import com.bittr.android.core.swaps.WebhookUrlCache
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.ldk.adapter.Bolt11Decoder
import com.bittr.android.core.wallet.ldk.seed.SecureStoreSeedVault
import com.bittr.android.core.wallet.seed.SeedWalletService
import com.bittr.android.di.WalletComposition
import com.bittr.android.feature.swap.SwapFiat
import com.bittr.android.push.PrefsBoltzWebhookCache
import com.bittr.android.receive.BitcoinPriceSource
import com.bittr.android.send.MempoolFeeEstimates
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Swaps' bindings: one [SwapCoordinator] for the process, over the one wallet composition.
 *
 * No push handler is bound to the coordinator: iOS never claims or refunds from a swap push, it
 * only opens the status screen (`SwapPushHooksModule`).
 */
@Module
@InstallIn(SingletonComponent::class)
object SwapModule {

    @Provides
    @Singleton
    fun provideSwapCoordinator(
        @ApplicationContext context: Context,
        composition: WalletComposition,
        http: HttpClient,
        environment: BittrEnvironment,
        signer: BittrRequestSigner,
        tokens: DeviceTokenSource,
        fees: MempoolFeeEstimates,
        secureStore: SecureStore,
        swapStore: SwapStore,
        descriptions: TransactionDescriptionStore,
        history: com.bittr.android.core.wallet.WalletOverviewSource,
    ): SwapCoordinator {
        val endpoints = BoltzEndpoints.forEnvironment(environment)
        val webhookCache = PrefsBoltzWebhookCache(context)
        val vault = SecureStoreSeedVault(secureStore, SeedWalletService.KEY_SEED)
        return SwapCoordinator(
            api = BoltzApi(http, endpoints),
            wallet = AppSwapWallet(composition, fees, descriptions, mnemonic = vault::read, history = history),
            store = swapStore,
            pushGate = BoltzWebhookMinter(
                environment = environment,
                http = http,
                signer = signer,
                tokens = tokens,
                cache = object : WebhookUrlCache {
                    override fun urlFor(deviceToken: String): String? = webhookCache.urlFor(deviceToken)
                    override fun store(url: String, deviceToken: String) = webhookCache.store(url, deviceToken)
                },
            ),
            feed = OkHttpSwapStatusFeed(endpoints.webSocketUrl),
            invoices = InvoiceInspector { invoice -> Bolt11Decoder.decode(invoice)?.let { InvoiceFacts(it.amountMsat, it.paymentHashHex) } },
            // The process scope, as the wallet's is: a claim or refund outlives the screen that started it.
            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
        )
    }

    @Provides
    @Singleton
    fun provideSwapFiat(preferences: AppPreferences, prices: BitcoinPriceSource): SwapFiat = object : SwapFiat {
        override fun currencyCode(): String = preferences.currency.value.code
        override suspend fun pricePerBitcoin(): Double? = prices.price(preferences.currency.value)
    }
}

/** How the navigation graph reaches the coordinator — `:feature:swap` has no Hilt of its own. */
@HiltViewModel
class SwapViewModel @Inject constructor(val coordinator: SwapCoordinator, val fiat: SwapFiat) : ViewModel()
