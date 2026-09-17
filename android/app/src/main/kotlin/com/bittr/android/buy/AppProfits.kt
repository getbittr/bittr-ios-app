package com.bittr.android.buy

import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpTransportException
import com.bittr.android.core.network.TransactionInfo
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.HomeCache
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.feature.buy.ProfitCalculator
import com.bittr.android.feature.buy.ProfitSummary
import com.bittr.android.feature.buy.PurchaseForProfit
import com.bittr.android.receive.BitcoinPriceSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Home's profit pill and the Profits screen — `getBittrTransactionDetails()` and
 * `calculateProfit()` from `LoadWalletData.swift`.
 *
 * Each time the wallet overview publishes a new set of transactions, the received ones not yet
 * sent to bittr are sent to `GET /transaction_info`; the purchases it confirms are stored, and
 * the summary is recomputed from them at today's prices.
 *
 * The summary is recomputed from the last prices read, the moment a purchase or the history
 * changes — iOS's `calculateProfit()` uses its cached conversion rates too. Waiting on two price
 * requests first left the Profits screen on the old totals for a while after a payout.
 */
class AppProfits(
    private val store: BittrCustomerStore,
    private val overview: WalletOverviewSource,
    /** `CacheManager.getTxoID()`: the channel-funding transaction bittr opened for the customer. */
    private val fundingTxId: () -> String? = { null },
    private val prices: BitcoinPriceSource,
    private val preferences: AppPreferences,
    private val http: HttpClient,
    private val environment: BittrEnvironment,
    private val signer: BittrRequestSigner,
    private val scope: CoroutineScope,
    /** Where the last summary is kept, so Home's pill is there on the next launch. */
    private val homeCache: HomeCache = HomeCache.None,
) {

    private val _summary = MutableStateFlow<ProfitSummary?>(null)

    /** Null until the wallet has synced and a price has been read. */
    val summary: StateFlow<ProfitSummary?> = _summary.asStateFlow()

    private val lookup = Mutex()

    /** The last prices read, [Prices.NONE] until the first read lands. */
    private val lastPrices = MutableStateFlow(Prices.NONE)

    private data class Prices(val eur: Double?, val chf: Double?) {
        companion object {
            val NONE = Prices(null, null)
        }
    }

    fun start() {
        scope.launch {
            overview.overview
                .filter { it.hasSynced }
                .map { snapshot -> snapshot.transactions.map { it.id } }
                .distinctUntilChanged()
                .collect { lookUpPurchases() }
        }
        // Prices: read once synced, and again when the history changes or the currency does.
        scope.launch {
            combine(overview.overview, preferences.currency) { snapshot, currency ->
                snapshot.takeIf { it.hasSynced }?.let { it.transactions.map { tx -> tx.id } to currency }
            }
                .filter { it != null }
                .distinctUntilChanged()
                .collect { refreshPrices() }
        }
        scope.launch {
            combine(overview.overview, store.purchases, preferences.currency, lastPrices) { snapshot, _, _, _ -> snapshot }
                .filter { it.hasSynced }
                .collect { recalculate() }
        }
    }

    /**
     * The wallet is gone: no summary until the next wallet's first synced reading computes one. The
     * purchases and bittr account it is computed from are cleared with the customer store.
     */
    fun reset() {
        _summary.value = null
    }

    private suspend fun refreshPrices() {
        val eur = prices.price(Currency.EUR)
        val chf = prices.price(Currency.CHF)
        // A failed read keeps the price it replaces.
        lastPrices.value = Prices(eur ?: lastPrices.value.eur, chf ?: lastPrices.value.chf)
    }

    private suspend fun lookUpPurchases() = lookup.withLock {
        val depositCodes = store.depositCodes()
        if (depositCodes.isEmpty()) return@withLock
        val sent = store.sentToBittr()
        val transactions = overview.overview.value.transactions
        val received = transactions
            .filter { it.receivedSats > 0 && it.netSats > 0 && it.id !in sent }
            .map { it.id }
        // `getBittrTransactions`: the funding transaction too, unless it was already sent and is
        // already in the history. A channel bittr funded is a purchase the history does not list
        // as a received transaction of this wallet.
        val funding = fundingTxId()?.takeUnless { id -> id in sent && transactions.any { it.id == id } }
        val txIds = (received + listOfNotNull(funding)).distinct()
        if (txIds.isEmpty()) return@withLock
        val pubkey = signer.pubkey() ?: return@withLock
        val signature = signer.sign(TransactionInfo.message(txIds, depositCodes)) ?: return@withLock
        val response = try {
            http.execute(TransactionInfo.request(environment, txIds, depositCodes, pubkey, signature))
        } catch (e: HttpTransportException) {
            return@withLock
        }
        val rows = TransactionInfo.parse(response) ?: return@withLock
        store.addSentToBittr(txIds)
        if (rows.isNotEmpty()) store.addPurchases(rows)
    }

    private fun recalculate() {
        val purchases = store.purchases.value
        val transactions = overview.overview.value.transactions
        val chosen = preferences.currency.value
        val (eur, chf) = lastPrices.value
        val chosenPrice = (if (chosen == Currency.EUR) eur else chf) ?: return
        val inputs = transactions.mapNotNull { tx ->
            val purchase = purchases[tx.id] ?: return@mapNotNull null
            PurchaseForProfit(
                receivedBtc = tx.receivedSats / 100_000_000.0,
                currency = purchase.currency,
                fiatNetAmount = purchase.fiatAmountNet ?: 0.0,
            )
        } + fundingPurchase(transactions.map { it.id }.toSet(), purchases)
        _summary.value = ProfitCalculator.summarise(inputs, chosen.symbol, chosenPrice, eur, chf)
        _summary.value?.let { summary ->
            homeCache.saveProfit(
                CachedProfit(summary.totalProfit, summary.totalInvestment, summary.currentValue, summary.currencySymbol),
            )
        }
    }

    /**
     * iOS turns the funding transaction's bittr row into a history transaction
     * (`createTransaction(isFundingTransaction: true)`) and counts it like any purchase; here it
     * is counted from the row itself, at the bitcoin amount bittr reports, unless the history
     * already has it.
     */
    private fun fundingPurchase(
        historyIds: Set<String>,
        purchases: Map<String, com.bittr.android.core.network.BittrTransactionInfo>,
    ): List<PurchaseForProfit> {
        val id = fundingTxId() ?: return emptyList()
        if (id in historyIds) return emptyList()
        val purchase = purchases[id] ?: return emptyList()
        val btc = purchase.bitcoinAmount ?: return emptyList()
        return listOf(PurchaseForProfit(receivedBtc = btc, currency = purchase.currency, fiatNetAmount = purchase.fiatAmountNet ?: 0.0))
    }
}
