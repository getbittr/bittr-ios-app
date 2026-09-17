package com.bittr.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Test

class PendingPayoutsTest {

    private fun item(id: String, amount: String = "0.0001", sentAt: String? = "2026-09-15T08:00:00") =
        """{"inserted_at":"2026-09-15T07:59:00",${sentAt?.let { "\"sent_at\":\"$it\"," } ?: ""}"status":"sent",""" +
            """"notification_type":"lightning_payout","attempts_count":1,"id":"$id",""" +
            """"last_attempt_at":"2026-09-15T08:00:00","transaction":{"bitcoin_amount":"$amount"}}"""

    @Test
    fun `the signed message and query match iOS`() {
        assertEquals("notifications:02pub:1700000000", PendingPayouts.message("02pub", 1_700_000_000))
        assertEquals(
            BittrEnvironment.DEVELOPMENT.url("notifications") + "?timestamp=1700000000&signature=sig%3Dab&pubkey=02pub",
            PendingPayouts.request(BittrEnvironment.DEVELOPMENT, 1_700_000_000, "sig=ab", "02pub").url,
        )
    }

    @Test
    fun `the newest complete notification is the payout, in millisatoshis`() {
        val body = """{"data":[${item("n1", "0.0002")},${item("n2", "0.0001")}]}"""
        assertEquals(
            PendingPayouts.Outcome.Available("n2", 10_000_000),
            PendingPayouts.parse(HttpResponse(200, body)),
        )
    }

    @Test
    fun `reading stops at the first incomplete notification, as iOS's break does`() {
        val body = """{"data":[${item("n1")},${item("n2", sentAt = null)},${item("n3")}]}"""
        assertEquals(PendingPayouts.Outcome.Available("n1", 10_000_000), PendingPayouts.parse(HttpResponse(200, body)))
    }

    @Test
    fun `a payout already processed is skipped for the next one`() {
        val body = """{"data":[${item("n1", "0.0002")},${item("n2", "0.0001")}]}"""
        assertEquals(
            PendingPayouts.Outcome.Available("n1", 20_000_000),
            PendingPayouts.parse(HttpResponse(200, body), skip = setOf("n2")),
        )
        assertEquals(PendingPayouts.Outcome.None, PendingPayouts.parse(HttpResponse(200, body), skip = setOf("n1", "n2")))
    }

    @Test
    fun `no data, an empty list or an unreadable body is no payout`() {
        listOf("""{"data":[]}""", """{"success":false}""", "not json", "").forEach { body ->
            assertEquals(body, PendingPayouts.Outcome.None, PendingPayouts.parse(HttpResponse(200, body)))
        }
        assertEquals(PendingPayouts.Outcome.None, PendingPayouts.parse(HttpResponse(200, """{"data":[${item("n1", "abc")}]}""")))
    }

    @Test
    fun `bitcoin amounts round to whole satoshis`() {
        assertEquals(100_000_000_000L, PendingPayouts.bitcoinToMsats("1"))
        assertEquals(1_000L, PendingPayouts.bitcoinToMsats("0.00000001"))
        assertEquals(12_346_000L, PendingPayouts.bitcoinToMsats("0.000123456"))
    }
}
