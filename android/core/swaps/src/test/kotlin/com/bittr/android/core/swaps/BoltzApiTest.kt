package com.bittr.android.core.swaps

import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.HttpTransportException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class BoltzApiTest {

    private class FakeHttp(private val answer: (HttpRequest) -> HttpResponse) : HttpClient {
        val requests = mutableListOf<HttpRequest>()
        override suspend fun execute(request: HttpRequest): HttpResponse {
            requests += request
            return answer(request)
        }
    }

    private fun api(answer: (HttpRequest) -> HttpResponse) = FakeHttp(answer).let { it to BoltzApi(it, BoltzEndpoints.DEVELOPMENT, pause = {}) }

    @Test
    fun `fee quotes read the submarine and the reverse shapes`() = runTest {
        val (_, submarine) = api { HttpResponse(200, """{"BTC":{"BTC":{"fees":{"percentage":0.1,"minerFees":226}}}}""") }
        assertEquals(BoltzFeeQuote(0.1, 226), submarine.feeQuote(reverse = false))
        val (http, reverse) = api { HttpResponse(200, """{"BTC":{"BTC":{"fees":{"percentage":0.25,"minerFees":{"lockup":300,"claim":200}}}}}""") }
        assertEquals(BoltzFeeQuote(0.25, 300), reverse.feeQuote(reverse = true))
        assertEquals("https://boltz-api.bittr.io/v2/swap/reverse", http.requests.single().url)
        val (_, down) = api { throw HttpTransportException("offline") }
        assertNull(down.feeQuote(reverse = true))
    }

    @Test
    fun `a submarine swap is created with iOS's body and read from iOS's example answer`() = runTest {
        val example = """{"bip21":"bitcoin:bcrt1p…","acceptZeroConf":false,"expectedAmount":50352,"id":"ChTExx2srRLT","address":"bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af","swapTree":{"claimLeaf":{"version":192,"output":"a914ed96"},"refundLeaf":{"version":192,"output":"2004cac3"}},"claimPublicKey":"03611b80","timeoutBlockHeight":479}"""
        val (http, boltz) = api { HttpResponse(201, example) }
        val created = boltz.createSubmarine("lnbcrt1", "02ab", "https://staging.getbittr.com/api/boltz/webhook/x")
        assertEquals(SubmarineCreated("ChTExx2srRLT", "bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af", 50_352, "03611b80", "a914ed96", "2004cac3"), created)

        val body = Json.parseToJsonElement(http.requests.single().jsonBody!!).jsonObject
        assertEquals("lnbcrt1", body["invoice"]!!.jsonPrimitive.content)
        assertEquals("true", body["webhook"]!!.jsonObject["hashSwapId"]!!.jsonPrimitive.content)
        assertEquals(HttpMethod.POST, http.requests.single().method)
    }

    @Test
    fun `a reverse swap asks for the webhook statuses, and Boltz's error is surfaced`() = runTest {
        val (http, boltz) = api { HttpResponse(400, """{"error":"invalid preimage hash"}""") }
        val failure = assertThrows(BoltzApiException::class.java) {
            kotlinx.coroutines.runBlocking { boltz.createReverse("02ab", "00", 50_247, "https://hook") }
        }
        assertEquals("invalid preimage hash", failure.message)
        val statuses = Json.parseToJsonElement(http.requests.single().jsonBody!!).jsonObject["webhook"]!!.jsonObject["status"]!!.jsonArray
        assertEquals(BoltzApi.REVERSE_WEBHOOK_STATUSES, statuses.map { it.jsonPrimitive.content })
    }

    @Test
    fun `a missing field is the generic swap error`() = runTest {
        val (_, boltz) = api { HttpResponse(201, """{"id":"x"}""") }
        val failure = assertThrows(BoltzApiException::class.java) {
            kotlinx.coroutines.runBlocking { boltz.createSubmarine("ln", "02", "https://hook") }
        }
        assertEquals(SwapCopy.SWAP_ERROR_2, failure.message)
    }

    @Test
    fun `broadcast takes any of the three id fields or a bare string`() = runTest {
        assertEquals("aa", api { HttpResponse(201, """{"transactionId":"aa"}""") }.second.broadcast("00"))
        assertEquals("bb", api { HttpResponse(200, """{"id":"bb"}""") }.second.broadcast("00"))
        assertEquals("cc", api { HttpResponse(200, "cc") }.second.broadcast("00"))
        assertThrows(BoltzApiException::class.java) { kotlinx.coroutines.runBlocking { api { HttpResponse(400, "bad-txns") }.second.broadcast("00") } }
    }

    @Test
    fun `status and socket messages carry the lockup hex`() = runTest {
        val (_, boltz) = api { HttpResponse(200, """{"status":"transaction.mempool","transaction":{"id":"2edf","hex":"0100"}}""") }
        assertEquals(SwapStatusUpdate("transaction.mempool", "0100"), boltz.status("id"))
        assertEquals(
            SwapStatusUpdate("invoice.settled", null),
            BoltzApi.parseSocketMessage("""{"event":"update","channel":"swap.update","args":[{"id":"x","status":"invoice.settled"}]}"""),
        )
        assertNull(BoltzApi.parseSocketMessage("""{"event":"subscribe","channel":"swap.update","args":["x"]}"""))
        assertEquals("""{"op":"subscribe","channel":"swap.update","args":["x"]}""", BoltzApi.subscribeMessage("x"))
    }

    @Test
    fun `raw hex is retried while the transaction propagates`() = runTest {
        var calls = 0
        val (_, boltz) = api { calls++; if (calls < 3) HttpResponse(404, "") else HttpResponse(200, "0200\n") }
        assertEquals("0200", boltz.rawTransactionHex("txid"))
        assertEquals(3, calls)
    }
}
