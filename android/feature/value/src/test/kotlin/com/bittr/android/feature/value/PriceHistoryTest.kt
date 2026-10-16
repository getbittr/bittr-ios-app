package com.bittr.android.feature.value

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The one price history behind Home's value card and the Value screen.
 *
 * Robolectric because `org.json` has no implementation on a plain JVM.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PriceHistoryTest {

    /** Every request and current-price read, in order. */
    private val calls = mutableListOf<String>()
    private var now = 1_000_000L
    private var historyCode = 200

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest): HttpResponse {
            calls += request.url.substringAfter("/price/btc")
            return HttpResponse(historyCode, historical(request.url.substringAfterLast('/')))
        }
    }

    private val history = PriceHistory(
        environment = BittrEnvironment.entries.first(),
        http = http,
        currentPrice = { currency ->
            calls += "current ${currency.name}"
            if (currency == PriceCurrency.CHF) 80_000.0 else 90_000.0
        },
        nowMillis = { now },
        parsing = Dispatchers.Unconfined,
    )

    /**
     * Three days of the week's bucket, priced per currency so a mix-up shows. The parser drops
     * the last one, the API's own copy of the latest price (see `parsePriceSeries`).
     */
    private fun historical(currency: String): String {
        val base = if (currency == "chf") 70_000 else 85_000
        val today = Instant.now()
        val points = (3 downTo 1).joinToString(",") { daysAgo ->
            """{"time_iso8601":"${today.minus(daysAgo.toLong(), ChronoUnit.DAYS)}","price":"${base + daysAgo}"}"""
        }
        val buckets = MutableList(9) { """{"interval":"x","data":[]}""" }
        buckets[GraphSpan.WEEK.apiIndex] = """{"interval":"x","data":[$points]}"""
        return buckets.joinToString(",", prefix = "[", postfix = "]")
    }

    @Test
    fun `the week is loaded in the chosen currency and ends on the current price once`() = runTest {
        assertEquals(listOf(70_003.0, 70_002.0, 80_000.0), history.week(PriceCurrency.CHF))
        assertEquals(listOf(85_003.0, 85_002.0, 90_000.0), history.week(PriceCurrency.EUR))
    }

    /** One endpoint at a time: the current price first, then the history. */
    @Test
    fun `the current price is asked for before the history`() = runTest {
        history.week(PriceCurrency.EUR)

        assertEquals(listOf("current EUR", "/historical/eur"), calls)
    }

    /** The Value screen reuses what Home's card loaded, as iOS's 15-minute cache does. */
    @Test
    fun `the history is fetched once for the card and the screen`() = runTest {
        history.week(PriceCurrency.EUR)
        history.load(PriceCurrency.EUR, LocalDate.now())

        assertEquals(1, calls.count { it == "/historical/eur" })

        now += PriceHistory.FRESH_MILLIS
        history.week(PriceCurrency.EUR)
        assertEquals("fetched again once 15 minutes old", 2, calls.count { it == "/historical/eur" })
    }

    /** A Value screen load brings Home's card up to date. */
    @Test
    fun `every load updates the weeks Home reads`() = runTest {
        assertTrue(history.weeks.value.isEmpty())

        history.load(PriceCurrency.CHF, LocalDate.now())

        assertEquals(listOf(70_003.0, 70_002.0, 80_000.0), history.weeks.value[PriceCurrency.CHF])
    }

    @Test
    fun `a failed fetch is not kept`() = runTest {
        historyCode = 429
        assertThrows(IllegalStateException::class.java) { kotlinx.coroutines.runBlocking { history.week(PriceCurrency.EUR) } }

        historyCode = 200
        history.week(PriceCurrency.EUR)
        assertEquals(2, calls.count { it == "/historical/eur" })
    }
}
