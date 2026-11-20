package com.bittr.android.core.common.amount

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UserAmountTest {

    @Test
    fun `amounts are read as iOS reads them`() {
        // A lone separator before exactly three digits groups, unless it is the locale's decimal point.
        assertEquals(BigDecimal("1000"), parsedUserAmount("1,000", decimalSeparator = '.'))
        assertEquals(BigDecimal("1.000"), parsedUserAmount("1,000", decimalSeparator = ','))
        assertEquals(BigDecimal("1.5"), parsedUserAmount("1,5", decimalSeparator = '.'))
        // Both kinds: the last is the decimal point.
        assertEquals(BigDecimal("1234.56"), parsedUserAmount("1.234,56", decimalSeparator = '.'))
        assertEquals(BigDecimal("1234.56"), parsedUserAmount("1'234.56", decimalSeparator = '.'))
        // Without a fraction every separator groups, and must group well.
        assertEquals(BigDecimal("1000"), parsedUserAmount("1.000", allowingFraction = false, decimalSeparator = '.'))
        assertNull(parsedUserAmount("1.5", allowingFraction = false, decimalSeparator = '.'))
        assertNull(parsedUserAmount("1e3", decimalSeparator = '.'))
    }

    @Test
    fun `whole satoshis stop at 21 million bitcoin`() {
        assertEquals(MAXIMUM_SATOSHIS, wholeSatoshis(BigDecimal(MAXIMUM_SATOSHIS)))
        assertNull(wholeSatoshis(BigDecimal(MAXIMUM_SATOSHIS).add(BigDecimal.ONE)))
        assertNull(wholeSatoshis(BigDecimal("-1")))
        assertEquals(2L, wholeSatoshis(BigDecimal("1.5")))
    }
}
