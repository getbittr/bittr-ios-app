package com.bittr.android.feature.send

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SendMathTest {

    @Test
    fun `satoshis take whole numbers and ignore grouping`() {
        assertEquals(294_424L, SendMath.parseSats("294 424", AmountCurrency.Satoshis, null))
        assertNull(SendMath.parseSats("1.5", AmountCurrency.Satoshis, null))
    }

    @Test
    fun `bitcoin takes a point or a comma`() {
        assertEquals(1_000L, SendMath.parseSats("0.00001", AmountCurrency.Bitcoin, null))
        assertEquals(150_000_000L, SendMath.parseSats("1,5", AmountCurrency.Bitcoin, null))
        assertNull(SendMath.parseSats("1.2.3", AmountCurrency.Bitcoin, null))
    }

    @Test
    fun `fiat converts at the price and needs one`() {
        assertEquals(5_000L, SendMath.parseSats("5", AmountCurrency.Fiat, 100_000.0))
        assertNull(SendMath.parseSats("5", AmountCurrency.Fiat, null))
    }

    @Test
    fun `amounts are read as iOS reads them, within 21 million bitcoin`() {
        val locale = Locale.getDefault()
        Locale.setDefault(Locale.US)
        try {
            assertEquals("A thousand euros, not one.", 1_000_000L, SendMath.parseSats("1,000", AmountCurrency.Fiat, 100_000.0))
            assertEquals(50_000L, SendMath.parseSats("50,000", AmountCurrency.Satoshis, null))
            assertNull(SendMath.parseSats("1e-5", AmountCurrency.Bitcoin, null))
            assertNull(SendMath.parseSats("21000000.00000001", AmountCurrency.Bitcoin, null))
            assertTrue(SendMath.isWellFormedAmount("1,000.50", AmountCurrency.Fiat))
            assertFalse(SendMath.isWellFormedAmount("-1", AmountCurrency.Fiat))
            assertFalse(SendMath.isWellFormedAmount("50000.00", AmountCurrency.Satoshis))
        } finally {
            Locale.setDefault(locale)
        }
    }

    @Test
    fun `fiat amounts have two decimals and the symbol`() {
        assertEquals("4.99 €", SendMath.formattedFiat(4_990, 100_000.0, "€"))
    }

    @Test
    fun `fees are whole sats per vbyte, at least one`() {
        assertEquals(141L, SendMath.feeSats(0.4, 141))
        assertEquals(705L, SendMath.feeSats(5.9, 141))
    }

    @Test
    fun `the routing fee cap is LDK's default`() {
        assertEquals(60L, SendMath.maxRoutingFeeSats(1_000))
    }

    @Test
    fun `the available label groups the amount`() {
        assertEquals("You can send 290 000 satoshis.", SendMath.availableLabel(290_000))
    }
}
