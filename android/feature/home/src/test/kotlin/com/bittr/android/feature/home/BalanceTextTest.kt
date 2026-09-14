package com.bittr.android.feature.home

import org.junit.Assert.assertEquals
import org.junit.Test

class BalanceTextTest {

    @Test
    fun `below one bitcoin the leading zeros are dimmed and sats appended`() {
        // The iOS capture `receive/01_home.png`.
        assertEquals(BalanceText(dimmed = "₿ 0.00 ", filled = "384 414 sats"), balanceText(384_414))
    }

    @Test
    fun `the dimmed part stops at the first significant digit`() {
        assertEquals(BalanceText(dimmed = "₿ 0.0", filled = "5 000 000 sats"), balanceText(5_000_000))
        assertEquals(BalanceText(dimmed = "₿ 0.00 000 00", filled = "1 sats"), balanceText(1))
    }

    @Test
    fun `a zero balance fills only the last digit`() {
        assertEquals(BalanceText(dimmed = "₿ 0.00 000 00", filled = "0 sats"), balanceText(0))
    }

    @Test
    fun `from one bitcoin up the whole figure is filled`() {
        assertEquals(BalanceText(dimmed = "", filled = "₿ 1.50 000 000"), balanceText(150_000_000))
    }
}
