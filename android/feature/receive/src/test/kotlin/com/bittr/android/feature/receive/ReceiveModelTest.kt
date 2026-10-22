package com.bittr.android.feature.receive

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiveModelTest {

    private val address = "bcrt1qyrwfhwsea2pexmp8qeg3y703kn4ky4xxk5e50e"
    private val invoice = "lnbcrt1p42rve0dqqnp4"

    @Test
    fun `the default type follows the channel and the lightning address`() {
        assertEquals(ReceiveType.Onchain, ReceiveType.default(lightningAvailable = false, lightningAddress = "a@b"))
        assertEquals(ReceiveType.Lnurl, ReceiveType.default(lightningAvailable = true, lightningAddress = "a@b"))
        assertEquals(ReceiveType.BitcoinQr, ReceiveType.default(lightningAvailable = true, lightningAddress = null))
    }

    @Test
    fun `5000 sats is 0 point 00005 bitcoin, the amount receive_onchain asserts`() {
        assertEquals("0.00005", bitcoinAmount(5_000))
        assertEquals("1", bitcoinAmount(100_000_000))
        assertEquals("0.00000001", bitcoinAmount(1))
    }

    @Test
    fun `an on-chain address with no amount copies as the bare address`() {
        val display = receiveDisplay(ReceiveType.Onchain, address, null, null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.ADDRESS, display.title)
        assertEquals("bcrt 1qyr wfhw sea2 pexm p8qe g3y7 03kn 4ky4 xxk5 e50e", display.label)
        assertEquals(true, display.monospaced)
        assertEquals(address, display.copyText)
        assertEquals("BITCOIN:${address.uppercase()}", display.qrPayload)
    }

    @Test
    fun `an on-chain address with an amount becomes a BIP-21 URI`() {
        val display = receiveDisplay(ReceiveType.Onchain, address, null, null, amountSats = 5_000, description = "")

        assertEquals("bcrt 1qyr wfhw sea2 pexm p8qe g3y7 03kn 4ky4 xxk5 e50e?amount=0.00005", display.label)
        assertEquals("bitcoin:$address?amount=0.00005", display.copyText)
    }

    @Test
    fun `an invoice shows below the title, with a bolt`() {
        val display = receiveDisplay(ReceiveType.Lightning, null, invoice, null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.INVOICE, display.title)
        assertEquals("lnbc rt1p 42rv e0dq qnp4", display.label)
        assertEquals(true, display.monospaced)
        assertEquals(invoice, display.copyText)
        assertEquals(true, display.showBolt)
    }

    @Test
    fun `the Bitcoin QR's parameters follow one question mark, with or without an amount`() {
        val withAmount = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = 500, description = "")
        assertEquals("bitcoin:$address?amount=0.000005&lightning=$invoice", withAmount.copyText)

        val bare = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = null, description = "coffee")
        assertEquals("bitcoin:$address?label=coffee&lightning=$invoice", bare.copyText)

        val none = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = null, description = "")
        assertEquals("bitcoin:$address?lightning=$invoice", none.copyText)
    }

    @Test
    fun `the Bitcoin QR's label is percent-encoded, so it can't cut the invoice off or add parameters`() {
        val display = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = 500, description = "Order #12 & cake=x?")
        assertEquals("bitcoin:$address?amount=0.000005&label=Order%20%2312%20%26%20cake%3Dx%3F&lightning=$invoice", display.copyText)
        assertEquals("Caf%C3%A9%20%E2%98%95", percentEncoded("Café ☕"))
        assertEquals("a-b.c_d~e", percentEncoded("a-b.c_d~e"))
    }

    @Test
    fun `missing data is never encoded`() {
        val noAddress = receiveDisplay(ReceiveType.Onchain, null, null, null, amountSats = null, description = "")
        assertEquals(ReceiveStrings.UNAVAILABLE, noAddress.label)
        assertNull(noAddress.qrPayload)
        assertNull(noAddress.copyText)

        val noInvoice = receiveDisplay(ReceiveType.Lightning, null, null, null, amountSats = null, description = "")
        assertEquals(ReceiveStrings.INVOICE, noInvoice.title)
        assertNull(noInvoice.qrPayload)

        val half = receiveDisplay(ReceiveType.BitcoinQr, address, null, null, amountSats = null, description = "")
        assertEquals(ReceiveStrings.UNAVAILABLE, half.label)
        assertNull(half.qrPayload)
        assertNull(half.copyText)
    }

    @Test
    fun `an amount that can't be read gets no code`() {
        val display = receiveDisplay(ReceiveType.Onchain, address, null, null, amountSats = null, description = "", amountInvalid = true)
        assertEquals(ReceiveStrings.INVALID_AMOUNT, display.label)
        assertNull(display.qrPayload)
        assertNull(display.copyText)
    }

    @Test
    fun `a Bitcoin QR and a lightning address are not grouped`() {
        val bitcoinQr = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = null, description = "")
        assertEquals(false, bitcoinQr.monospaced)

        val lightningAddress = receiveDisplay(ReceiveType.Lnurl, null, null, lightningAddress = "tom@bittr.app", amountSats = null, description = "")
        assertEquals("tom@bittr.app", lightningAddress.label)
        assertEquals(false, lightningAddress.monospaced)
    }

    @Test
    fun `an unavailable lightning address has no QR`() {
        val display = receiveDisplay(ReceiveType.Lnurl, null, null, lightningAddress = null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.UNAVAILABLE, display.label)
        assertEquals(false, display.monospaced)
        assertNull(display.copyText)
        assertNull(display.qrPayload)
    }

    @Test
    fun `cards follow updateCards`() {
        assertEquals(ReceiveCards(false, true, true, false), ReceiveCards.forType(ReceiveType.Onchain, hasChannel = false))
        assertEquals(ReceiveCards(false, true, true, true), ReceiveCards.forType(ReceiveType.Onchain, hasChannel = true))
        assertEquals(ReceiveCards(true, false, false, true), ReceiveCards.forType(ReceiveType.Lnurl, hasChannel = true))
    }

    @Test
    fun `amounts parse per currency`() {
        assertEquals(5_000L, parseAmountSats("5000", ReceiveCurrency.Satoshis, null))
        assertNull("Satoshis take whole numbers only.", parseAmountSats("50.5", ReceiveCurrency.Satoshis, null))
        assertEquals(50_000L, parseAmountSats("0,0005", ReceiveCurrency.Bitcoin, null))
        // 5 EUR at 50 000 EUR per bitcoin is 0.0001 BTC.
        assertEquals(10_000L, parseAmountSats("5", ReceiveCurrency.Fiat, 50_000.0))
        assertNull("Fiat needs a price.", parseAmountSats("5", ReceiveCurrency.Fiat, null))
        assertNull(parseAmountSats("  ", ReceiveCurrency.Satoshis, null))
    }

    @Test
    fun `amounts are read as iOS reads them`() {
        // A lone separator before exactly three digits groups, unless it is the locale's decimal point.
        assertEquals(BigDecimal("1000"), parsedUserAmount("1,000", decimalSeparator = '.'))
        assertEquals(BigDecimal("1.000"), parsedUserAmount("1,000", decimalSeparator = ','))
        assertEquals(BigDecimal("1.5"), parsedUserAmount("1,5", decimalSeparator = '.'))
        // Both kinds: the last is the decimal point.
        assertEquals(BigDecimal("1234.56"), parsedUserAmount("1.234,56", decimalSeparator = '.'))
        assertEquals(BigDecimal("1234.56"), parsedUserAmount("1'234.56", decimalSeparator = '.'))
        // Satoshis are whole, so their separators only group.
        assertEquals(50_000L, parseAmountSats("50,000", ReceiveCurrency.Satoshis, null))
        assertEquals(1_000L, parseAmountSats("1.000", ReceiveCurrency.Satoshis, null))
        assertNull(parseAmountSats("50000.00", ReceiveCurrency.Satoshis, null))
        // A sign is a sign, and nothing else but digits and separators is a number.
        assertEquals(5L, parseAmountSats("+5", ReceiveCurrency.Satoshis, null))
        assertNull(parseAmountSats("-5", ReceiveCurrency.Satoshis, null))
        assertNull(parseAmountSats("1e-5", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("1E3", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("0.1.2", ReceiveCurrency.Bitcoin, null))
    }

    @Test
    fun `amounts stop at 21 million bitcoin instead of wrapping round`() {
        assertEquals(2_100_000_000_000_000L, parseAmountSats("21000000", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("21000000.00000001", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("100000000000", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("184467440737.09551617", ReceiveCurrency.Bitcoin, null))
        assertNull(parseAmountSats("18446744073709552", ReceiveCurrency.Satoshis, null))
        assertNull(parseAmountSats("99999999999999999999999", ReceiveCurrency.Fiat, 50_000.0))
    }

    @Test
    fun `Done refuses what is not a number, and leaves the rest to the label`() {
        assertTrue(isWellFormedAmount("", ReceiveCurrency.Satoshis))
        assertTrue(isWellFormedAmount("50,000", ReceiveCurrency.Satoshis))
        assertTrue("A number, if too large, which the label says.", isWellFormedAmount("100000000000", ReceiveCurrency.Bitcoin))
        assertFalse(isWellFormedAmount("-0.1", ReceiveCurrency.Bitcoin))
        assertFalse(isWellFormedAmount("1e-5", ReceiveCurrency.Bitcoin))
        assertFalse(isWellFormedAmount("50000.00", ReceiveCurrency.Satoshis))
    }
}
