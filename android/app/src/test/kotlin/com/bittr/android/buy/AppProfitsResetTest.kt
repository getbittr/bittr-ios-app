package com.bittr.android.buy

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.InMemoryBittrCustomerStore
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletOverviewSource
import com.bittr.android.receive.BitcoinPriceSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AppProfitsResetTest {

    private val scope = CoroutineScope(Dispatchers.Unconfined)
    private val overview = MutableStateFlow(WalletOverview(hasNode = true, hasSynced = true, satoshisOnchain = 1_000))

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest) = HttpResponse(200, """{"btc_eur":"60000","btc_chf":"58000"}""")
    }

    private val profits = AppProfits(
        store = InMemoryBittrCustomerStore(),
        overview = object : WalletOverviewSource {
            override val overview: StateFlow<WalletOverview> = this@AppProfitsResetTest.overview
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

    @After
    fun tearDown() = scope.cancel()

    @Test
    fun `after the wallet is removed the profit summary is null until the next wallet syncs`() {
        profits.start()
        assertNotNull(profits.summary.value)

        // Removal: the overview is emptied and the summary reset.
        overview.value = WalletOverview(hasNode = true)
        profits.reset()
        assertNull(profits.summary.value)
    }
}
