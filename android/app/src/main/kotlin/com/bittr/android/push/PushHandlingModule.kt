package com.bittr.android.push

import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.ldk.adapter.Bolt11Decoder
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.ldk.lightning.BittrPeerConnection
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
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
    fun providePushNode(lightning: LightningNodePort, bittrPeer: BittrPeerConnection): PushNode = object : PushNode {

        override suspend fun ensureConnectedToBittr(): Boolean = bittrPeer.ensureConnected()

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
        payoutTracker: BittrPayoutTracker,
        customers: BittrCustomerStore,
        descriptions: TransactionDescriptionStore,
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
        payoutTracker = payoutTracker,
        onPayoutFinished = customers::addProcessedPayout,
        onPayoutInvoice = { invoice, notificationId ->
            Bolt11Decoder.decode(invoice)?.paymentHashHex?.let { descriptions.store(it, notificationId) }
        },
    )
}
