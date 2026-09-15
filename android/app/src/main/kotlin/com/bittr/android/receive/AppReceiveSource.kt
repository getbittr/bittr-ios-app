package com.bittr.android.receive

import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.core.wallet.ldk.adapter.Bolt11Decoder
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.activeChannel
import com.bittr.android.core.wallet.ldk.onchain.OnchainAddressPool
import com.bittr.android.feature.receive.FiatCurrency
import com.bittr.android.feature.receive.ReceiveSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

/**
 * [ReceiveSource] over the wallet [com.bittr.android.di.WalletModule] composed.
 *
 * @param addressPool null in a build with no node, which has no on-chain wallet to hand
 *   addresses from. Receive then shows "Unavailable" rather than inventing an address —
 *   an address nobody watches is money that arrives and never shows.
 * @param descriptions where an invoice's description is kept for the transaction screen —
 *   `ReceiveLightning.swift`'s `storeInvoiceDescription`. ldk-node reports no description with a
 *   received payment, so without this the description is lost.
 */
class AppReceiveSource(
    private val lightning: LightningNodePort,
    private val addressPool: OnchainAddressPool?,
    private val preferences: AppPreferences,
    private val prices: BitcoinPriceSource,
    private val descriptions: TransactionDescriptionStore? = null,
) : ReceiveSource {

    override fun lightningAvailable(): Boolean = lightning.listChannels().activeChannel() != null

    /**
     * The bittr account's lightning address. The bittr account (signup, deposit codes and
     * the lightning address that comes with them) is not ported yet, so there is none.
     */
    override fun lightningAddress(): String? = null

    override val addressesVerified: StateFlow<Boolean> = addressPool?.verified ?: MutableStateFlow(true)

    override fun currentOnchainAddress(): String? = addressPool?.currentAddress()

    override fun nextOnchainAddress(): String? = addressPool?.nextAddress()

    override suspend fun zeroAmountInvoice(description: String): String? = createInvoice(description) {
        lightning.receiveBolt11VariableAmount(Bolt11DescriptionView.Direct(description), INVOICE_EXPIRY_SECS)
    }

    override suspend fun invoice(amountSats: Long, description: String): String? = createInvoice(description) {
        lightning.receiveBolt11(
            amountMsat = amountSats.toULong() * MSAT_PER_SAT,
            description = Bolt11DescriptionView.Direct(description),
            expirySecs = INVOICE_EXPIRY_SECS,
        )
    }

    override fun fiatCurrency(): FiatCurrency =
        preferences.currency.value.let { FiatCurrency(code = it.code, symbol = it.symbol) }

    override suspend fun fiatPricePerBitcoin(): Double? = prices.price(preferences.currency.value)

    /** Null on any failure — no node, no channel liquidity — which Receive shows as "Unavailable". */
    private suspend fun createInvoice(description: String, create: () -> String): String? =
        withContext(Dispatchers.IO) {
            runCatching(create).getOrNull()?.also { invoice -> remember(invoice, description) }
        }

    /** Keyed by payment hash, which the paid row carries whether or not its preimage is known. */
    private fun remember(invoice: String, description: String) {
        if (description.isBlank()) return
        val hash = Bolt11Decoder.decode(invoice)?.paymentHashHex ?: return
        descriptions?.store(hash, description)
    }

    private companion object {
        /** `expirySecs: 3600` — `ReceiveViewController.swift:227`. */
        const val INVOICE_EXPIRY_SECS: UInt = 3600u
        const val MSAT_PER_SAT: ULong = 1000uL
    }
}
