package com.bittr.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HttpRequestTest {

    @Test
    fun `PATCH is available as a verb`() {
        // Not a tautology. This is the single requirement that decided the HTTP
        // client: api-contract §2.3 makes the device-token endpoint a PATCH, and
        // java.net.HttpURLConnection throws ProtocolException on that verb. If this
        // enum ever loses the case, the endpoint becomes unreachable.
        assertTrue(HttpMethod.entries.contains(HttpMethod.PATCH))
    }

    @Test
    fun `a relative url is rejected at construction`() {
        val thrown = runCatching {
            HttpRequest(HttpMethod.GET, "/customer")
        }.exceptionOrNull()

        assertTrue(
            "A path with no host must fail where it is built, not at the socket. " +
                "Got $thrown",
            thrown is IllegalArgumentException,
        )
    }

    @Test
    fun `a GET with a body is rejected`() {
        val thrown = runCatching {
            HttpRequest(HttpMethod.GET, "https://example.test/x", jsonBody = "{}")
        }.exceptionOrNull()

        assertTrue(
            "OkHttp will happily send a GET with a body and some servers silently " +
                "drop it, which is the kind of failure that gets debugged server-side " +
                "for a day. Got $thrown",
            thrown is IllegalArgumentException,
        )
    }

    @Test
    fun `a POST and a PATCH may carry a body, and any verb may omit one`() {
        assertEquals(
            "{}",
            HttpRequest(HttpMethod.POST, "https://example.test/x", "{}").jsonBody,
        )
        assertEquals(
            "{}",
            HttpRequest(HttpMethod.PATCH, "https://example.test/x", "{}").jsonBody,
        )
        // api-contract §2.4's GET /boltz/webhook-token is the bodyless case.
        assertEquals(null, HttpRequest(HttpMethod.GET, "https://example.test/x").jsonBody)
    }

    @Test
    fun `only 2xx is successful`() {
        // The boundaries specifically. §2.3 rules 2-4 ask the client to tell a
        // rate-limit rejection from a bad signature from a clock-skew rejection, so
        // every non-2xx has to survive as its own number rather than as a boolean.
        assertTrue(HttpResponse(200, "").isSuccessful)
        assertTrue(HttpResponse(299, "").isSuccessful)
        assertFalse(HttpResponse(199, "").isSuccessful)
        assertFalse(HttpResponse(300, "").isSuccessful)
        assertFalse(HttpResponse(401, "").isSuccessful)
        assertFalse(HttpResponse(429, "").isSuccessful)
        assertFalse(HttpResponse(503, "").isSuccessful)
    }

    @Test
    fun `a failed response keeps its code and body`() {
        // §4.1 put push_channel in the body and kept the status 2xx; §2.3 rule 4
        // then asks for a distinguishing slug on the failures. Both readings need the
        // body of a non-2xx to survive, so it is asserted rather than assumed.
        val response = HttpResponse(409, """{"error":"no_such_customer"}""")
        assertFalse(response.isSuccessful)
        assertTrue(response.body.contains("no_such_customer"))
    }
}
