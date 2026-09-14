package com.bittr.android.feature.receive

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
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
        val pool: ArrayDeque<String> = ArrayDeque(listOf("addr-1", "addr-2")),
    ) : ReceiveSource {
        var current: String? = pool.removeFirst()
        val invoiceAmounts = mutableListOf<Long?>()
        override val addressesVerified = MutableStateFlow(verified)
        override fun lightningAvailable() = channel
        override fun lightningAddress() = address
        override fun currentOnchainAddress() = current
        override fun nextOnchainAddress(): String? = pool.removeFirstOrNull()?.also { current = it }
        override suspend fun zeroAmountInvoice(description: String) = "lnbcrt-zero".also { invoiceAmounts += null }
        override suspend fun invoice(amountSats: Long, description: String) = "lnbcrt-$amountSats".also { invoiceAmounts += amountSats }
        override fun fiatCurrency() = FiatCurrency("EUR", "€")
        override suspend fun fiatPricePerBitcoin() = 50_000.0
    }

    // The test scope itself, not `backgroundScope`: `advanceUntilIdle()` does not run
    // background work, so a controller launching there would never finish a load.
    private fun TestScope.controller(source: FakeSource) = ReceiveController(source, this)

    @Test
    fun `with no channel it opens on the address, and More is hidden`() = runTest {
        val controller = controller(FakeSource())
        controller.start()
        advanceUntilIdle()

        val state = controller.state.value
        assertEquals(ReceiveType.Onchain, state.type)
        assertFalse(state.loading)
        assertEquals("addr-1", state.display?.addressLabel)
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
        assertEquals("addr-1", controller.state.value.display?.addressLabel)
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
        assertEquals("lnbcrt-zero", controller.state.value.display?.lowerLabel)
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
        assertEquals("addr-2", controller.state.value.display?.addressLabel)
        assertNull(controller.state.value.alert)

        controller.onRefresh()
        controller.onAlertButton(1)
        advanceUntilIdle()
        assertEquals("addr-2", controller.state.value.display?.addressLabel)
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
        assertTrue(controller.state.value.display!!.copyText.contains("amount=0.0001"))
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
