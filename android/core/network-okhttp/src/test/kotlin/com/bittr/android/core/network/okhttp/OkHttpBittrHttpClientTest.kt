package com.bittr.android.core.network.okhttp

import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpTransportException
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What this client puts on the wire, asserted against a real loopback server.
 *
 * A JVM test rather than an instrumented one, which is the point of keeping the
 * binding in a Kotlin/JVM module: the backend (BIT-9) is Ruben's and does not answer
 * yet, so until BIT-142 the only way to know these requests are well-formed is to
 * send them somewhere that records them.
 */
class OkHttpBittrHttpClientTest {

    private fun withServer(block: suspend (MockWebServer) -> Unit) = runTest {
        MockWebServer().use { server ->
            server.start()
            block(server)
        }
    }

    /**
     * The recorded body as text. `RecordedRequest.body` is nullable — a request that
     * sent none records null rather than an empty ByteString — and the two are the
     * same thing to every assertion here.
     */
    private val RecordedRequest.bodyText: String get() = body?.utf8().orEmpty()

    @Test
    fun `a PATCH reaches the wire with its verb and body intact`() = withServer { server ->
        // The test this module exists for. api-contract §2.3 is
        // `PATCH /customer/device-token`, and HttpURLConnection cannot send that
        // verb at all — it throws ProtocolException from setRequestMethod. Anything
        // that quietly rewrote it to POST would present as a 404 or a 405 from a
        // backend nobody can read the logs of.
        server.enqueue(MockResponse.Builder().code(200).body("""{"data":{}}""").build())

        val body = """{"deposit_code":"ABC123","platform":"android"}"""
        val response = OkHttpBittrHttpClient().execute(
            HttpRequest(
                method = HttpMethod.PATCH,
                url = server.url("/api/customer/device-token").toString(),
                jsonBody = body,
            ),
        )

        val recorded = server.takeRequest()
        assertEquals("PATCH", recorded.method)
        assertEquals("/api/customer/device-token", recorded.target)
        assertEquals(body, recorded.bodyText)
        assertEquals(
            "application/json; charset=utf-8",
            recorded.headers["Content-Type"],
        )
        assertEquals(200, response.code)
        assertTrue(response.isSuccessful)
        assertEquals("""{"data":{}}""", response.body)
    }

    @Test
    fun `a POST carries its body and a GET carries none`() = withServer { server ->
        server.enqueue(MockResponse.Builder().code(201).body("{}").build())
        server.enqueue(MockResponse.Builder().code(200).body("{}").build())

        val client = OkHttpBittrHttpClient()
        client.execute(
            HttpRequest(HttpMethod.POST, server.url("/api/customer").toString(), """{"x":1}"""),
        )
        client.execute(HttpRequest(HttpMethod.GET, server.url("/api/boltz/webhook-token").toString()))

        val post = server.takeRequest()
        assertEquals("POST", post.method)
        assertEquals("""{"x":1}""", post.bodyText)

        val get = server.takeRequest()
        assertEquals("GET", get.method)
        assertEquals("", get.bodyText)
    }

    /**
     * The payout calls: a POST with everything in the query and no body. OkHttp rejects a POST
     * built with a null body ("method POST must have a request body"), which surfaced as
     * "Couldn't connect to Bittr to complete payout" on every payout.
     */
    @Test
    fun `a POST or PATCH with no body is sent with an empty one`() = withServer { server ->
        server.enqueue(MockResponse.Builder().code(200).body("""{"success":true}""").build())
        server.enqueue(MockResponse.Builder().code(200).body("{}").build())

        val client = OkHttpBittrHttpClient()
        val payout = client.execute(
            HttpRequest(HttpMethod.POST, server.url("/api/payout/lightning?notification_id=n1&invoice=lnbc1").toString()),
        )
        client.execute(HttpRequest(HttpMethod.PATCH, server.url("/api/customer/payment-mode").toString()))

        assertEquals(200, payout.code)
        val post = server.takeRequest()
        assertEquals("POST", post.method)
        assertEquals("", post.bodyText)
        assertEquals("/api/payout/lightning?notification_id=n1&invoice=lnbc1", post.target)
        assertEquals("PATCH", server.takeRequest().method)
    }

    @Test
    fun `a non-2xx comes back as a response, not as an exception`() = withServer { server ->
        // Load-bearing for api-contract §2.3 rules 2-4: the client's correct
        // behaviour differs between a rate-limit rejection (retry), a bad signature
        // (stop forever) and no_such_customer (retry after signup). Throwing on all
        // three is how a client picks the wrong one.
        server.enqueue(
            MockResponse.Builder().code(429).body("""{"error":"rate_limited"}""").build(),
        )

        val response = OkHttpBittrHttpClient().execute(
            HttpRequest(HttpMethod.PATCH, server.url("/api/customer/device-token").toString(), "{}"),
        )

        assertEquals(429, response.code)
        assertFalse(response.isSuccessful)
        assertTrue(response.body.contains("rate_limited"))
    }

    @Test
    fun `a 2xx with an empty body decodes rather than failing`() = withServer { server ->
        server.enqueue(MockResponse.Builder().code(204).build())

        val response = OkHttpBittrHttpClient().execute(
            HttpRequest(HttpMethod.GET, server.url("/api/ping").toString()),
        )

        assertEquals(204, response.code)
        assertEquals("", response.body)
    }

    @Test
    fun `no response at all is a transport failure, not a status`() = runTest {
        // The `unavailable` shape of api-contract §4.2, and the reason it is a
        // separate type: "we could not reach the backend" says nothing about the
        // device token, and §4.3's invariant turns on not mistaking it for a verdict.
        //
        // The server is started and then closed, so the port is real and definitely
        // has nothing listening — rather than picking a number and hoping.
        val deadUrl = MockWebServer().use { server ->
            server.start()
            server.url("/api/customer").toString()
        }

        val thrown = runCatching {
            OkHttpBittrHttpClient().execute(HttpRequest(HttpMethod.GET, deadUrl))
        }.exceptionOrNull()

        assertTrue(
            "Expected HttpTransportException for an unreachable host, got $thrown",
            thrown is HttpTransportException,
        )
        assertTrue(
            "The message must name the request so a failure is diagnosable. Was: " +
                thrown?.message,
            thrown?.message?.contains("GET") == true,
        )
    }

    @Test
    fun `every request announces that it accepts json`() = withServer { server ->
        server.enqueue(MockResponse.Builder().code(200).body("{}").build())

        OkHttpBittrHttpClient().execute(
            HttpRequest(HttpMethod.GET, server.url("/api/ping").toString()),
        )

        assertEquals("application/json", server.takeRequest().headers["Accept"])
    }
}
