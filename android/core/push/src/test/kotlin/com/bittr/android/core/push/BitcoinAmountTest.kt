package com.bittr.android.core.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The BTC-string-to-msats conversion, against `String.parsedNumber()` +
 * `CGFloat.inSatoshis()` as iOS implements them. Every expectation here was read off the
 * Swift, not chosen — divergence in this function is money displayed or paid wrongly on one
 * platform only.
 */
class BitcoinAmountTest {

    @Test
    fun `one satoshi survives eight decimal places`() {
        assertEquals(1L, BitcoinAmount.btcStringToSatoshis("0.00000001"))
        assertEquals(1_000L, BitcoinAmount.btcStringToMsats("0.00000001"))
    }

    @Test
    fun `eight decimal places convert exactly, with no binary rounding error`() {
        // The case BigDecimal exists for. 0.12345678 * 1e8 in binary floating point is
        // 12345677.999999998, which truncates to one satoshi short.
        assertEquals(12_345_678L, BitcoinAmount.btcStringToSatoshis("0.12345678"))
    }

    @Test
    fun `a comma is a decimal separator too`() {
        // Parity with String.parsedNumber(), which accepts both. The backend should still
        // emit '.' — this is about not dropping a payload iOS would have read.
        assertEquals(
            BitcoinAmount.btcStringToMsats("0.001"),
            BitcoinAmount.btcStringToMsats("0,001"),
        )
        assertEquals(100_000_000L, BitcoinAmount.btcStringToMsats("0,001"))
    }

    @Test
    fun `half a satoshi rounds away from zero, matching Swift's rounded()`() {
        assertEquals(1L, BitcoinAmount.btcStringToSatoshis("0.000000005"))
        assertEquals(0L, BitcoinAmount.btcStringToSatoshis("0.000000004"))
    }

    @Test
    fun `a leading sign is accepted and a negative amount is zero`() {
        assertEquals(50_000_000L, BitcoinAmount.btcStringToSatoshis("+0.5"))
        // inSatoshis() guards `self > 0`, so iOS pays out nothing rather than a negative.
        assertEquals(0L, BitcoinAmount.btcStringToSatoshis("-0.5"))
    }

    @Test
    fun `surrounding whitespace is trimmed`() {
        assertEquals(50_000_000L, BitcoinAmount.btcStringToSatoshis("  0.5\n"))
    }

    @Test
    fun `unreadable input is zero rather than an exception`() {
        // toNumber() returns 0 for anything parsedNumber() rejects (String.swift:151-154).
        // A push whose amount cannot be read must not take the FCM service down with it.
        assertEquals(0L, BitcoinAmount.btcStringToMsats(null))
        assertEquals(0L, BitcoinAmount.btcStringToMsats(""))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("   "))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("abc"))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("0x1f"))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("1.2e-3"))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("."))
    }

    @Test
    fun `two separators are rejected, so a grouped number is not misread`() {
        // "1.000,5" is one thousand and a half in several locales and one-point-something
        // in others. iOS refuses to guess; guessing here would be a 1000x payout error.
        assertNull(BitcoinAmount.parsedNumber("1.000,5"))
        assertEquals(0L, BitcoinAmount.btcStringToMsats("1.000,5"))
    }

    @Test
    fun `amounts above the supply clamp instead of overflowing`() {
        assertEquals(BitcoinAmount.MAXIMUM_SATOSHIS, BitcoinAmount.btcStringToSatoshis("22000000"))
        assertEquals(
            BitcoinAmount.MAXIMUM_SATOSHIS * 1_000L,
            BitcoinAmount.btcStringToMsats("22000000"),
        )
    }

    @Test
    fun `the whole msat domain fits in a Long and not in an Int`() {
        // BIT-30 §2(a). Int caps at 2,147,483,647 msats ~ 0.0215 BTC; the clamped ceiling
        // here is nine orders of magnitude past it.
        val ceiling = BitcoinAmount.btcStringToMsats("21000000")
        assertEquals(2_100_000_000_000_000_000L, ceiling)

        // The boundary an Int would have failed at, in the middle of ordinary amounts.
        val justOverIntMax = BitcoinAmount.btcStringToMsats("0.03")
        assertEquals(3_000_000_000L, justOverIntMax)
        assert(justOverIntMax > Int.MAX_VALUE.toLong())
    }
}
