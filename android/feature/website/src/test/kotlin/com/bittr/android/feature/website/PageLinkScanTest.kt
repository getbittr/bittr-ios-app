package com.bittr.android.feature.website

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PageLinkScanTest {

    @Test
    fun `a found link comes back as a JSON string and is unescaped`() {
        assertEquals("lightning:LNURL1DP68GURN8GHJ7", PageLinkScan.parse("\"lightning:LNURL1DP68GURN8GHJ7\""))
        assertEquals("lnurl1dp68gurn8ghj7um", PageLinkScan.parse("\"lnurl1dp68gurn8ghj7um\""))
        assertEquals("lightning:a\"b", PageLinkScan.parse("\"lightning:a\\\"b\""))
        assertEquals("lightning:x", PageLinkScan.parse("\"lightning\\u003Ax\""))
    }

    @Test
    fun `nothing found, or anything that isn't a lightning link, is null`() {
        assertNull(PageLinkScan.parse("null"))
        assertNull(PageLinkScan.parse(null))
        assertNull(PageLinkScan.parse("\"\""))
        assertNull(PageLinkScan.parse("\"https://evil.example\""))
        assertNull(PageLinkScan.parse("42"))
    }

    @Test
    fun `the script matches iOS's lnurlFrom and runs as an expression`() {
        assertTrue("lightning:" in PageLinkScan.SCRIPT)
        assertTrue("lnurl:" in PageLinkScan.SCRIPT)
        assertTrue("^lnurl1[02-9ac-hj-np-z]{6,}\$/" in PageLinkScan.SCRIPT)
        assertTrue("messageHandlers" !in PageLinkScan.SCRIPT)
    }
}
