package com.bittr.android.lnurl

import com.bittr.android.core.push.PushEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LightningAddressPushTest {

    private val push = PushEnvelope.LightningAddress(
        amountMsats = 1_500_000,
        metadata = """[["text/plain","Payment to e2ebittr"]]""",
        timeSent = "1757900000",
        username = "e2ebittr",
        endpoint = "https://pay.example.com/lnurl-invoice",
    )

    @Test
    fun `the steps follow iOS's order`() {
        val handler = LightningAddressPush(lightning = unused(), http = unusedHttp())
        assertEquals(LightningAddressPush.Step.AskToSignIn, handler.step(signedIn = false, synced = true, wasNotified = false))
        assertEquals(LightningAddressPush.Step.WaitForSync, handler.step(signedIn = true, synced = false, wasNotified = true))
        assertEquals(LightningAddressPush.Step.HandleNow, handler.step(signedIn = true, synced = true, wasNotified = true))
        assertEquals(LightningAddressPush.Step.AskHandleNow, handler.step(signedIn = true, synced = true, wasNotified = false))
    }

    @Test
    fun `a push missing a field is dropped`() {
        val handler = LightningAddressPush(lightning = unused(), http = unusedHttp())
        assertEquals(1_500_000L, handler.request(push)!!.amountMsats)
        assertNull(handler.request(push.copy(endpoint = "")))
        assertNull(handler.request(push.copy(amountMsats = 0)))
    }

    @Test
    fun `the description hash is the hex SHA-256 of the metadata`() {
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            LightningAddressPush.descriptionHash(""),
        )
        assertEquals("1 500", LightningAddressPushCopy.amountSats(1_500_000))
    }

    private fun unused(): com.bittr.android.core.wallet.ldk.lightning.LightningNodePort =
        java.lang.reflect.Proxy.newProxyInstance(
            javaClass.classLoader,
            arrayOf(com.bittr.android.core.wallet.ldk.lightning.LightningNodePort::class.java),
        ) { _, _, _ -> error("not used") } as com.bittr.android.core.wallet.ldk.lightning.LightningNodePort

    private fun unusedHttp() = object : com.bittr.android.core.network.HttpClient {
        override suspend fun execute(request: com.bittr.android.core.network.HttpRequest) = error("not used")
    }
}
