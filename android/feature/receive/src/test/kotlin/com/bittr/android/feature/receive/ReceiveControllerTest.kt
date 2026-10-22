package com.bittr.android.feature.receive

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ReceiveControllerTest {

    private class FakeSource(
        var channel: Boolean = false,
        var address: String? = null,
        verified: Boolean = true,
        var invoicesWork: Boolean = true,
        val pool: ArrayDeque<String> = ArrayDeque(listOf("addr-1", "addr-2")),
    ) : ReceiveSource {
        var current: String? = pool.removeFirst()
        val invoiceAmounts = mutableListOf<Long?>()
        override val addressesVerified = MutableStateFlow(verified)
        override fun stopWaitingForAddresses() {
            addressesVerified.value = true
        }
        override fun lightningAvailable() = channel
        override fun lightningAddress() = address
        override fun currentOnchainAddress() = current
        override fun nextOnchainAddress(): String? = pool.removeFirstOrNull()?.also { current = it }
        override suspend fun zeroAmountInvoice(description: String) = "lnbcrt-zero".takeIf { invoicesWork }.also { invoiceAmounts += null }
        override suspend fun invoice(amountSats: Long, description: String) = "lnbcrt-$amountSats".takeIf { invoicesWork }.also { invoiceAmounts += amountSats }
        override fun fiatCurrency() = FiatCurrency("EUR", "€")
        override suspend fun fiatPricePerBitcoin() = 50_000.0
    }

    // The test scope itself, not `backgroundScope`: `advanceUntilIdle()` does not run
    // background work, so a controller launching there would never finish a load.
    private fun TestScope.controller(source: FakeSource) = ReceiveController(source, this)

    @Test
    fun `amounts drop spaces, keep satoshis whole, and refuse a minus or a second separator`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()

        controller.onAmountChange("1 500")
        assertEquals("1500", controller.state.value.amountText)
        // A separator that can't be thousands is refused rather than dropped, which would have asked for 100 times as much.
        for (malformed in listOf("50000.00", "5,00", "15-")) {
            controller.onAmountChange(malformed)
            controller.onDone()
            assertEquals(malformed, ReceiveStrings.ENTER_VALID_AMOUNT, controller.state.value.alert?.message)
            controller.onAlertButton(0)
        }

        controller.onCurrencyButton()
        controller.onAlertButton(3) // Bitcoin
        controller.onAmountChange(" 0.000 01 ")
        assertEquals("0.00001", controller.state.value.amountText)

        for (malformed in listOf("-0.1", "0.1.2", "0,1.2", "1,,2")) {
            controller.onAmountChange(malformed)
            controller.onDone()
            assertEquals(malformed, ReceiveStrings.ENTER_VALID_AMOUNT, controller.state.value.alert?.message)
            controller.onAlertButton(0)
        }
        advanceUntilIdle()
    }

    @Test
    fun `with no channel it opens on the address, and More is hidden`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()

        val state = controller.state.value
        assertEquals(ReceiveType.Onchain, state.type)
        assertFalse(state.loading)
        assertEquals("addr-1", state.display?.copyText)
        assertFalse(state.cards.more)
    }

    @Test
    fun `it waits for the address pool, and gives up after eight seconds`() = runTest {
        val source = FakeSource(verified = false)
        val controller = controller(source)
        controller.start()

        advanceTimeBy(7_000)
        assertTrue("Still verifying, so still loading.", controller.state.value.loading)

        advanceTimeBy(1_500)
        advanceUntilIdle()
        assertFalse(controller.state.value.loading)
        assertEquals("addr-1", controller.state.value.display?.copyText)
        assertTrue("Gave up for good, as iOS does.", source.addressesVerified.value)
    }

    @Test
    fun `an amount typed during the wait is not in the code, and Copy waits for it`() = runTest {
        val source = FakeSource(verified = false)
        val controller = controller(source)
        controller.start()
        controller.onEdit()
        controller.onAmountChange("5000")

        advanceTimeBy(9_000)
        advanceUntilIdle()
        assertEquals("Made from the fields as they were when it was asked for.", "addr-1", controller.state.value.display?.copyText)
        assertNull("The field has an amount the code does not.", controller.onCopy())

        controller.onEditingEnded()
        advanceUntilIdle()
        assertEquals("bitcoin:addr-1?amount=0.00005", controller.onCopy())
    }

    @Test
    fun `closing Add amount straight after an edit makes one invoice, without the amount`() = runTest {
        val source = FakeSource(channel = true)
        // Eager, as the app's main dispatcher is, so a load starts the moment it is asked for.
        val controller = ReceiveController(source, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        controller.start()
        controller.onMore()
        controller.onAlertButton(3)
        advanceUntilIdle()
        val made = source.invoiceAmounts.size

        controller.onEdit()
        controller.onAmountChange("5000")
        // As the screen does it: the stack closes, then the keyboard goes.
        controller.onEdit()
        controller.onEditingEnded()
        advanceUntilIdle()

        assertEquals(made, source.invoiceAmounts.size)
        assertEquals("lnbcrt-zero", controller.state.value.display?.copyText)
    }

    @Test
    fun `picking Invoice from More creates an invoice`() = runTest {
        val controller = controller(FakeSource(channel = true))
        controller.start()
        advanceUntilIdle()

        controller.onMore()
        assertEquals(5, controller.state.value.alert?.buttons?.size)
        controller.onAlertButton(3)
        advanceUntilIdle()

        assertEquals(ReceiveType.Lightning, controller.state.value.type)
        assertEquals("lnbcrt-zero", controller.state.value.display?.copyText)
        assertNull(controller.state.value.alert)
    }

    @Test
    fun `renewing walks the pool, then says none are left and keeps the address`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()

        controller.onRefresh()
        controller.onAlertButton(1)
        advanceUntilIdle()
        assertEquals("addr-2", controller.state.value.display?.copyText)
        assertNull(controller.state.value.alert)

        controller.onRefresh()
        controller.onAlertButton(1)
        advanceUntilIdle()
        assertEquals("addr-2", controller.state.value.display?.copyText)
        assertEquals(ReceiveStrings.NO_ADDRESS_AVAILABLE, controller.state.value.alert?.message)
        assertEquals(1, controller.state.value.alert?.buttons?.size)
    }

    @Test
    fun `an amount in euros reaches the invoice as satoshis`() = runTest {
        val source = FakeSource(channel = true)
        val controller = controller(source)
        controller.start()
        advanceUntilIdle()

        controller.onEdit()
        controller.onCurrencyButton()
        assertEquals("€", controller.state.value.alert?.buttons?.get(1)?.label)
        controller.onAlertButton(1)
        assertEquals("EUR", controller.state.value.currencyLabel)

        controller.onAmountChange("5")
        controller.onDone()
        advanceUntilIdle()

        assertEquals(10_000L, source.invoiceAmounts.last())
        assertTrue(controller.state.value.display?.copyText.orEmpty().contains("amount=0.0001"))
    }

    @Test
    fun `closing Add amount makes a code with an amount again without it`() = runTest {
        val source = FakeSource(channel = true)
        val controller = controller(source)
        controller.start()
        advanceUntilIdle()
        controller.onMore()
        controller.onAlertButton(3)
        advanceUntilIdle()

        controller.onEdit()
        controller.onAmountChange("5000")
        controller.onDone()
        advanceUntilIdle()
        assertEquals(5_000L, source.invoiceAmounts.last())

        controller.onEdit()
        advanceUntilIdle()
        assertFalse(controller.state.value.amountOpen)
        assertEquals("lnbcrt-zero", controller.state.value.display?.copyText)
    }

    @Test
    fun `an amount left by tapping elsewhere is in the code, and so is a change of currency`() = runTest {
        val source = FakeSource(channel = true)
        val controller = controller(source)
        controller.start()
        advanceUntilIdle()
        controller.onMore()
        controller.onAlertButton(3)
        advanceUntilIdle()

        controller.onEdit()
        controller.onAmountChange("1000")
        controller.onEditingEnded()
        advanceUntilIdle()
        assertEquals(1_000L, source.invoiceAmounts.last())

        controller.onCurrencyButton()
        controller.onAlertButton(3)
        advanceUntilIdle()
        assertEquals(ReceiveCurrency.Bitcoin, controller.state.value.currency)
        assertEquals(100_000_000_000L, source.invoiceAmounts.last())

        val made = source.invoiceAmounts.size
        controller.onEditingEnded()
        advanceUntilIdle()
        assertEquals("Nothing changed, so no new invoice.", made, source.invoiceAmounts.size)
    }

    @Test
    fun `an amount that can't be read shows Invalid amount, with no code and no invoice`() = runTest {
        val source = FakeSource(channel = true)
        val controller = controller(source)
        controller.start()
        advanceUntilIdle()
        controller.onMore()
        controller.onAlertButton(3)
        advanceUntilIdle()
        val made = source.invoiceAmounts.size

        controller.onEdit()
        controller.onAmountChange("50.00.1")
        controller.onEditingEnded()
        advanceUntilIdle()

        assertEquals(ReceiveStrings.INVALID_AMOUNT, controller.state.value.display?.label)
        assertNull(controller.state.value.display?.qrPayload)
        assertEquals(made, source.invoiceAmounts.size)
    }

    @Test
    fun `an invoice that can't be made shows Unavailable, with nothing to copy`() = runTest {
        val source = FakeSource(channel = true, invoicesWork = false)
        val controller = controller(source)
        controller.start()
        advanceUntilIdle()

        assertEquals(ReceiveType.BitcoinQr, controller.state.value.type)
        assertEquals(ReceiveStrings.UNAVAILABLE, controller.state.value.display?.label)
        assertNull(controller.onCopy())
    }

    @Test
    fun `nothing is copied or shared while a new code loads`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()
        assertEquals("addr-1", controller.onShare())

        controller.show(ReceiveType.Onchain)
        assertTrue(controller.state.value.loading)
        assertNull(controller.onCopy())
        assertNull(controller.onShare())
    }

    @Test
    fun `the description stops at 100 bytes`() = runTest {
        val controller = controller(FakeSource())
        controller.onDescriptionChange("a".repeat(100))
        controller.onDescriptionChange("a".repeat(101))
        assertEquals(100, controller.state.value.descriptionText.length)

        controller.onDescriptionChange("😀".repeat(25))
        controller.onDescriptionChange("😀".repeat(26))
        assertEquals("😀".repeat(25), controller.state.value.descriptionText)
    }

    @Test
    fun `closing Add amount leaves a code without an amount as it is`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()
        val shown = controller.state.value.display

        controller.onEdit()
        controller.onAmountChange("5000")
        controller.onEdit()
        advanceUntilIdle()

        assertEquals("", controller.state.value.amountText)
        assertFalse(controller.state.value.loading)
        assertTrue("Never made again, so the same display.", shown === controller.state.value.display)
    }

    @Test
    fun `copy raises the Copied alert with the text`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()

        assertEquals("addr-1", controller.onCopy())
        assertEquals(ReceiveStrings.COPIED, controller.state.value.alert?.title)
        assertEquals("addr-1", controller.state.value.alert?.message)
    }
}
