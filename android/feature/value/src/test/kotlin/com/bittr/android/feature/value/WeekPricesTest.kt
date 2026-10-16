package com.bittr.android.feature.value

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Home's value card line: in the chosen currency, and ending on the current price once.
 *
 * Robolectric because `org.json` has no implementation on a plain JVM.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class WeekPricesTest {

    private val requested = mutableListOf<String>()

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest): HttpResponse {
            requested += request.url
            return if (request.url.contains("/historical/")) {
                HttpResponse(200, historical(request.url.substringAfterLast('/')))
            } else {
                HttpResponse(200, """{"btc_eur":"90000","btc_chf":"80000"}""")
            }
        }
    }

    /**
     * Three days of the week's bucket, priced per currency so a mix-up shows. The parser drops
     * the last one, the API's own copy of the latest price (see `parsePriceSeries`).
     */
    private fun historical(currency: String): String {
        val base = if (currency == "chf") 70_000 else 85_000
        val now = Instant.now()
        val points = (3 downTo 1).joinToString(",") { daysAgo ->
            """{"time_iso8601":"${now.minus(daysAgo.toLong(), ChronoUnit.DAYS)}","price":"${base + daysAgo}"}"""
        }
        val buckets = MutableList(9) { """{"interval":"x","data":[]}""" }
        buckets[GraphSpan.WEEK.apiIndex] = """{"interval":"x","data":[$points]}"""
        return buckets.joinToString(",", prefix = "[", postfix = "]")
    }

    @Test
    fun `the line is loaded in the chosen currency`() = runTest {
        val week = loadWeekPrices(BittrEnvironment.entries.first(), http, PriceCurrency.CHF)

        assertTrue(requested.toString(), requested.any { it.endsWith("/price/btc/historical/chf") })
        assertEquals(listOf(70_003.0, 70_002.0, 80_000.0), week)
    }

    /** The series already ends on the current price; a second copy drew a flat stub. */
    @Test
    fun `the line ends on the current price once`() = runTest {
        val week = loadWeekPrices(BittrEnvironment.entries.first(), http, PriceCurrency.EUR)

        assertEquals(listOf(85_003.0, 85_002.0, 90_000.0), week)
    }
}
