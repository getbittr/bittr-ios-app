package com.bittr.android.device

import android.util.Log
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.PendingPayouts
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.feature.settings.DeviceNode
import com.bittr.android.feature.settings.PendingPayoutCheck
import com.bittr.android.push.PushCoordinator
import com.bittr.android.push.PushNode
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Module
@InstallIn(SingletonComponent::class)
object DeviceNodeModule {

    @Provides
    @Singleton
    fun provideDeviceNode(
        lightning: LightningNodePort,
        push: PushNode,
        signer: BittrRequestSigner,
        http: HttpClient,
        environment: BittrEnvironment,
        payouts: PushCoordinator,
        customers: BittrCustomerStore,
    ): DeviceNode = AppDeviceNode(lightning, push, signer, http, environment, payouts, customers)
}

/**
 * Device details over the one wallet composition: the node's key, the bittr peer (the same
 * check and reconnect the payout push uses), and the pending-payout lookup, whose payout is
 * handed to [PushCoordinator] so its alerts are the push's.
 */
internal class AppDeviceNode(
    private val lightning: LightningNodePort,
    private val push: PushNode,
    private val signer: BittrRequestSigner,
    private val http: HttpClient,
    private val environment: BittrEnvironment,
    private val payouts: PushCoordinator,
    private val customers: BittrCustomerStore,
    private val clockSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) : DeviceNode {

    override fun publicKey(): String? = runCatching { lightning.nodeId() }.getOrNull()

    override suspend fun isConnectedToBittr(): Boolean = withContext(Dispatchers.IO) { push.isConnectedToBittr() }

    override suspend fun reconnectToBittr() = withContext(Dispatchers.IO) { push.reconnectToBittr() }

    override suspend fun pendingPayout(): PendingPayoutCheck = withContext(Dispatchers.IO) {
        val pubkey = signer.pubkey() ?: return@withContext PendingPayoutCheck.NoNode
        val timestamp = clockSeconds()
        val signature = signer.sign(PendingPayouts.message(pubkey, timestamp))
            ?: return@withContext PendingPayoutCheck.NoNode
        val response = runCatching { http.execute(PendingPayouts.request(environment, timestamp, signature, pubkey)) }
            .getOrNull() ?: return@withContext PendingPayoutCheck.NoneAvailable
        Log.i(TAG, "GET notifications: ${PendingPayouts.describe(response)}")
        val skip = customers.processedPayouts()
        when (val outcome = PendingPayouts.parse(response, skip)) {
            PendingPayouts.Outcome.None -> PendingPayoutCheck.NoneAvailable
            is PendingPayouts.Outcome.Available -> PendingPayoutCheck.Available(outcome.notificationId, outcome.amountMsats)
        }
    }

    override fun handlePendingPayout(payout: PendingPayoutCheck.Available) {
        payouts.handlePendingPayout(payout.notificationId, payout.amountMsats)
    }

    private companion object {
        const val TAG = "DeviceNode"
    }
}
