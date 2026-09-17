package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The profit figures Home's pill and the Profits screen show — `calculatedProfit`,
 * `calculatedInvestments` and `calculatedCurrentValue`, kept so the pill is there on launch.
 */
data class CachedProfit(
    val totalProfit: Long,
    val totalInvestment: Long,
    val currentValue: Long,
    val currencySymbol: String,
)

/**
 * What Home last showed — iOS's `WalletCache` (`Cache/WalletCache.swift`): the balance, the history
 * rows, the chain height the confirmations are counted from, and the conversion rates.
 *
 * @property hasReading a wallet reading has been saved. A cache holding only a price or a profit has
 *   nothing to show on Home, as iOS shows nothing when `cachedSatsBalance` is nil.
 * @property prices one bitcoin per [FiatPrice.symbol] — iOS keeps `eurValue` and `chfValue`.
 */
data class CachedHome(
    val hasReading: Boolean = false,
    val satoshisOnchain: Long = 0L,
    val satoshisLightning: Long = 0L,
    val pendingClosureSatoshis: Long = 0L,
    val transactions: List<WalletActivity> = emptyList(),
    val currentHeight: Int? = null,
    val channelClosureTxIds: Set<String> = emptySet(),
    val prices: Map<String, Double> = emptyMap(),
    val profit: CachedProfit? = null,
) {
    /** `setTotalSats()`, as [WalletOverview.totalSatoshis]. */
    val totalSatoshis: Long get() = satoshisOnchain + satoshisLightning + pendingClosureSatoshis

    fun price(symbol: String?): FiatPrice? = symbol?.let { s -> prices[s]?.let { FiatPrice(it, s) } }

    companion object {
        /** The reading half of a synced [WalletOverview]; prices and profit are kept from [previous]. */
        fun of(overview: WalletOverview, previous: CachedHome?): CachedHome = CachedHome(
            hasReading = true,
            satoshisOnchain = overview.satoshisOnchain,
            satoshisLightning = overview.satoshisLightning,
            pendingClosureSatoshis = overview.pendingClosureSatoshis,
            // `cachedHomeTransactions` drops rows with no timestamp.
            transactions = overview.transactions.filter { it.timestampSecs != 0L },
            currentHeight = overview.currentHeight ?: previous?.currentHeight,
            channelClosureTxIds = overview.channelClosureTxIds,
            prices = previous?.prices.orEmpty(),
            profit = previous?.profit,
        )
    }
}

/**
 * Where [CachedHome] is kept between launches. Home shows it while the wallet syncs; it never makes
 * the wallet count as synced, so Send, Receive and the refresh keep their guards until a live reading.
 */
interface HomeCache {

    /** The cache as last written, or null when there is none. */
    val cached: StateFlow<CachedHome?>

    /** A synced reading — `setTotalSats()` and `cachedHomeTransactions`. */
    fun saveOverview(overview: WalletOverview)

    /** A conversion rate that was just fetched — `cachedEurValue` / `cachedChfValue`. */
    fun savePrice(price: FiatPrice)

    fun saveProfit(profit: CachedProfit)

    /** The wallet is gone — `CacheManager.deleteClientInfo()` removes `walletcache`. */
    fun clear()

    /** No cache: a build or test that starts Home empty. */
    object None : HomeCache {
        override val cached: StateFlow<CachedHome?> = MutableStateFlow(null)
        override fun saveOverview(overview: WalletOverview) = Unit
        override fun savePrice(price: FiatPrice) = Unit
        override fun saveProfit(profit: CachedProfit) = Unit
        override fun clear() = Unit
    }
}
