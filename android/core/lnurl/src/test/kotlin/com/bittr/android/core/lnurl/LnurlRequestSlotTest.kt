package com.bittr.android.core.lnurl

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 R-10: one in-flight LNURL request, cancelled on navigation and on
 * dismissal.
 *
 * iOS's version of this is `isHandlingLnurlAuth`, a boolean that is set on the
 * way in and never cleared — so the second LNURL a page offers is dropped for the
 * lifetime of the screen, including after the first one failed. And nothing
 * cancels an in-flight request when the screen goes away, so a response can
 * arrive to a dismissed controller. Both halves are tested here.
 */
class LnurlRequestSlotTest {

    @Test
    fun `a fresh slot has nothing in flight`() {
        val slot = LnurlRequestSlot()

        assertNull(slot.inFlight)
        assertFalse("Cancelling an idle slot reports nothing cancelled.", slot.cancel())
    }

    @Test
    fun `a second request supersedes the first`() {
        val slot = LnurlRequestSlot()

        val first = slot.begin("pay.example.com")
        val second = slot.begin("other.example.com")

        assertFalse(
            "The superseded request must not be able to deliver a result — that is what " +
                "stops a slow first response from opening a dialog over the second.",
            first.isCurrent,
        )
        assertTrue(second.isCurrent)
    }

    @Test
    fun `cancelling stops the in-flight request from delivering`() {
        val slot = LnurlRequestSlot()
        val ticket = slot.begin("pay.example.com")

        assertTrue("Something was in flight, so cancel reports true.", slot.cancel())

        assertFalse(
            "This is the case iOS does not handle: a response arriving after the screen " +
                "is gone. A ticket that is not current must not deliver.",
            ticket.isCurrent,
        )
        assertNull(slot.inFlight)
    }

    @Test
    fun `finishing releases the slot for the next request`() {
        // The iOS failure this covers: a boolean set and never cleared means the
        // NEXT legitimate LNURL is silently ignored, including after a failure.
        val slot = LnurlRequestSlot()

        val first = slot.begin("pay.example.com")
        first.finish()
        assertNull(slot.inFlight)

        val second = slot.begin("pay.example.com")
        assertTrue("A new request must be able to start after the previous one ended.", second.isCurrent)
    }

    @Test
    fun `finishing a superseded ticket does not release the current one`() {
        val slot = LnurlRequestSlot()

        val first = slot.begin("first")
        val second = slot.begin("second")
        first.finish()

        assertTrue(
            "A late-completing superseded request must not clear the slot out from " +
                "under the request that replaced it.",
            second.isCurrent,
        )
    }
}
