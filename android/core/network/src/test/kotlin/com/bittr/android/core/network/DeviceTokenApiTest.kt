package com.bittr.android.core.network

import com.bittr.android.core.push.PushChannel
import com.bittr.android.core.push.PushChannelAction
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-41 item 5's wire half — `PATCH /customer/device-token` (`api-contract` §2.3) — and item
 * 6's — `GET /boltz/webhook-token` (§2.4).
 */
class DeviceTokenApiTest {

    private val env = BittrEnvironment.DEVELOPMENT
    private val signed = SignedRequest(pubkey = "02aabb", signature = "sig", timestampSeconds = 1_757_000_000)

    private fun bodyOf(request: HttpRequest): JsonObject =
        Json.parseToJsonElement(requireNotNull(request.jsonBody)) as JsonObject

    /**
     * BIT-41's own deliverable 5 says `POST`; rev 2 of the contract changed it to `PATCH` and rev
     * 4 kept it. It is also the reason OkHttp is on this repo's dependency graph at all, so a
     * silent revert to POST would look like it worked and would take the justification for a
     * dependency with it.
     */
    @Test
    fun `the device token endpoint is a PATCH`() {
        val request = DeviceTokenPatch.request(env, "ABC123", "fcm-token", signed)

        assertEquals(HttpMethod.PATCH, request.method)
        assertEquals("${env.apiBaseUrl}/customer/device-token", request.url)
    }

    @Test
    fun `the body is the signed-request shape payment-mode already uses`() {
        val body = bodyOf(DeviceTokenPatch.request(env, "ABC123", "fcm-token", signed))

        assertEquals(
            setOf("deposit_code", "platform", "device_token", "pubkey", "signature", "timestamp"),
            body.keys,
        )
        assertEquals(JsonPrimitive("ABC123"), body["deposit_code"])
        assertEquals(JsonPrimitive("android"), body["platform"])
        assertEquals(JsonPrimitive("fcm-token"), body["device_token"])
        assertEquals(JsonPrimitive("02aabb"), body["pubkey"])
        assertEquals(JsonPrimitive("sig"), body["signature"])
        // A number, as BuyViewController.swift:361 sends. A quoted timestamp is a different
        // value to anything type-checking it on the way in.
        assertEquals(JsonPrimitive(1_757_000_000L), body["timestamp"])
    }

    /**
     * §2.3's column-width note and §2.4's compare are the same requirement seen from two ends:
     * the token must survive byte-for-byte. A client that trims is the half of that failure
     * nobody looks for, because the symptom shows up as staleness in `SwapManager`.
     */
    @Test
    fun `the token is sent verbatim, including surrounding whitespace and its full length`() {
        val awkward = " " + "e".repeat(180) + ":APA91b\t"
        val body = bodyOf(DeviceTokenPatch.request(env, "ABC123", awkward, signed))

        assertEquals(JsonPrimitive(awkward), body["device_token"])
    }

    @Test
    fun `the signed message is the five-part construction the contract pins`() {
        assertEquals(
            "device_token:02aabb:ABC123:fcm-token:1757000000",
            DeviceTokenPatch.message("02aabb", "ABC123", "fcm-token", 1_757_000_000),
        )
    }

    @Test
    fun `an accepted refresh carries the same push_channel pair as registration`() {
        val accepted = requireNotNull(
            DeviceTokenPatch.parse(HttpResponse(200, """{"data":{"push_channel":"fcm"}}""")).valueOrNull(),
        )
        assertEquals(PushChannelAction.Registered(PushChannel.FCM), accepted.action)
    }

    /**
     * §2.3 says only that the response *carries* the pair, not at what depth. Reading both the
     * wrapped and the unwrapped shape is what stops the alternative from failing silently — an
     * unread `push_channel` parses as an unrecognised channel, which looks like a contract
     * mismatch rather than a parser bug.
     */
    @Test
    fun `the push_channel pair is read whether or not it is wrapped in data`() {
        val wrapped = DeviceTokenPatch.parse(HttpResponse(200, """{"data":{"push_channel":"fcm"}}"""))
        val bare = DeviceTokenPatch.parse(HttpResponse(200, """{"push_channel":"fcm"}"""))

        assertEquals(
            requireNotNull(wrapped.valueOrNull()).pushChannel,
            requireNotNull(bare.valueOrNull()).pushChannel,
        )
    }

    // ---------------------------------------------------------------- §2.3 rules 3 and 4

    /**
     * The four rejections rule 4 says the client *"will pick the wrong one"* of if the backend
     * collapses them. Asserted as a table, because the value of the split is entirely in the
     * differences between rows.
     *
     * Note that four causes map to **three** recoveries, deliberately. Skew and a rate-limit
     * rejection are different faults with the same right answer — stop pushing now, try on a
     * later foreground — because Android has no API to set the system clock outside a
     * device-owner app, so "retry after a clock sync" really is "retry later". The causes stay
     * distinguishable in the failure *type*, which is what gets logged and what BIT-35's support
     * view would read; only the behaviour is shared.
     */
    @Test
    fun `the four rejection kinds are distinguished, and drive three different behaviours`() {
        fun failure(code: Int, slug: String?): ApiFailure =
            requireNotNull(
                DeviceTokenPatch.parse(
                    HttpResponse(code, slug?.let { """{"error":"$it"}""" } ?: ""),
                ).failureOrNull(),
            )

        val badSignature = failure(401, "bad_signature")
        val skew = failure(401, "timestamp_skew")
        val noCustomer = failure(404, "no_such_customer")
        val rateLimited = failure(429, null)

        assertTrue(badSignature is ApiFailure.BadSignature)
        assertTrue(skew is ApiFailure.ClockSkew)
        assertTrue(noCustomer is ApiFailure.NoSuchCustomer)
        assertTrue(rateLimited is ApiFailure.RateLimited)

        assertEquals(ApiFailure.Recovery.STOP, badSignature.recovery)
        assertEquals(ApiFailure.Recovery.RETRY_LATER, skew.recovery)
        assertEquals(ApiFailure.Recovery.RETRY_AFTER_REGISTRATION, noCustomer.recovery)
        assertEquals(ApiFailure.Recovery.RETRY_LATER, rateLimited.recovery)

        // The one that matters most: a bad signature and a missing customer row — rule 4's exact
        // pair — must never end up on the same path.
        assertNotEquals(badSignature.recovery, noCustomer.recovery)
    }

    /**
     * The asymmetry the classifier is built around. STOP abandons a customer's push route for
     * the life of the install, so it is never inferred; everything unplaced retries inside the
     * §2.3 rule 2 budget, which is bounded at one call per foreground.
     *
     * The case that makes this concrete is today's: the endpoint does not exist on any backend,
     * so every call 404s with no slug. Reading that as "no such customer, give up" would have
     * this client abandon an endpoint before it shipped.
     */
    @Test
    fun `an unrecognised rejection retries in budget and never stops`() {
        fun recovery(code: Int, body: String): ApiFailure.Recovery =
            requireNotNull(DeviceTokenPatch.parse(HttpResponse(code, body)).failureOrNull()).recovery

        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, recovery(404, ""))
        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, recovery(401, ""))
        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, recovery(403, """{"error":"forbidden"}"""))
        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, recovery(500, "<html>502 Bad Gateway</html>"))
        assertNotEquals(ApiFailure.Recovery.STOP, recovery(401, ""))
    }

    /**
     * Prose is not a slug. `message` carries customer-facing text, and feeding it to the
     * classifier would eventually match a slug by accident — on the one set whose false positive
     * is permanent.
     */
    @Test
    fun `a customer-facing message is never read as an error slug`() {
        val failure = requireNotNull(
            DeviceTokenPatch.parse(
                HttpResponse(400, """{"message":"bad_signature"}"""),
            ).failureOrNull(),
        )
        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, failure.recovery)
    }

    /** §2.3 rules 3-4 describe rejections without promising a 4xx. Both routes classify alike. */
    @Test
    fun `a 2xx carrying success false classifies by slug just as a 4xx would`() {
        val failure = requireNotNull(
            DeviceTokenPatch.parse(
                HttpResponse(200, """{"success":false,"error":"no_such_customer"}"""),
            ).failureOrNull(),
        )
        assertEquals(ApiFailure.Recovery.RETRY_AFTER_REGISTRATION, failure.recovery)
    }

    // ---------------------------------------------------------------- §2.4, the Boltz mint

    /** Three parts, not five — `SwapManager.swift:85-95`. Matching the siblings would 401. */
    @Test
    fun `the boltz message is the three-part construction that endpoint already verifies`() {
        assertEquals("boltz_webhook:02aabb:1757000000", BoltzWebhook.message("02aabb", 1_757_000_000))
    }

    @Test
    fun `the boltz mint is a GET carrying its signature in the query string`() {
        val request = BoltzWebhook.request(env, signed)

        assertEquals(HttpMethod.GET, request.method)
        assertEquals(
            "${env.apiBaseUrl}/boltz/webhook-token" +
                "?pubkey=02aabb&timestamp=1757000000&signature=sig",
            request.url,
        )
        // HttpRequest's own invariant: a GET must not carry a body.
        assertEquals(null, request.jsonBody)
    }

    /**
     * §2.4's compare, ported as a value rather than the log line iOS leaves at
     * `SwapManager.swift:77-80`. A URL minted against a token the backend no longer holds is the
     * exact failure BIT-41 deliverable 6 exists to prevent, arriving by a different route.
     */
    @Test
    fun `a mint against a different token is reported as a mismatch, not accepted quietly`() {
        val body = """{"success":true,"url":"https://boltz.example/hook/abc","device_token":"old-token"}"""

        assertFalse(
            requireNotNull(BoltzWebhook.parse(HttpResponse(200, body), "new-token").valueOrNull())
                .tokenMatchesLocal,
        )
        assertTrue(
            requireNotNull(BoltzWebhook.parse(HttpResponse(200, body), "old-token").valueOrNull())
                .tokenMatchesLocal,
        )
    }

    /** `SwapManager.swift:68-73` requires `success: true` and a `url`; anything else is not a mint. */
    @Test
    fun `a boltz response without success or url is a failure`() {
        assertTrue(
            BoltzWebhook.parse(
                HttpResponse(200, """{"success":false,"error":"bad_signature"}"""),
                "token",
            ) is ApiResult.Failure,
        )
        assertTrue(
            BoltzWebhook.parse(HttpResponse(200, """{"success":true}"""), "token") is ApiResult.Failure,
        )
    }
}
