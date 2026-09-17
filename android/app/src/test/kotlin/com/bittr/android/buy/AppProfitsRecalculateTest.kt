package com.bittr.android.buy

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.BittrTransactionInfo
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.InMemoryBittrCustomerStore
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.receive.BitcoinPriceSource
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * buy_more.yaml opens Profits right after a payout and expects the new purchase in the totals. The
 * summary used to wait on two price requests before it recomputed, so it lagged the purchase.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AppProfitsRecalculateTest {

    private val scope = CoroutineScope(Dispatchers.Unconfined)

    private fun activity(id: String, sats: Long) =
        WalletActivity(id = id, receivedSats = sats, sentSats = 0, feeSats = 0, timestampSecs = 0, isLightning = true, confirmationHeight = null)

    private fun purchase(id: String, eur: Double) = BittrTransactionInfo(
        txId = id, transferType = null, historicalExchangeRate = null, datetime = null,
        currency = "EUR", bitcoinAmount = null, fiatAmountNet = eur, fiatAmountGross = eur,
    )

    @After
    fun tearDown() = scope.cancel()

    @Test
    fun `a new purchase is counted at once, while a price request is still out`() {
        val overview = MutableStateFlow(
            WalletOverview(hasNode = true, hasSynced = true, transactions = listOf(activity("a", 100_000))),
        )
        val store = InMemoryBittrCustomerStore().apply { addPurchases(listOf(purchase("a", 50.0))) }
        var priceReads = 0
        val hang = CompletableDeferred<HttpResponse>()
        val http = object : HttpClient {
            override suspend fun execute(request: HttpRequest): HttpResponse {
                // The first two reads (EUR, CHF) answer; every later one never does.
                return if (priceReads++ < 2) HttpResponse(200, """{"btc_eur":"100000","btc_chf":"90000"}""") else hang.await()
            }
        }
        val profits = AppProfits(
            store = store,
            overview = object : WalletOverviewSource {
                override val overview: StateFlow<WalletOverview> = overview
            },
            prices = BitcoinPriceSource(BittrEnvironment.DEVELOPMENT, http),
            preferences = AppPreferences(ApplicationProvider.getApplicationContext()),
            http = http,
            environment = BittrEnvironment.DEVELOPMENT,
            signer = object : BittrRequestSigner {
                override suspend fun pubkey(): String? = null
                override suspend fun sign(message: String): String? = null
            },
            scope = scope,
        )
        profits.start()
        assertEquals(50L, profits.summary.value?.totalInvestment)

        // The payout lands and bittr confirms it; the price refresh it starts hangs.
        overview.value = overview.value.copy(transactions = overview.value.transactions + activity("b", 100_000))
        store.addPurchases(listOf(purchase("b", 60.0)))

        assertEquals(110L, profits.summary.value?.totalInvestment)
        assertEquals(200L, profits.summary.value?.currentValue)
    }
}
