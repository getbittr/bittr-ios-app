package com.bittr.android.di

import android.content.Context
import com.bittr.android.BuildConfig
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.BoltzWebhookCache
import com.bittr.android.core.network.DeviceTokenCache
import com.bittr.android.core.network.DeviceTokenLifecycle
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.UnixClock
import com.bittr.android.core.network.okhttp.OkHttpBittrHttpClient
import com.bittr.android.core.push.DeviceTokenRetryBudget
import com.bittr.android.core.push.fcm.FirebaseDeviceTokenSource
import com.bittr.android.core.push.fcm.PushDelivery
import com.bittr.android.push.BittrPushDelivery
import com.bittr.android.push.PrefsBoltzWebhookCache
import com.bittr.android.push.PrefsDeviceTokenCache
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * The push object graph — BIT-41 item 3's wiring.
 *
 * Two of the bindings below are deliberately **not** implemented yet, and both are named here
 * rather than hidden, because each is a one-line swap for the issue that owns it and hiding them
 * would make this graph look complete when it is not. `DeviceTokenLifecycle` treats both as
 * ordinary states — not errors — so the app behaves correctly today: it holds a live FCM
 * registration, decodes pushes, and declines to post a token it cannot sign for.
 */
@Module
@InstallIn(SingletonComponent::class)
object PushModule {

    /**
     * The single HTTP client for the whole app.
     *
     * `:app` is where it is built, so that "who can reach the bittr API" stays a question about
     * one dependency block. [OkHttpBittrHttpClient] is the only implementation of [HttpClient]
     * in the repo and the only class allowed to open a socket.
     */
    @Provides
    @Singleton
    fun provideHttpClient(): HttpClient = OkHttpBittrHttpClient()

    /**
     * Which backend this build talks to, read from the name `:app` compiles in.
     *
     * Throws on an unrecognised value rather than guessing, because neither default is safe:
     * `PRODUCTION` points a mistyped debug build at the real backend — the BIT-32 harm — and
     * `DEVELOPMENT` ships a release build talking to staging. `ApiEnvironmentFlagTest` covers
     * both variants.
     */
    @Provides
    @Singleton
    fun provideEnvironment(): BittrEnvironment =
        BittrEnvironment.fromBuildConfig(BuildConfig.BITTR_ENVIRONMENT)

    @Provides
    @Singleton
    fun provideDeviceTokenSource(): DeviceTokenSource = FirebaseDeviceTokenSource()

    /**
     * `api-contract` §2.3 rule 2's ceiling. A singleton because "session" means process
     * lifetime, and two instances would each grant their own three attempts.
     */
    @Provides
    @Singleton
    fun provideRetryBudget(): DeviceTokenRetryBudget = DeviceTokenRetryBudget()

    /**
     * **BIT-6's seam.** Signing a bittr request needs the lightning node key, and there is no
     * lightning node yet — `:core:wallet`'s interface covers the seed, the PIN and BIP-39, and
     * `WalletService` has no `nodeId()` or `signMessage()` because ldk-node has not landed.
     *
     * So this reports the node as not ready, which is a state the contract and both clients
     * already model: iOS guards on exactly this at every signing call site
     * (`BuyViewController.swift:330`, `SwapManager.swift:86`) because the node syncs
     * asynchronously after launch. `DeviceTokenLifecycle` returns `WALLET_NOT_READY` and spends
     * no retry budget.
     *
     * BIT-6 replaces the body of this function, exactly as [WalletModule] documents for
     * `provideWalletService`. Nothing else in the push path changes when it does.
     */
    @Provides
    @Singleton
    fun provideRequestSigner(): BittrRequestSigner = object : BittrRequestSigner {
        override suspend fun pubkey(): String? = null
        override suspend fun sign(message: String): String? = null
    }

    /**
     * The push object graph, assembled.
     *
     * **The deposit-code supplier is the signup port's seam.** `PATCH /customer/device-token`
     * is keyed on the customer's deposit code (§2.3), and this app has no customer record yet —
     * `POST /customer` is built (`CustomerRegistration`) but the screen that calls it is not
     * ported. Until it is, the supplier returns null and the lifecycle reports
     * `NOT_REGISTERED`, which is also the correct behaviour *after* the port for every launch
     * before signup completes. It is a lambda rather than a value precisely because this object
     * is built at process start, when there is usually no deposit code, and `onNewToken` can
     * arrive on either side of the moment there is one.
     */
    @Provides
    @Singleton
    fun provideDeviceTokenLifecycle(
        environment: BittrEnvironment,
        httpClient: HttpClient,
        signer: BittrRequestSigner,
        tokenSource: DeviceTokenSource,
        tokenCache: DeviceTokenCache,
        webhookCache: BoltzWebhookCache,
        budget: DeviceTokenRetryBudget,
    ): DeviceTokenLifecycle = DeviceTokenLifecycle(
        environment = environment,
        httpClient = httpClient,
        signer = signer,
        tokenSource = tokenSource,
        tokenCache = tokenCache,
        webhookCache = webhookCache,
        budget = budget,
        clock = UnixClock.System,
        depositCode = { null },
    )

    @Provides
    @Singleton
    fun provideDeviceTokenCache(@ApplicationContext context: Context): DeviceTokenCache =
        PrefsDeviceTokenCache(context)

    @Provides
    @Singleton
    fun provideBoltzWebhookCache(@ApplicationContext context: Context): BoltzWebhookCache =
        PrefsBoltzWebhookCache(context)
}

/** [BittrPushDelivery] under the interface `:core:push-fcm` asks the `Application` for. */
@Module
@InstallIn(SingletonComponent::class)
abstract class PushDeliveryModule {

    @Binds
    abstract fun bindPushDelivery(delivery: BittrPushDelivery): PushDelivery
}
