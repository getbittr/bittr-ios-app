package com.bittr.android.send

import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort
import com.bittr.android.core.wallet.ldk.lightning.PaymentStatusView
import com.bittr.android.core.wallet.ldk.onchain.OnchainDrainClamp
import com.bittr.android.core.wallet.ldk.onchain.OnchainSendSupport
import com.bittr.android.feature.send.DrainQuote
import com.bittr.android.feature.send.FeeEstimates
import com.bittr.android.feature.send.FiatCurrency
import com.bittr.android.feature.send.SendSource
import com.bittr.android.receive.BitcoinPriceSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * [SendSource] over the wallet `di/WalletModule` composed: BDK for the previews, ldk-node
 * for the broadcast and the payment, the overview for balances.
 *
 * @param onchainSend null in a build with no node; Regular then never becomes ready.
 */
class AppSendSource(
    private val lightning: LightningNodePort,
    private val onchain: NodeOnchainPort,
    private val onchainSend: OnchainSendSupport?,
    private val overview: WalletOverviewSource,
    private val refresh: () -> Unit,
    private val fees: MempoolFeeEstimates,
    private val preferences: AppPreferences,
    private val prices: BitcoinPriceSource,
    override val network: BitcoinNetwork,
) : SendSource {

    override val walletUpdates: Flow<Any> = overview.overview

    override fun onchainReady(): Boolean = onchainSend?.isReady == true

    override suspend fun awaitOnchainReady(): Boolean = withTimeoutOrNull(SCAN_WAIT_MS) {
        while (!onchainReady()) delay(POLL_MS)
        true
    } ?: false

    override fun onchainSpendableSats(): Long = overview.overview.value.satoshisOnchainSpendable

    override fun lightningSendableSats(): Long = overview.overview.value.lightningSendableSats

    override suspend fun feeEstimates(): FeeEstimates? = fees.fetch()

    override suspend fun drainQuote(address: String?, satPerVb: Long): DrainQuote? = io {
        val preview = runCatching { onchainSend?.drainPreview(address, satPerVb.toULong()) }.getOrNull() ?: return@io null
        // iOS clamps only once balances have been read; before that there is nothing to clamp to.
        val loaded = overview.overview.value.takeIf { it.hasSynced }?.satoshisOnchainSpendable
        val clamped = OnchainDrainClamp.clampToLdkSpendable(preview, loaded)
        DrainQuote(clamped.sendableSats.toLong(), clamped.feeSats.toLong(), clamped.vsize.toLong())
    }

    override suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long): Result<Long> = io {
        runCatching {
            val support = onchainSend ?: error("No on-chain wallet in this build.")
            support.transactionVsize(address, amountSats, satPerVb.toULong())?.toLong() ?: error("The wallet isn't open yet.")
        }
    }

    override suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long, sendAll: Boolean): Result<String> = io {
        runCatching {
            if (sendAll) {
                onchain.sendAllToAddress(address, satPerVb.toULong())
            } else {
                onchain.sendToAddress(address, amountSats, satPerVb.toULong())
            }
        }
    }

    override suspend fun payInvoice(invoice: String, amountSats: Long?): Result<String> = io {
        runCatching {
            val id = if (amountSats == null) {
                lightning.sendBolt11(invoice, null)
            } else {
                lightning.sendBolt11UsingAmount(invoice, amountSats.toULong() * MSAT_PER_SAT, null)
            }
            // Wait for the payment to settle, so the transaction screen opens on a result.
            val status = withTimeoutOrNull(PAYMENT_WAIT_MS) {
                var current = lightning.payment(id)?.status
                while (current == null || current == PaymentStatusView.Pending) {
                    delay(POLL_MS)
                    current = lightning.payment(id)?.status
                }
                current
            }
            check(status != PaymentStatusView.Failed) { "Payment failed" }
            id
        }
    }

    override suspend fun settledTransactionId(id: String): String? = io {
        runCatching { lightning.syncWallets() }
        refresh()
        overview.overview.value.transactions.firstOrNull { it.id == id }?.id
    }

    override fun fiatCurrency(): FiatCurrency =
        preferences.currency.value.let { FiatCurrency(code = it.code, symbol = it.symbol) }

    override suspend fun fiatPricePerBitcoin(): Double? = prices.price(preferences.currency.value)

    private suspend fun <T> io(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }

    private companion object {
        /** iOS's BDK full-scan watchdog is 180 s; waiting longer than that is waiting for nothing. */
        const val SCAN_WAIT_MS = 180_000L
        const val PAYMENT_WAIT_MS = 60_000L
        const val POLL_MS = 500L
        const val MSAT_PER_SAT = 1000uL
    }
}
