package com.bittr.android.receive

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.preferences.Currency
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `GET /price/btc` is asked for by Home, the profit summary, Receive, Send, the swap screen and a
 * transaction, each currency separately. Four calls inside 100 ms had staging answering 429, which
 * failed bitcoin_value.yaml.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class BitcoinPriceSourceTest {

    private var calls = 0
    private var now = 1_000_000L

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest): HttpResponse {
            calls++
            return HttpResponse(200, """{"btc_eur":"60000","btc_chf":"58000"}""")
        }
    }

    private val prices = BitcoinPriceSource(BittrEnvironment.DEVELOPMENT, http) { now }

    @Test
    fun `one reading serves every caller and both currencies`() = runTest {
        assertEquals(60000.0, prices.price(Currency.EUR))
        assertEquals(58000.0, prices.price(Currency.CHF))
        assertEquals(60000.0, prices.price(Currency.EUR))
        assertEquals("the price is read once for all of them", 1, calls)
    }

    @Test
    fun `a stale reading is refetched`() = runTest {
        prices.price(Currency.EUR)
        now += 31_000
        prices.price(Currency.EUR)
        assertEquals(2, calls)
    }

    @Test
    fun `a failed reading is not cached`() = runTest {
        val failing = object : HttpClient {
            override suspend fun execute(request: HttpRequest): HttpResponse {
                calls++
                return if (calls == 1) HttpResponse(429, "") else HttpResponse(200, """{"btc_eur":"60000"}""")
            }
        }
        val source = BitcoinPriceSource(BittrEnvironment.DEVELOPMENT, failing) { now }
        assertEquals(null, source.price(Currency.EUR))
        assertEquals(60000.0, source.price(Currency.EUR))
    }

    /** Parsed before it is kept: a reply that isn't the price is not cached for 30 seconds. */
    @Test
    fun `a reply that does not parse is not cached`() = runTest {
        val replies = ArrayDeque(listOf("<html>busy</html>", """{"btc_eur":"60000","btc_chf":"58000"}"""))
        val source = BitcoinPriceSource(BittrEnvironment.DEVELOPMENT, object : HttpClient {
            override suspend fun execute(request: HttpRequest): HttpResponse {
                calls++
                return HttpResponse(200, replies.removeFirst())
            }
        }) { now }

        assertEquals(null, source.price(Currency.EUR))
        assertEquals(60000.0, source.price(Currency.EUR))
        assertEquals(2, calls)
    }

    @Test
    fun `a reply missing a currency is used but not cached`() = runTest {
        val source = BitcoinPriceSource(BittrEnvironment.DEVELOPMENT, object : HttpClient {
            override suspend fun execute(request: HttpRequest): HttpResponse {
                calls++
                return HttpResponse(200, """{"btc_eur":"60000"}""")
            }
        }) { now }

        assertEquals(60000.0, source.price(Currency.EUR))
        assertEquals(null, source.price(Currency.CHF))
        assertEquals(2, calls)
    }

    /** What lets Home pick up a price the Value screen fetched. */
    @Test
    fun `each new reading is announced, a cached one is not`() = runTest {
        var announced = 0
        val listener = backgroundScope.launch(kotlinx.coroutines.test.UnconfinedTestDispatcher(testScheduler)) {
            prices.freshReadings.collect { announced++ }
        }

        prices.price(Currency.EUR)
        prices.price(Currency.CHF)
        now += 31_000
        prices.price(Currency.EUR)

        assertEquals(2, announced)
        listener.cancel()
    }
}
