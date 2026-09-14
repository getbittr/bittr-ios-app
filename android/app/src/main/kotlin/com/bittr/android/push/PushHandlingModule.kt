package com.bittr.android.push

import android.util.Log
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.di.LdkEnvironmentConfig
import dagger.BindsOptionalOf
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.util.Optional
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The hooks other ports fill in. Each is optional: bind an implementation with `@Binds`
 * in any Hilt module and the coordinator uses it; leave it unbound and the push is
 * handled the way the missing screen allows (see [PushCoordinator]).
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class PushHooksModule {

    @BindsOptionalOf
    abstract fun depositCodeSource(): DepositCodeSource

    @BindsOptionalOf
    abstract fun swapPushHandler(): SwapPushHandler

    @BindsOptionalOf
    abstract fun lnurlPushHandler(): LnurlPushHandler

    @BindsOptionalOf
    abstract fun payoutSwapLauncher(): PayoutSwapLauncher
}

@Module
@InstallIn(SingletonComponent::class)
object PushHandlingModule {

    @Provides
    @Singleton
    fun providePushNode(lightning: LightningNodePort): PushNode = object : PushNode {

        private val bittrNode = LdkEnvironmentConfig.fromBuildConfig()

        override fun isConnectedToBittr(): Boolean {
            val nodeId = bittrNode?.lightningNodeId ?: return false
            return lightning.listPeers().any { it.nodeId == nodeId && it.isConnected }
        }

        override suspend fun reconnectToBittr() {
            val environment = bittrNode ?: return
            runCatching { lightning.connect(environment.lightningNodeId, environment.lightningNodeAddress, persist = true) }
                .onFailure { Log.w("PushNode", "Reconnecting to the bittr node failed", it) }
        }

        override fun invoice(amountMsat: Long, description: String, expirySecs: Int): String? = runCatching {
            lightning.receiveBolt11(
                amountMsat = amountMsat.toULong(),
                description = Bolt11DescriptionView.Direct(description),
                expirySecs = expirySecs.toUInt(),
            )
        }.getOrNull()
    }

    @Provides
    @Singleton
    fun providePushCoordinator(
        wallet: WalletService,
        overview: WalletOverviewSource,
        signer: BittrRequestSigner,
        node: PushNode,
        http: HttpClient,
        environment: BittrEnvironment,
        depositCodes: Optional<DepositCodeSource>,
        swapHandler: Optional<SwapPushHandler>,
        lnurlHandler: Optional<LnurlPushHandler>,
        payoutSwap: Optional<PayoutSwapLauncher>,
    ): PushCoordinator = PushCoordinator(
        // Main, like every iOS handler (`DispatchQueue.main`): one thread owns the
        // pending push and the dedup record. Node and network work hops to IO.
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        io = Dispatchers.IO,
        walletState = wallet.state,
        overview = overview.overview,
        signer = signer,
        node = node,
        http = http,
        environment = environment,
        depositCodes = depositCodes.orElse(DepositCodeSource { null }),
        swapHandler = swapHandler.orElse(null),
        lnurlHandler = lnurlHandler.orElse(null),
        payoutSwap = payoutSwap.orElse(null),
    )
}
