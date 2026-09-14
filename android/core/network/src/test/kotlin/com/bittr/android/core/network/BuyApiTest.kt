package com.bittr.android.core.network

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BuyApiTest {

    private val env = BittrEnvironment.DEVELOPMENT
    private val signed = SignedRequest(pubkey = "02abc", signature = "sig+/=", timestampSeconds = 1_700_000_000)

    private fun bodyOf(request: HttpRequest): JsonObject =
        Json.parseToJsonElement(requireNotNull(request.jsonBody)) as JsonObject

    @Test
    fun `check2fa sends the trimmed code and the pubkey only when there is one`() {
        val withNode = bodyOf(EmailCheck2fa.request(env, "a@b.com", " 123456 ", "02abc"))
        assertEquals(JsonPrimitive("a@b.com"), withNode["email_address"])
        assertEquals(JsonPrimitive("123456"), withNode["token_2fa"])
        assertEquals(JsonPrimitive("02abc"), withNode["lightning_pubkey"])
        assertFalse(bodyOf(EmailCheck2fa.request(env, "a@b.com", "1", null)).containsKey("lightning_pubkey"))
        assertEquals("https://staging.getbittr.com/api/verify/email/check2fa", EmailCheck2fa.request(env, "a", "b", null).url)
    }

    @Test
    fun `check2fa reads a token, the invalid-code message and other messages whatever the status`() {
        assertEquals(
            EmailCheck2fa.Outcome.Verified("tok", "DC1", "msg"),
            EmailCheck2fa.parse(HttpResponse(200, """{"token":"tok","deposit_code":"DC1","message":"msg"}""")),
        )
        assertEquals(
            EmailCheck2fa.Outcome.InvalidCode,
            EmailCheck2fa.parse(HttpResponse(400, """{"message":"Invalid 2FA verification token provided"}""")),
        )
        assertEquals(EmailCheck2fa.Outcome.Error("nope"), EmailCheck2fa.parse(HttpResponse(500, """{"message":"nope"}""")))
        assertEquals(EmailCheck2fa.Outcome.Error(null), EmailCheck2fa.parse(HttpResponse(200, "{}")))
        assertNull(EmailCheck2fa.parse(HttpResponse(502, "<html>")))
    }

    @Test
    fun `customer signup reads the partner details or the server message`() {
        assertEquals(
            CustomerSignup.Outcome.Created("CH00", "DC1", "SWIFT", ""),
            CustomerSignup.parse(HttpResponse(200, """{"data":{"iban":"CH00","deposit_code":"DC1","swift":"SWIFT"}}""")),
        )
        assertEquals(
            CustomerSignup.Outcome.InvalidIban,
            CustomerSignup.parse(HttpResponse(400, """{"message":"Unable to create customer account (invalid iban)"}""")),
        )
        assertEquals(CustomerSignup.Outcome.Message("x"), CustomerSignup.parse(HttpResponse(400, """{"message":"x"}""")))
        assertEquals(CustomerSignup.Outcome.Unrecognised, CustomerSignup.parse(HttpResponse(200, "{}")))
    }

    @Test
    fun `deposit code is a signed GET with the iOS message`() {
        assertEquals("deposit_codes:02abc:1700000000", DepositCodeFetch.message("02abc", 1_700_000_000))
        val request = DepositCodeFetch.request(env, signed)
        assertEquals(HttpMethod.GET, request.method)
        assertEquals(
            "https://staging.getbittr.com/api/deposit_code?timestamp=1700000000&signature=sig%2B%2F%3D&pubkey=02abc",
            request.url,
        )
        assertEquals(
            DepositCodeFetch.Details("DC1", "CH00", "SW", null, "onchain"),
            DepositCodeFetch.parse(
                HttpResponse(200, """{"data":{"deposit_code":"DC1","iban":"CH00","swift":"SW","payment_mode":"onchain"}}"""),
            ),
        )
        assertNull(DepositCodeFetch.parse(HttpResponse(200, """{"data":{"deposit_code":"DC1"}}""")))
    }

    @Test
    fun `payment mode patch signs mode lightning and reads the confirmed mode or the error`() {
        assertEquals(
            "payment_mode:02abc:DC1:lightning:1700000000",
            PaymentModePatch.message("02abc", "DC1", PaymentMode.LIGHTNING, 1_700_000_000),
        )
        val body = bodyOf(PaymentModePatch.request(env, "DC1", PaymentMode.ONCHAIN, signed))
        assertEquals(JsonPrimitive(1_700_000_000L), body["timestamp"])
        assertEquals(JsonPrimitive("onchain"), body["payment_mode"])
        assertEquals(
            PaymentModePatch.Outcome.Confirmed("onchain"),
            PaymentModePatch.parse(HttpResponse(200, """{"data":{"payment_mode":"onchain"}}""")),
        )
        val expired = PaymentModePatch.parse(HttpResponse(401, """{"success":false,"error":"Expired timestamp"}"""))
        assertTrue((expired as PaymentModePatch.Outcome.ServerError).isExpiredTimestamp)
        assertEquals(
            PaymentModePatch.Outcome.ServerError("Unknown error"),
            PaymentModePatch.parse(HttpResponse(200, """{"success":false}""")),
        )
    }

    @Test
    fun `transaction info signs codes then ids and reads numbers or numeric strings`() {
        assertEquals("DC1,DC2tx1,tx2", TransactionInfo.message(listOf("tx1", "tx2"), listOf("DC1", "DC2")))
        val rows = TransactionInfo.parse(
            HttpResponse(
                200,
                """{"success":true,"data":[{"tx_id":"tx1","currency":"EUR","bitcoin_amount":"0.001","fiat_amount_net":95.5},{"currency":"CHF"}]}""",
            ),
        )!!
        assertEquals(1, rows.size)
        assertEquals(0.001, rows[0].bitcoinAmount!!, 1e-12)
        assertEquals(95.5, rows[0].fiatAmountNet!!, 1e-12)
        assertNull(TransactionInfo.parse(HttpResponse(200, """{"success":false}""")))
    }
}
