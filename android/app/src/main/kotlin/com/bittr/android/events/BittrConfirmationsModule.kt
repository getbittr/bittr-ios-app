package com.bittr.android.events

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.BittrTransactionInfo
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.TransactionInfo
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.wallet.BittrPurchase
import com.bittr.android.core.wallet.BittrPurchaseSource
import com.bittr.android.core.wallet.InternetConnection
import com.bittr.android.core.wallet.TransactionDescriptionStore
import com.bittr.android.di.WalletComposition
import com.bittr.android.receive.BitcoinPriceSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.withContext

@Module
@InstallIn(SingletonComponent::class)
object BittrConfirmationsModule {

    /** bittr's purchase records for the transaction screen, over the customer store. */
    @Provides
    @Singleton
    fun provideBittrPurchaseSource(
        store: BittrCustomerStore,
        composition: WalletComposition,
        prices: BitcoinPriceSource,
    ): BittrPurchaseSource = object : BittrPurchaseSource {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        override val purchases: StateFlow<Map<String, BittrPurchase>> = store.purchases
            .map { rows -> rows.mapValues { (_, row) -> row.toPurchase() } }
            .stateIn(scope, SharingStarted.Eagerly, store.purchases.value.mapValues { (_, row) -> row.toPurchase() })

        override fun fundingTxId(): String? = composition.channelFundingTxId()

        override suspend fun pricePerBitcoin(currencyCode: String): Double? =
            Currency.entries.firstOrNull { it.code == currencyCode }?.let { prices.price(it) }
    }

    @Provides
    @Singleton
    fun provideBittrLookup(
        store: BittrCustomerStore,
        http: HttpClient,
        environment: BittrEnvironment,
        signer: BittrRequestSigner,
        descriptions: TransactionDescriptionStore,
    ): BittrLookup = AppBittrLookup(store, http, environment, signer, descriptions)

    /** `Reachability.isConnectedToNetwork()`: a network that reaches the internet. */
    @Provides
    @Singleton
    fun provideInternetConnection(@ApplicationContext context: Context): InternetConnection = InternetConnection {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return@InternetConnection true
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return@InternetConnection false
        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}

/** [BittrLookup] over `GET /transaction_info` — `BittrService.fetchBittrTransactions`. */
internal class AppBittrLookup(
    private val store: BittrCustomerStore,
    private val http: HttpClient,
    private val environment: BittrEnvironment,
    private val signer: BittrRequestSigner,
    private val descriptions: TransactionDescriptionStore,
) : BittrLookup {

    override fun alreadySent(txId: String): Boolean = txId in store.sentToBittr()

    override fun isPurchase(txId: String): Boolean = store.purchases.value.containsKey(txId)

    override suspend fun check(txId: String): Boolean = withContext(Dispatchers.IO) {
        val txIds = listOf(txId)
        val depositCodes = store.depositCodes()
        val pubkey = signer.pubkey() ?: return@withContext false
        val signature = signer.sign(TransactionInfo.message(txIds, depositCodes)) ?: return@withContext false
        val response = runCatching { http.execute(TransactionInfo.request(environment, txIds, depositCodes, pubkey, signature)) }
            .getOrNull() ?: return@withContext false
        val rows = TransactionInfo.parse(response) ?: return@withContext false
        // `updateSentToBittr` once the call succeeded, whatever it returned.
        store.addSentToBittr(txIds)
        if (rows.isNotEmpty()) store.addPurchases(rows)
        rows.size == 1 && rows.first().txId == txId
    }

    override fun storeDescription(key: String, description: String) = descriptions.store(key, description)
}

/** A `/transaction_info` row as the transaction screen reads it. */
internal fun BittrTransactionInfo.toPurchase(): BittrPurchase = BittrPurchase(
    txId = txId,
    currency = currency,
    bitcoinAmountSats = bitcoinAmount?.let(::bitcoinToSats),
    fiatNetAmount = fiatAmountNet,
    fiatGrossAmount = fiatAmountGross,
    transferFeeSats = transferFee?.let(::bitcoinToSats),
    bittrFee = bittrFee,
    surcharge = surcharge,
    historicalExchangeRate = historicalExchangeRate,
    timestampSecs = datetime?.let(::utcSeconds),
)

/** `toNumber().inSatoshis()`. */
private fun bitcoinToSats(bitcoin: Double): Long =
    BigDecimal(bitcoin.toString()).movePointRight(8).setScale(0, RoundingMode.HALF_UP).toLong()

/** bittr's `datetime`, `yyyy-MM-dd'T'HH:mm:ss` in UTC, as iOS parses it. */
private fun utcSeconds(datetime: String): Long? = runCatching {
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        .apply { timeZone = TimeZone.getTimeZone("UTC") }
        .parse(datetime)
        ?.time
        ?.div(1000)
}.getOrNull()
