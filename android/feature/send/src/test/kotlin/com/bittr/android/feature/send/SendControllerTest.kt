package com.bittr.android.feature.send

import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.lnurl.LnurlSource
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

    private class FakeSource(
        private val lightningBalance: Long = 0L,
        private val responses: Map<String, String> = emptyMap(),
    ) : SendSource {
        override val network: BitcoinNetwork = BitcoinNetwork.entries.first { it.bech32Hrp == "bcrt" }
        override val walletUpdates: Flow<Any> = emptyFlow()
        var sent: Triple<String, Long, Boolean>? = null
        val fetched = mutableListOf<String>()
        val notes = mutableMapOf<String, String>()

        override suspend fun lnurlGet(url: String): Result<String> {
            fetched += url
            return responses[url]?.let { Result.success(it) } ?: Result.failure(IllegalStateException("404"))
        }
        override suspend fun createInvoice(amountMsat: Long, description: String) = Result.success("lnbcrt-withdraw-$amountMsat")
        override fun storeTransactionNote(transactionId: String, note: String) {
            notes[transactionId] = note
        }

        override fun onchainReady() = true
        override suspend fun awaitOnchainReady() = true
        override fun onchainSpendableSats() = 294_424L
        var lightning = lightningBalance
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

    private val invoice150Sats =
        "lnbcrt1500n1qqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0jqgfzyvjz2f389q5" +
            "j52ev95hz7vp3xgengdfkxuurjw3m8s7nu06qg9pyx3z9ger5sj22fdxy6nj0dnuknp"

    private val lightningAddress = "e2ebittr@pay.example.com"
    private val wellKnown = "https://pay.example.com/.well-known/lnurlp/e2ebittr"
    private val callback = "https://pay.example.com/lnurlp/cb/e2ebittr"

    private fun payRequest(min: Long, max: Long) =
        """{"tag":"payRequest","callback":"$callback","minSendable":$min,"maxSendable":$max,"metadata":"[[\"text/plain\",\"Pay to e2ebittr\"]]"}"""

    @Test
    fun `a lightning address with a range takes the amount, then confirms the address and keeps the note`() = runTest {
        val source = FakeSource(
            lightningBalance = 10_000,
            responses = mapOf(
                wellKnown to payRequest(min = 1_000, max = 1_000_000_000),
                "$callback?amount=150000" to """{"pr":"$invoice150Sats","routes":[]}""",
            ),
        )
        val controller = SendController(source, this)
        controller.onToChange(lightningAddress)
        val focusAmount = controller.onToReturn()
        advanceUntilIdle()

        // send_lightning.yaml: the spinner goes, then "1500"-style typing lands in the amount field.
        assertEquals(false, focusAmount)
        assertEquals(false, controller.state.value.lnurlLoading)
        assertEquals(1, controller.state.value.focusAmountRequests)
        assertEquals(null, controller.state.value.alert)

        controller.onAmountChange("150")
        controller.onNext()
        advanceUntilIdle()

        val confirm = controller.state.value.confirm!!
        assertEquals(lightningAddress, confirm.displayedAddress)
        assertEquals(invoice150Sats, confirm.addressOrInvoice)
        assertEquals(150L, confirm.amountSats)

        controller.onConfirm()
        advanceUntilIdle()
        assertEquals("Pay to e2ebittr", source.notes["hash"])
    }

    /** The in-app browser's hand-off: a first-party page gets LNURL-auth, and a refusal for pay. */
    @Test
    fun `a first-party page may start a login but not a payment`() = runTest {
        val web = LnurlSource.FirstPartyWeb(origin = "https://getbittr.com", pageTitle = "Support")
        val source = FakeSource(lightningBalance = 10_000, responses = mapOf(wellKnown to payRequest(min = 1_000, max = 1_000_000_000)))
        val controller = SendController(source, this)

        controller.onLnurl(lightningAddress, web)
        advanceUntilIdle()
        val refused = controller.state.value.alert!!
        assertTrue(refused.message, refused.message.contains("Payments can only be started"))
        assertEquals(null, controller.state.value.confirm)
        assertEquals(0, controller.state.value.focusAmountRequests)
        controller.onAlertButton(0)

        val k1 = "a".repeat(64)
        controller.onLnurl("https://getbittr.com/lnurl/auth?tag=login&k1=$k1&action=login", web)
        advanceUntilIdle()
        val login = controller.state.value.alert!!
        assertEquals(2, login.buttons.size)
        assertTrue(login.message, login.message.contains("getbittr.com"))
    }

    @Test
    fun `an amount outside the range says between what`() = runTest {
        val source = FakeSource(lightningBalance = 10_000, responses = mapOf(wellKnown to payRequest(min = 1_000_000, max = 2_000_000)))
        val controller = SendController(source, this)
        controller.onToChange(lightningAddress)
        controller.onToReturn()
        advanceUntilIdle()
        controller.onAmountChange("5")
        controller.onNext()
        advanceUntilIdle()

        assertEquals("Amount must be between 1000 and 2000 satoshis.", controller.state.value.alert!!.message)
        assertEquals(listOf(wellKnown), source.fetched)
    }

    @Test
    fun `a fixed amount is confirmed in an alert first, and a mismatched invoice is refused`() = runTest {
        val source = FakeSource(
            lightningBalance = 10_000,
            responses = mapOf(
                wellKnown to payRequest(min = 200_000, max = 200_000),
                "$callback?amount=200000" to """{"pr":"$invoice150Sats"}""",
            ),
        )
        val controller = SendController(source, this)
        controller.onToChange(lightningAddress)
        controller.onToReturn()
        advanceUntilIdle()

        val ask = controller.state.value.alert!!
        assertEquals("Are you sure you'd like to pay 200 satoshis?", ask.message)
        controller.onAlertButton(1)
        advanceUntilIdle()

        // The service returned a 150-sat invoice for a 200-sat request.
        assertTrue(controller.state.value.alert!!.message.contains("doesn't match"))
        assertEquals(null, controller.state.value.confirm)
    }

    @Test
    fun `a withdraw with a range asks for the amount and re-asks when it is out of range`() = runTest {
        val service = "https://lnbits.example.com/withdraw"
        val cb = "https://lnbits.example.com/withdraw/cb"
        val source = FakeSource(
            responses = mapOf(
                service to """{"tag":"withdrawRequest","callback":"$cb","k1":"abc","minWithdrawable":1000,"maxWithdrawable":50000}""",
                "$cb?k1=abc&pr=lnbcrt-withdraw-20000" to """{"status":"OK"}""",
            ),
        )
        val controller = SendController(source, this)
        controller.onDestination(
            Destination.Lnurl(raw = "lnurl1", target = com.bittr.android.core.common.destination.LnurlTarget.Service(service)),
        )
        advanceUntilIdle()

        val ask = controller.state.value.alert!!
        assertEquals("alert.withdrawRequest", ask.tag)
        assertNotNull(ask.field)
        controller.onAlertText(1, "999")
        assertTrue(controller.state.value.alert!!.message.startsWith("Please enter an amount within the range shown."))

        controller.onAlertText(1, "20")
        advanceUntilIdle()
        assertEquals(null, controller.state.value.alert)
        assertEquals("$cb?k1=abc&pr=lnbcrt-withdraw-20000", source.fetched.last())
    }

    @Test
    fun `an unsupported tag and a private host are refused without paying`() = runTest {
        val source = FakeSource(responses = mapOf(wellKnown to """{"tag":"channelRequest"}"""))
        val controller = SendController(source, this)
        controller.onToChange(lightningAddress)
        controller.onToReturn()
        advanceUntilIdle()
        assertEquals("We currently only support lightning pay and withdraw requests.", controller.state.value.alert!!.message)

        controller.onAlertButton(0)
        controller.onDestination(
            Destination.Lnurl(raw = "lnurl1", target = com.bittr.android.core.common.destination.LnurlTarget.Service("https://192.168.1.10/pay")),
        )
        advanceUntilIdle()
        assertEquals("LNURL status", controller.state.value.alert!!.title)
        assertEquals(listOf(wellKnown), source.fetched)
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
