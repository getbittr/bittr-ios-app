package com.bittr.android.swap

import android.util.Log
import com.bittr.android.core.swaps.DrainPreview
import com.bittr.android.core.swaps.SwapChannel
import com.bittr.android.core.swaps.SwapKey
import com.bittr.android.core.swaps.SwapPayment
import com.bittr.android.core.swaps.SwapPaymentState
import com.bittr.android.core.swaps.SwapWallet
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.ldk.bip.Bip84Account
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.PaymentStatusView
import com.bittr.android.core.wallet.ldk.lightning.activeChannel
import com.bittr.android.core.wallet.ldk.onchain.OnchainDrainClamp
import com.bittr.android.di.WalletComposition
import com.bittr.android.send.MempoolFeeEstimates
import kotlin.math.roundToLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * [SwapWallet] over the wallet `di/WalletModule` composed — the same ports Send uses, plus the
 * swap key, which is derived from the seed at iOS's path (`m/503'/0'/0'/0/<index>`).
 *
 * @param mnemonic reads the seed per use, never held.
 */
class AppSwapWallet(
    private val composition: WalletComposition,
    private val fees: MempoolFeeEstimates,
    private val descriptions: TransactionDescriptionStore,
    private val mnemonic: () -> String?,
) : SwapWallet {

    @Volatile private var lastRate: Long? = null

    private val lightning get() = composition.lightning
    private val overview get() = composition.overview.overview.value

    override fun onchainReady(): Boolean = composition.onchainSend?.isReady == true

    override suspend fun awaitOnchainReady(): Boolean = withTimeoutOrNull(SCAN_WAIT_MS) {
        while (!onchainReady()) delay(POLL_MS)
        true
    } ?: false

    override fun activeChannel(): SwapChannel? = runCatching { lightning.listChannels().activeChannel() }.getOrNull()?.let {
        SwapChannel(
            channelValueSats = it.channelValueSats.toLong(),
            outboundSats = (it.outboundCapacityMsat / 1000uL).toLong(),
            reserveSats = it.unspendablePunishmentReserveSats?.toLong(),
            counterpartyReserveSats = it.counterpartyUnspendablePunishmentReserveSats.toLong(),
            inboundHtlcMaximumMsat = it.inboundHtlcMaximumMsat?.toLong(),
        )
    }

    override fun onchainBalanceSats(): Long = overview.satoshisOnchain

    override fun onchainSpendableSats(): Long = overview.satoshisOnchainSpendable

    override suspend fun fastestFeeRate(): Double? = fees.fetch()?.fastest?.also { lastRate = maxOf(1L, it.roundToLong()) }

    override fun lastKnownFeeRate(): Long? = lastRate

    override suspend fun drainPreview(address: String?, satPerVb: Long): DrainPreview? = io {
        val preview = runCatching { composition.onchainSend?.drainPreview(address, satPerVb.toULong()) }.getOrNull() ?: return@io null
        val loaded = overview.takeIf { it.hasSynced }?.satoshisOnchainSpendable
        val clamped = OnchainDrainClamp.clampToLdkSpendable(preview, loaded)
        DrainPreview(clamped.sendableSats.toLong(), clamped.feeSats.toLong())
    }

    override suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long): Result<Long> = io {
        runCatching {
            val support = composition.onchainSend ?: error("No on-chain wallet in this build.")
            support.transactionVsize(address, amountSats, satPerVb.toULong())?.toLong() ?: error("The wallet isn't open yet.")
        }
    }

    /** BDK's `CreateTxException.InsufficientFunds` and `CoinSelection` — iOS's friendly-message branch. */
    override fun isInsufficientFunds(failure: Throwable): Boolean {
        val described = "${failure::class.qualifiedName} ${failure.message}"
        return "InsufficientFunds" in described || "CoinSelection" in described
    }

    override suspend fun createInvoice(amountMsat: Long, description: String, expirySecs: Int): String? = io {
        runCatching { lightning.receiveBolt11(amountMsat.toULong(), Bolt11DescriptionView.Direct(description), expirySecs.toUInt()) }
            .onFailure { Log.w(TAG, "Swap invoice failed", it) }
            .getOrNull()
    }

    override suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long): Result<String> = io {
        runCatching { composition.onchain.sendToAddress(address, amountSats, satPerVb.toULong()) }
    }

    override suspend fun sendAllOnchain(address: String, satPerVb: Long): Result<String> = io {
        runCatching { composition.onchain.sendAllToAddress(address, satPerVb.toULong()) }
    }

    override suspend fun startPayment(invoice: String): Result<String> = io {
        runCatching { lightning.sendBolt11(invoice, null) }
    }

    override suspend fun payment(paymentId: String): SwapPayment? = io {
        lightning.payment(paymentId)?.let {
            val state = when (it.status) {
                PaymentStatusView.Succeeded -> SwapPaymentState.Succeeded
                PaymentStatusView.Failed -> SwapPaymentState.Failed
                else -> SwapPaymentState.Pending
            }
            SwapPayment(state, it.amountMsat?.toLong())
        }
    }

    override suspend fun nextUnusedAddress(): String? = io {
        composition.addressPool?.nextAddress()
            ?: composition.addressPool?.currentAddress()
            ?: runCatching { composition.onchain.newReceiveAddress().address }.getOrNull()
    }

    override suspend fun swapKey(index: Int): SwapKey = io {
        val words = mnemonic() ?: error("No seed on this device")
        val key = Bip84Account.swapRefundKey(words, index)
        SwapKey(key.privateKey.value.toHex(), key.publicKey.value.toHex())
    }

    /**
     * `CacheManager.storeInvoiceDescription`: the swap's `dateID` on each leg (payment hash or txid),
     * which is how the history matches the two legs into one swap row.
     */
    override fun recordDescription(key: String, description: String) {
        descriptions.store(key, description)
    }

    override fun recordPaymentFees(key: String, feesSats: Long) = Unit

    override suspend fun sync() = io {
        runCatching { lightning.syncWallets() }
        composition.refresh()
    }

    override suspend fun transactionIdForPayment(paymentHash: String): String? = io {
        runCatching { lightning.syncWallets() }
        composition.refresh()
        overview.transactions.firstOrNull { it.id.equals(paymentHash, ignoreCase = true) }?.id
    }

    private suspend fun <T> io(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }

    private companion object {
        const val TAG = "AppSwapWallet"
        const val SCAN_WAIT_MS = 180_000L
        const val POLL_MS = 500L
    }
}
