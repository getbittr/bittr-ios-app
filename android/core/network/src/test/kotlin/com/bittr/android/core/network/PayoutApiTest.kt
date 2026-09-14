package com.bittr.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PayoutApiTest {

    private val env = BittrEnvironment.DEVELOPMENT

    @Test
    fun `htlc ready posts the signed deposit code as JSON`() {
        val request = HtlcReady.request(env, "ABC123", 1_700_000_000, "02pub", "sig")
        assertEquals(HttpMethod.POST, request.method)
        assertEquals(env.url("htlc-interceptor/ready"), request.url)
        val body = request.jsonBody!!
        assertTrue(body, "\"deposit_code\":\"ABC123\"" in body)
        assertTrue(body, "\"timestamp\":1700000000" in body)
        assertTrue(body, "\"pubkey\":\"02pub\"" in body)
        assertTrue(body, "\"signature\":\"sig\"" in body)
        assertEquals("htlc_ready:ABC123:1700000000", HtlcReady.message("ABC123", 1_700_000_000))
    }

    @Test
    fun `htlc ready outcomes follow facilitateHTLCReady`() {
        assertEquals(HtlcReady.Outcome.Resumed, HtlcReady.parse(HttpResponse(200, """{"success":true,"action":"resumed"}""")))
        assertEquals(HtlcReady.Outcome.TimedOut, HtlcReady.parse(HttpResponse(200, """{"success":true,"action":"failed_timeout"}""")))
        assertEquals(
            HtlcReady.Outcome.Failed("no_held_htlc"),
            HtlcReady.parse(HttpResponse(200, """{"success":false,"error":"no_held_htlc"}""")),
        )
        assertEquals(
            HtlcReady.Outcome.Failed("no_held_htlc"),
            HtlcReady.parse(HttpResponse(404, """{"success":false,"error":"no_held_htlc"}""")),
        )
        assertEquals(HtlcReady.Outcome.Failed("Unknown error"), HtlcReady.parse(HttpResponse(500, """{"success":false}""")))
        assertEquals(HtlcReady.Outcome.Failed(null), HtlcReady.parse(HttpResponse(502, "<html>")))
    }

    @Test
    fun `lightning payout carries everything in the query`() {
        val request = LightningPayout.request(env, "n 1", "lnbcrt1", "s+g", "02pub")
        assertEquals(HttpMethod.POST, request.method)
        assertNull(request.jsonBody)
        assertEquals(
            env.url("payout/lightning") + "?notification_id=n%201&invoice=lnbcrt1&signature=s%2Bg&pubkey=02pub",
            request.url,
        )
    }

    @Test
    fun `lightning payout outcomes key off error_code`() {
        assertEquals(LightningPayout.Outcome.Paid("pre"), LightningPayout.parse(HttpResponse(200, """{"success":true,"pre_image":"pre"}""")))
        assertEquals(LightningPayout.Outcome.Error(LightningPayout.NO_DATA), LightningPayout.parse(HttpResponse(200, """{"success":true}""")))
        assertEquals(LightningPayout.Outcome.Error(LightningPayout.COULD_NOT_CONNECT), LightningPayout.parse(HttpResponse(500, "")))
        assertEquals(
            LightningPayout.Outcome.ChannelFull("full", "50000"),
            LightningPayout.parse(HttpResponse(200, """{"success":false,"error":"full","error_code":"CHANNEL_FULL","suggested_swap_amount":"50000"}""")),
        )
        assertEquals(
            LightningPayout.Outcome.Error("full"),
            LightningPayout.parse(HttpResponse(200, """{"success":false,"error":"full","error_code":"CHANNEL_FULL"}""")),
        )
        assertEquals(
            LightningPayout.Outcome.Processing("Your payment is being processed and should complete shortly."),
            LightningPayout.parse(HttpResponse(200, """{"success":false,"error_code":"PAYMENT_PROCESSING"}""")),
        )
        assertEquals(
            LightningPayout.Outcome.TooLarge("big"),
            LightningPayout.parse(HttpResponse(200, """{"success":false,"error":"big","error_code":"PAYMENT_TOO_LARGE"}""")),
        )
        assertEquals(
            LightningPayout.Outcome.Error("This payment has already been processed."),
            LightningPayout.parse(HttpResponse(200, """{"success":false,"error":"This payment has already been processed."}""")),
        )
    }

    @Test
    fun `onchain payout reports a message only on failure`() {
        assertEquals(
            env.url("payout/onchain") + "?notification_id=n1&signature=sig&pubkey=02pub",
            OnchainPayout.request(env, "n1", "sig", "02pub").url,
        )
        assertNull(OnchainPayout.parse(HttpResponse(200, """{"success":true}""")))
        assertEquals("nope", OnchainPayout.parse(HttpResponse(200, """{"success":false,"error":"nope"}""")))
        assertEquals(OnchainPayout.COULD_NOT_CONNECT, OnchainPayout.parse(HttpResponse(503, "")))
    }
}
