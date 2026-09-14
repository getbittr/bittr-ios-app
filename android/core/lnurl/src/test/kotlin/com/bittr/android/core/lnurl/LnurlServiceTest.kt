package com.bittr.android.core.lnurl

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LnurlServiceTest {

    @Test
    fun `a pay request with a range reads its callback, limits and last text description`() {
        val body = """{"tag":"payRequest","callback":"https://spiritedlizard2.lnbits.com/lnurlp/api/v1/lnurl/cb/FRV7Uj",
            "minSendable":1000,"maxSendable":100000000,
            "metadata":"[[\"text/plain\", \"Payment to tom\"], [\"text/identifier\", \"tom@spiritedlizard2.lnbits.com\"]]"}"""
        assertEquals(
            LnurlServiceResponse.Pay(
                callback = "https://spiritedlizard2.lnbits.com/lnurlp/api/v1/lnurl/cb/FRV7Uj",
                minSendableMsat = 1000,
                maxSendableMsat = 100_000_000,
                description = "Payment to tom",
            ),
            LnurlService.parse(body),
        )
    }

    @Test
    fun `iOS keeps the last text-plain entry when there are two`() {
        assertEquals("second", LnurlService.description("""[["text/plain","first"],["text/plain","second"]]"""))
        assertEquals(null, LnurlService.description("not json"))
    }

    @Test
    fun `withdraw, login, unknown tags and garbage are told apart`() {
        assertEquals(
            LnurlServiceResponse.Withdraw("https://x.com/cb", "abc", 10_000, 10_000),
            LnurlService.parse("""{"tag":"withdrawRequest","callback":"https://x.com/cb","k1":"abc","minWithdrawable":10000,"maxWithdrawable":10000}"""),
        )
        assertEquals(
            LnurlServiceResponse.Login("https://x.com/auth", "k", "login"),
            LnurlService.parse("""{"tag":"login","callback":"https://x.com/auth","k1":"k","action":"login"}"""),
        )
        assertEquals(LnurlServiceResponse.Unsupported, LnurlService.parse("""{"tag":"channelRequest"}"""))
        assertEquals(LnurlServiceResponse.Unsupported, LnurlService.parse("""{"tag":"payRequest","callback":"https://x.com"}"""))
        assertEquals(LnurlServiceResponse.Unreadable, LnurlService.parse("<html>"))
    }

    @Test
    fun `the pay callback gives an invoice or the service's detail`() {
        assertEquals(LnurlPayCallback.Invoice("lnbc1"), LnurlService.parsePayCallback("""{"pr":" lnbc1 ","routes":[]}"""))
        assertEquals(
            LnurlPayCallback.Refused("Unable to connect to https://api.getalby.com."),
            LnurlService.parsePayCallback("""{"detail":"Unable to connect to https://api.getalby.com.","status":"pending"}"""),
        )
    }

    @Test
    fun `status OK is the only success`() {
        assertTrue(LnurlService.parseStatus("""{"status":"OK"}""").ok)
        val refused = LnurlService.parseStatus("""{"status":"ERROR","reason":"expired"}""")
        assertFalse(refused.ok)
        assertEquals("expired", refused.reason)
    }

    @Test
    fun `callback parameters are appended to an existing query and encoded`() {
        assertEquals("https://x.com/cb?amount=1500000", LnurlService.withQuery("https://x.com/cb", "amount" to "1500000"))
        assertEquals(
            "https://x.com/cb?id=7&k1=a%2Bb&pr=lnbc1",
            LnurlService.withQuery("https://x.com/cb?id=7&k1=old", "k1" to "a+b", "pr" to "lnbc1"),
        )
    }

    @Test
    fun `the auth seed and linking key are HMAC-SHA256 as on iOS`() {
        val seed = LnurlAuthKeys.seed("  Attack urge ACROSS  ")
        assertArrayEquals(seed, LnurlAuthKeys.seed("attack urge across"))
        assertEquals(32, seed.size)
        // Host case never changes the key.
        assertArrayEquals(LnurlAuthKeys.linkingPrivateKey(seed, "Site.com"), LnurlAuthKeys.linkingPrivateKey(seed, "site.com"))
        assertEquals("Log in", LnurlAuthKeys.actionText("LOGIN"))
        assertEquals("Authenticate", LnurlAuthKeys.actionText(null))
    }
}
