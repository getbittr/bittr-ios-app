package com.bittr.android.feature.send

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
