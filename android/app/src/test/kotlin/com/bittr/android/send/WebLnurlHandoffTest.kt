package com.bittr.android.send

import com.bittr.android.core.lnurl.LnurlSource
import com.bittr.android.feature.send.SendLnurlRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WebLnurlHandoffTest {

    @Test
    fun `a posted LNURL is taken once`() {
        val handoff = WebLnurlHandoff()
        val request = SendLnurlRequest("lnurl1abc", LnurlSource.FirstPartyWeb("https://getbittr.com", "Support"))

        assertNull(handoff.take())
        handoff.post(request)
        assertEquals(request, handoff.take())
        assertNull("Reopening Send must not replay the page's LNURL", handoff.take())
    }
}
