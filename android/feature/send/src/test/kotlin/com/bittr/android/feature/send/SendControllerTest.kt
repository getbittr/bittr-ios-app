package com.bittr.android.feature.send

import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.common.destination.Destination
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SendControllerTest {

    private val address = "bcrt1qz2d3feqzlr3ggslt3ugs768utz8kmweah95qgv"

    private class FakeSource : SendSource {
        override val network: BitcoinNetwork = BitcoinNetwork.entries.first { it.bech32Hrp == "bcrt" }
        override val walletUpdates: Flow<Any> = emptyFlow()
        var sent: Triple<String, Long, Boolean>? = null

        override fun onchainReady() = true
        override suspend fun awaitOnchainReady() = true
        override fun onchainSpendableSats() = 294_424L
        var lightning = 0L
        override fun lightningSendableSats() = lightning
        override suspend fun feeEstimates() = FeeEstimates(fastest = 10.0, hour = 5.0, economy = 1.0)
        override suspend fun drainQuote(address: String?, satPerVb: Long) = DrainQuote(sendableSats = 290_000, feeSats = 2_000, vsize = 150)
        override suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long) = Result.success(141L)
        override suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long, sendAll: Boolean): Result<String> {
            sent = Triple(address, amountSats, sendAll)
            return Result.success("txid")
        }
        override suspend fun payInvoice(invoice: String, amountSats: Long?) = Result.success("hash")
        override suspend fun settledTransactionId(id: String) = id
        override fun fiatCurrency() = FiatCurrency("EUR", "€")
        override suspend fun fiatPricePerBitcoin() = 100_000.0
    }

    @Test
    fun `an on-chain payment the balance cannot cover offers Swap & Pay when Lightning can`() = runTest {
        val source = FakeSource().apply { lightning = 400_000 }
        val controller = SendController(source, this)
        val effects = mutableListOf<SendEffect>()
        val collecting = launch(UnconfinedTestDispatcher(testScheduler)) { controller.effects.toList(effects) }

        controller.onModeSelected(SendMode.Onchain)
        controller.onToChange(address)
        controller.onAmountChange("300000")
        controller.onNext()
        advanceUntilIdle()

        val alert = controller.state.value.alert!!
        assertEquals(SendStrings.INSUFFICIENT_FUNDS, alert.title)
        assertEquals(listOf("Cancel", "Swap & Pay"), alert.buttons.map { it.label })
        controller.onAlertButton(1)
        advanceUntilIdle()

        assertEquals(listOf<SendEffect>(SendEffect.SwapAndPayAddress(address, 300_000)), effects)
        collecting.cancel()
    }

    @Test
    fun `the currency alert lists Cancel, Bitcoin, Satoshis and the fiat symbol`() = runTest {
        val controller = SendController(FakeSource(), this)
        controller.onCurrencyButton()
        assertEquals(listOf("Cancel", "Bitcoin", "Satoshis", "€"), controller.state.value.alert!!.buttons.map { it.label })

        controller.onAlertButton(3)
        assertEquals("EUR", controller.state.value.currencyLabel)
    }

    @Test
    fun `a fiat amount to an address reaches the confirm page converted to sats`() = runTest {
        val controller = SendController(FakeSource(), this)
        controller.onModeSelected(SendMode.Onchain)
        controller.onToChange(address)
        controller.onCurrencyButton()
        controller.onAlertButton(3)
        controller.onAmountChange("5")
        controller.onNext()
        advanceUntilIdle()

        val confirm = assertNotNull(controller.state.value.confirm).let { controller.state.value.confirm!! }
        assertEquals(5_000L, confirm.amountSats)
        assertEquals("5.00 €", confirm.amountFiat)
        assertEquals(141L, confirm.vsize)
        assertEquals(false, confirm.sendingMaximum)
        assertEquals(FeeTier.Medium, confirm.selectedFee)
    }

    @Test
    fun `an amount at the drain sends the maximum`() = runTest {
        val controller = SendController(FakeSource(), this)
        controller.onModeSelected(SendMode.Onchain)
        controller.onToChange(address)
        controller.onAmountChange("290000")
        controller.onNext()
        advanceUntilIdle()

        val confirm = controller.state.value.confirm!!
        assertTrue(confirm.sendingMaximum)
        assertEquals(292_000L, confirm.drainTotalSats)
        assertEquals(150L, confirm.vsize)
    }

    @Test
    fun `confirming broadcasts and opens the new transaction`() = runTest {
        val source = FakeSource()
        val controller = SendController(source, this)
        val effects = mutableListOf<SendEffect>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { controller.effects.toList(effects) }

        controller.onModeSelected(SendMode.Onchain)
        controller.onToChange(address)
        controller.onAmountChange("5000")
        controller.onNext()
        advanceUntilIdle()
        controller.onConfirm()
        assertEquals("Send transaction", controller.state.value.alert!!.title)
        controller.onAlertButton(1)
        advanceUntilIdle()

        assertEquals(Triple(address, 5_000L, false), source.sent)
        assertEquals(listOf<SendEffect>(SendEffect.OpenTransaction("txid")), effects)
        assertEquals("", controller.state.value.toText)
        assertEquals(null, controller.state.value.confirm)
    }

    @Test
    fun `something that is not an address or invoice says so`() = runTest {
        val controller = SendController(FakeSource(), this)
        controller.onDestination(Destination.Unrecognised)
        assertEquals("No bitcoin address found.", controller.state.value.alert!!.title)
    }
}
