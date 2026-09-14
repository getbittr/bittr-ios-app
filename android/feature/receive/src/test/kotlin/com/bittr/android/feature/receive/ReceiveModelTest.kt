package com.bittr.android.feature.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
        val display = receiveDisplay(ReceiveType.Onchain, address, "", null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.ADDRESS, display.title)
        assertEquals(address, display.addressLabel)
        assertEquals("", display.lowerLabel)
        assertEquals(address, display.copyText)
        assertEquals("BITCOIN:${address.uppercase()}", display.qrPayload)
    }

    @Test
    fun `an on-chain address with an amount becomes a BIP-21 URI`() {
        val display = receiveDisplay(ReceiveType.Onchain, address, "", null, amountSats = 5_000, description = "")

        assertEquals("$address?amount=0.00005", display.addressLabel)
        assertEquals("bitcoin:$address?amount=0.00005", display.copyText)
    }

    @Test
    fun `an invoice shows below the title, with a bolt`() {
        val display = receiveDisplay(ReceiveType.Lightning, "", invoice, null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.INVOICE, display.title)
        assertEquals(invoice, display.lowerLabel)
        assertEquals(invoice, display.copyText)
        assertEquals(true, display.showBolt)
    }

    @Test
    fun `the Bitcoin QR is built as iOS builds it, including with no amount`() {
        val withAmount = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = 500, description = "")
        assertEquals("bitcoin:$address?amount=0.000005&lightning=$invoice", withAmount.copyText)

        val bare = receiveDisplay(ReceiveType.BitcoinQr, address, invoice, null, amountSats = null, description = "coffee")
        assertEquals("bitcoin:$address&label=coffee&lightning=$invoice", bare.copyText)
    }

    @Test
    fun `an unavailable lightning address has no QR`() {
        val display = receiveDisplay(ReceiveType.Lnurl, "", "", lightningAddress = null, amountSats = null, description = "")

        assertEquals(ReceiveStrings.UNAVAILABLE, display.addressLabel)
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
}
