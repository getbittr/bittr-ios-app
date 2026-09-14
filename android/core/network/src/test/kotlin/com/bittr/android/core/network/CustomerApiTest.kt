package com.bittr.android.core.network

import com.bittr.android.core.push.PushChannel
import com.bittr.android.core.push.PushChannelAction
import com.bittr.android.core.push.PushChannelReason
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-41 item 2 — `category: "android"` on both registration endpoints, and what the response
 * means. `api-contract` §2.1, §2.2 and §4.
 */
class CustomerApiTest {

    private val env = BittrEnvironment.DEVELOPMENT

    private fun bodyOf(request: HttpRequest): JsonObject =
        Json.parseToJsonElement(requireNotNull(request.jsonBody)) as JsonObject

    private fun fields() = CustomerRegistration.Fields(
        email = "satoshi@example.com",
        emailToken = "123456",
        bitcoinAddress = "bc1qexample",
        bitcoinMessage = "message",
        bitcoinSignature = "sig",
        iban = "NL91ABNA0417164300",
        lightningPubkey = "02aabb",
        lightningSignature = "lnsig",
        xpubKey = "zpub123",
    )

    // ---------------------------------------------------------------- §2.2, verify/email

    @Test
    fun `verify email sends category android`() {
        val body = bodyOf(EmailVerification.request(env, "satoshi@example.com", "NL91ABNA0417164300"))

        assertEquals(JsonPrimitive("android"), body["category"])
        // The other two fields are exactly Transfer1ViewController.swift:409-413, unchanged.
        assertEquals(JsonPrimitive("satoshi@example.com"), body["email"])
        assertEquals(JsonPrimitive("NL91ABNA0417164300"), body["iban"])
        assertEquals(3, body.size)
    }

    @Test
    fun `verify email posts to the environment's host, never a literal`() {
        assertEquals(
            "${BittrEnvironment.DEVELOPMENT.apiBaseUrl}/verify/email",
            EmailVerification.request(BittrEnvironment.DEVELOPMENT, "e", "i").url,
        )
        assertEquals(
            "${BittrEnvironment.PRODUCTION.apiBaseUrl}/verify/email",
            EmailVerification.request(BittrEnvironment.PRODUCTION, "e", "i").url,
        )
    }

    /**
     * The polarity that fails every good registration if inverted. `POST /verify/email` sends no
     * `success` field on the happy path — `Transfer1ViewController.swift:422` only acts on an
     * explicit `false`.
     */
    @Test
    fun `verify email treats an absent success field as acceptance`() {
        val parsed = EmailVerification.parse(HttpResponse(200, """{"data":{}}"""))
        assertEquals(EmailVerification.Outcome.Accepted, parsed.valueOrNull())
    }

    @Test
    fun `verify email surfaces the backend's own rejection message`() {
        val parsed = EmailVerification.parse(
            HttpResponse(200, """{"success":false,"message":"IBAN could not be validated"}"""),
        )
        assertEquals(
            EmailVerification.Outcome.Rejected("IBAN could not be validated"),
            parsed.valueOrNull(),
        )
    }

    // ---------------------------------------------------------------- §2.1, POST /customer

    @Test
    fun `registration sends category android and the FCM token under its own field`() {
        val body = bodyOf(CustomerRegistration.request(env, fields(), androidDeviceToken = "fcm-token"))

        assertEquals(JsonPrimitive("android"), body["category"])
        assertEquals(JsonPrimitive("fcm-token"), body["android_device_token"])
    }

    /**
     * §4.2's `platform_mismatch` is computed from the fields on *this request*, so a client that
     * sends `ios_device_token` manufactures a slug §9 routes to support as our own defect.
     * "Not rejected" in §2.1 is forward compatibility for the backend, not licence for us.
     */
    @Test
    fun `registration never sends the other platform's token field`() {
        val withToken = bodyOf(CustomerRegistration.request(env, fields(), "fcm-token"))
        val withoutToken = bodyOf(CustomerRegistration.request(env, fields(), null))

        assertNull(withToken["ios_device_token"])
        assertNull(withoutToken["ios_device_token"])
    }

    /**
     * §2.1: *"`category: "android"` with no `android_device_token` at all is a normal, accepted
     * registration — not an error."* The key is absent, not `""` and not JSON null.
     */
    @Test
    fun `registration with no token omits the field entirely`() {
        val body = bodyOf(CustomerRegistration.request(env, fields(), androidDeviceToken = null))

        assertFalse("android_device_token" in body)
        assertEquals(JsonPrimitive("android"), body["category"])
    }

    /**
     * §2.1: the backend *"does not infer or downgrade `payment_mode` on its own"*, so an absent
     * field has to stay absent. `Transfer2ViewController.swift:367-369` adds it only when the
     * client decided it.
     */
    @Test
    fun `payment_mode is sent only when the client decided it`() {
        assertFalse("payment_mode" in bodyOf(CustomerRegistration.request(env, fields(), null)))
        assertEquals(
            JsonPrimitive("onchain"),
            bodyOf(
                CustomerRegistration.request(env, fields().copy(paymentMode = "onchain"), null),
            )["payment_mode"],
        )
    }

    @Test
    fun `every field iOS sends is present`() {
        val body = bodyOf(
            CustomerRegistration.request(
                env,
                fields().copy(
                    paymentMode = "onchain",
                    exclusiveInitiativeConfirmedAt = "2026-09-14T00:00:00Z",
                    depositCode = "ABC123",
                ),
                "fcm-token",
            ),
        )
        // Transfer2ViewController.swift:347-387, with ios_device_token swapped for the Android
        // field. Asserted as a set so a dropped field fails here rather than at signup.
        assertEquals(
            setOf(
                "email", "email_token", "bitcoin_address", "initial_address_type", "category",
                "bitcoin_message", "bitcoin_signature", "iban", "lightning_pubkey",
                "lightning_signature", "xpub_key", "xpub_addr_type", "xpub_path",
                "skip_xpub_usage_check", "android_device_token", "payment_mode",
                "exclusive_initiative_confirmed_at", "deposit_code",
            ),
            body.keys,
        )
    }

    // ---------------------------------------------------------------- §4, the response

    @Test
    fun `a validated registration reads deposit code and a live route`() {
        val parsed = CustomerRegistration.parse(
            HttpResponse(
                200,
                """{"data":{"deposit_code":"ABC123","iban":"NL..","swift":"ABNANL2A",
                   "push_channel":"fcm"}}""",
            ),
        )
        val registered = requireNotNull(parsed.valueOrNull())

        assertEquals("ABC123", registered.depositCode)
        assertEquals(PushChannel.FCM, registered.pushChannel.channel)
        assertEquals(PushChannelAction.Registered(PushChannel.FCM), registered.action)
        assertFalse(registered.showsRegistrationFailureCopy)
    }

    /**
     * §4.1: a token the backend cannot use must **not** fail the request. Rejecting it would
     * dead-end signup with no customer record and no deposit code, over a problem the customer
     * cannot fix. So this is a success carrying a bad route, and BIT-46's "site 2".
     */
    @Test
    fun `a registration with no push route still succeeds and still yields a deposit code`() {
        val parsed = CustomerRegistration.parse(
            HttpResponse(
                200,
                """{"data":{"deposit_code":"ABC123","push_channel":"none",
                   "push_channel_reason":"unregistered"}}""",
            ),
        )
        val registered = requireNotNull(parsed.valueOrNull())

        assertEquals("ABC123", registered.depositCode)
        assertEquals(
            PushChannelAction.TokenRejected(PushChannelReason.UNREGISTERED),
            registered.action,
        )
        assertTrue(registered.showsRegistrationFailureCopy)
        // §4.3: a token was sent and the verdict is about *that token*, so the downgrade is not
        // on offer yet.
        assertFalse(registered.action.mayOfferOnchainDowngrade)
    }

    /**
     * The token is only "acknowledged" when the backend reports a live route. `unavailable` is
     * the case where we sent one and have no verdict — priming the cache from it would make the
     * next app start skip the retry that §4.3 depends on.
     */
    @Test
    fun `only a live route acknowledges the token that was sent`() {
        fun acknowledged(channel: String, reason: String?): String? =
            requireNotNull(
                CustomerRegistration.parse(
                    HttpResponse(
                        200,
                        """{"data":{"push_channel":"$channel"""" +
                            (reason?.let { ""","push_channel_reason":"$it"""" } ?: "") + "}}",
                    ),
                ).valueOrNull(),
            ).acknowledgedToken("fcm-token")

        assertEquals("fcm-token", acknowledged("fcm", null))
        assertNull(acknowledged("none", "unavailable"))
        assertNull(acknowledged("none", "missing"))
        // An APNS route for a request this client sent as category "android" is a §5 dispatch
        // bug, not an acknowledgement.
        assertNull(acknowledged("apns", null))
    }

    /**
     * §2.1's additivity argument only holds if unknown keys are ignored on both clients. iOS
     * reads `data` key by key with optional casts; this is the Android half of that promise.
     */
    @Test
    fun `unknown response fields are ignored, not fatal`() {
        val parsed = CustomerRegistration.parse(
            HttpResponse(
                200,
                """{"data":{"deposit_code":"ABC123","push_channel":"fcm",
                   "a_field_added_next_year":{"nested":[1,2,3]}},"meta":{"trace":"x"}}""",
            ),
        )
        assertEquals("ABC123", requireNotNull(parsed.valueOrNull()).depositCode)
    }

    @Test
    fun `a non-2xx is a placed failure, not an exception`() {
        val parsed = CustomerRegistration.parse(HttpResponse(500, "upstream exploded"))
        assertEquals(
            ApiFailure.Recovery.RETRY_IN_BUDGET,
            requireNotNull(parsed.failureOrNull()).recovery,
        )
    }
}
