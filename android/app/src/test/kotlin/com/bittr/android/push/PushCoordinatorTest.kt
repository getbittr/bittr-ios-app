package com.bittr.android.push

import com.bittr.android.core.common.TestID
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PushCoordinatorTest {

    private val walletState = MutableStateFlow(WalletState.Locked)
    private val overview = MutableStateFlow(WalletOverview(hasNode = true))
    private var now = 1_000_000L
    private var depositCode: String? = null
    private var connected = true
    private val requests = mutableListOf<HttpRequest>()
    private var reply = HttpResponse(200, """{"success":false,"error":"no_held_htlc"}""")

    private val signer = object : BittrRequestSigner {
        override suspend fun pubkey(): String? = "02pub"
        override suspend fun sign(message: String): String? = "sig:$message"
    }

    private val node = object : PushNode {
        override fun isConnectedToBittr() = connected
        override suspend fun reconnectToBittr() { connected = true }
        override fun invoice(amountMsat: Long, description: String, expirySecs: Int) = "lnbcrt$amountMsat"
    }

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest): HttpResponse {
            requests += request
            return reply
        }
    }

    private val answered = mutableListOf<PushEnvelope.LightningAddress>()
    private var answerSucceeds = true

    private var swapScreenOpen = false
    private val swapPushesOpened = mutableListOf<PushEnvelope.Swap>()
    private val swapHandler = object : SwapPushHandler {
        override fun swapScreenOpen() = swapScreenOpen
        override suspend fun onSwapPush(push: PushEnvelope.Swap) {
            swapPushesOpened += push
        }
    }

    @Test
    fun `a swap push while locked asks to sign in, then opens the swap status after the first sync`() {
        coordinator.receive(PushEnvelope.Swap("hashed-id", "transaction.claimed"))
        val signIn = state.alert!!
        assertEquals(PushStrings.SWAP_STATUS_UPDATE, signIn.title)
        assertEquals(PushStrings.PLEASE_SIGN_IN, signIn.message)
        coordinator.onAlertButton(signIn.buttons.single())
        assertTrue(swapPushesOpened.isEmpty())

        walletState.value = WalletState.Ready
        assertEquals(TestID.Loading.syncingWallet, state.loading?.testTag)
        overview.value = overview.value.copy(hasSynced = true)
        assertEquals(1, swapPushesOpened.size)
        assertNull(state.loading)
    }

    @Test
    fun `a swap push is ignored while a swap screen is open`() {
        unlockAndSync()
        swapScreenOpen = true
        coordinator.receive(PushEnvelope.Swap("hashed-id", "invoice.settled"))
        assertTrue(swapPushesOpened.isEmpty())
        assertEquals(PushUiState(), state)
    }

    @Test
    fun `a swap push without a swap id does nothing`() {
        unlockAndSync()
        coordinator.receive(PushEnvelope.Swap("", "invoice.settled"))
        assertTrue(swapPushesOpened.isEmpty())
    }

    // Unconfined and no pauses: each push is handled inside `receive`.
    private val coordinator = PushCoordinator(
        scope = CoroutineScope(Dispatchers.Unconfined),
        io = Dispatchers.Unconfined,
        walletState = walletState,
        overview = overview,
        signer = signer,
        node = node,
        http = http,
        environment = BittrEnvironment.DEVELOPMENT,
        depositCodes = DepositCodeSource { depositCode },
        swapHandler = swapHandler,
        lnurlHandler = LnurlPushHandler { push ->
            answered += push
            answerSucceeds
        },
        payoutSwap = null,
        clockMillis = { now },
        pause = {},
        log = {},
    )

    private val addressPush = PushEnvelope.LightningAddress(
        amountMsats = 21_000_000,
        metadata = "[[\"text/plain\",\"Pay to e2ebittr\"]]",
        timeSent = "1",
        username = "e2ebittr",
        endpoint = "https://pay.example.com/answer",
    )

    @Test
    fun `a lightning-address push while locked asks to sign in, then answers after the first sync`() {
        coordinator.receive(addressPush)
        val signIn = state.alert!!
        assertEquals(TestID.Alert.paymentRequest, signIn.testTag)
        assertEquals("Someone wants to pay you 21 000 satoshis! Please sign in to accept the payment.", signIn.message)
        coordinator.onAlertButton(signIn.buttons.single())
        assertTrue(answered.isEmpty())

        unlockAndSync()
        assertEquals(listOf(addressPush), answered)
        assertEquals(PushUiState(), state)
    }

    @Test
    fun `a lightning-address push while open asks, and a failed answer says so`() {
        unlockAndSync()
        answerSucceeds = false
        coordinator.receive(addressPush)
        val ask = state.alert!!
        assertEquals(listOf(PushStrings.CANCEL, PushStrings.HANDLE_NOW), ask.buttons.map { it.label })

        coordinator.onAlertButton(ask.buttons[1])
        assertEquals(listOf(addressPush), answered)
        assertEquals(TestID.Alert.paymentRequestFailed, state.alert?.testTag)
        assertNull(state.loading)
    }

    @Test
    fun `cancelling a lightning-address push forgets it`() {
        unlockAndSync()
        coordinator.receive(addressPush)
        coordinator.onAlertButton(state.alert!!.buttons[0])
        walletState.value = WalletState.Locked
        unlockAndSync()
        assertTrue(answered.isEmpty())
    }

    private val state get() = coordinator.uiState.value

    private fun unlockAndSync() {
        walletState.value = WalletState.Ready
        overview.value = overview.value.copy(hasSynced = true)
    }

    @Test
    fun `an information push opens the Question card with a lowercased title`() {
        coordinator.receive(PushEnvelope.Information("Bittr update", "This is a test."))
        assertEquals(PushQuestion("bittr update", "This is a test."), state.question)

        coordinator.closeQuestion()
        now += 11_000
        coordinator.receive(PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NO_DISCRIMINATOR))
        assertEquals(PushQuestion("oops!", PushStrings.BITTR_NOTIFICATION_FAIL), state.question)

        coordinator.closeQuestion()
        now += 11_000
        coordinator.receive(PushEnvelope.HtlcExpired(null, null, null))
        assertEquals(PushQuestion("payment expired", PushStrings.HTLC_EXPIRED_BODY), state.question)
    }

    @Test
    fun `a push within ten seconds of the last one is ignored, whatever its id`() {
        coordinator.receive(PushEnvelope.Information("one", "1"), id = "a")
        coordinator.closeQuestion()
        now += 9_000
        coordinator.receive(PushEnvelope.Information("two", "2"), id = "b")
        assertNull(state.question)

        now += 2_000
        coordinator.receive(PushEnvelope.Information("three", "3"), id = "c")
        assertEquals("three", state.question?.title)

        now += 20_000
        coordinator.closeQuestion()
        coordinator.receive(PushEnvelope.Information("again", "c"), id = "c")
        assertNull("the same id is never handled twice in a row", state.question)
    }

    @Test
    fun `an HTLC push while locked waits silently, syncs after unlock, then completes without the alert`() {
        coordinator.receive(PushEnvelope.HtlcIncoming)
        assertEquals(PushUiState(), state)

        walletState.value = WalletState.Ready
        assertEquals(TestID.Loading.syncingWallet, state.loading?.testTag)
        assertNull(state.alert)

        overview.value = overview.value.copy(hasSynced = true)
        // No bittr account on this wallet: the deferred path ends on the failure alert.
        assertNull(state.loading)
        val alert = state.alert!!
        assertEquals(TestID.Alert.incomingPayment, alert.testTag)
        assertEquals(PushStrings.BITTR_PAYOUT_FAIL, alert.message)
        assertEquals(listOf(PushStrings.CLOSE), alert.buttons.map { it.label })
        assertTrue(requests.isEmpty())

        coordinator.onAlertButton(alert.buttons[0])
        assertEquals(PushUiState(), state)
    }

    @Test
    fun `an HTLC push while open asks first, then signs and posts htlc ready`() {
        unlockAndSync()
        depositCode = "DEP1"
        coordinator.receive(PushEnvelope.HtlcIncoming)
        val ask = state.alert!!
        assertEquals(TestID.Alert.incomingPayment, ask.testTag)
        assertEquals(PushStrings.NEW_BITTR_PAYMENT, ask.message)

        coordinator.onAlertButton(ask.buttons.single())
        val request = requests.single()
        assertTrue(request.url.endsWith("/htlc-interceptor/ready"))
        val timestamp = now / 1_000
        assertTrue(request.jsonBody!!, "\"signature\":\"sig:htlc_ready:DEP1:$timestamp\"" in request.jsonBody!!)
        assertEquals(PushStrings.HTLC_NO_HELD, state.alert?.message)
        assertNull(state.loading)
    }

    @Test
    fun `a resumed HTLC shows nothing`() {
        unlockAndSync()
        depositCode = "DEP1"
        reply = HttpResponse(200, """{"success":true,"action":"resumed"}""")
        coordinator.receive(PushEnvelope.HtlcIncoming)
        coordinator.onAlertButton(state.alert!!.buttons.single())
        assertEquals(PushUiState(), state)
    }

    @Test
    fun `a payout while open asks, pays out, and clears`() {
        unlockAndSync()
        reply = HttpResponse(200, """{"success":true,"pre_image":"pre"}""")
        coordinator.receive(PushEnvelope.LightningPayout("n1", 5_000_000))
        assertEquals(PushStrings.BITTR_PAYOUT, state.alert?.title)

        coordinator.onAlertButton(state.alert!!.buttons.single())
        assertEquals(
            BittrEnvironment.DEVELOPMENT.url("payout/lightning") +
                "?notification_id=n1&invoice=lnbcrt5000000&signature=sig%3An1&pubkey=02pub",
            requests.single().url,
        )
        assertEquals(PushUiState(), state)
    }

    @Test
    fun `a payout without its data fails with the data message`() {
        unlockAndSync()
        coordinator.receive(PushEnvelope.LightningPayout(null, 0))
        coordinator.onAlertButton(state.alert!!.buttons.single())
        assertEquals(PushStrings.BITTR_PAYOUT_FAIL, state.alert?.message)
    }

    @Test
    fun `a payout that cannot reach bittr offers a retry that reconnects`() {
        unlockAndSync()
        connected = false
        reply = HttpResponse(200, """{"success":true,"pre_image":"pre"}""")
        coordinator.receive(PushEnvelope.LightningPayout("n1", 1_000))
        coordinator.onAlertButton(state.alert!!.buttons.single())
        val offline = state.alert!!
        assertEquals(PushStrings.COULDNT_CONNECT, offline.message)
        assertEquals(listOf(PushStrings.CLOSE, PushStrings.TRY_AGAIN), offline.buttons.map { it.label })

        coordinator.onAlertButton(offline.buttons[1])
        assertEquals(1, requests.size)
        assertNull(state.alert)
    }

    @Test
    fun `a transport failure keeps the payout and offers try again`() {
        unlockAndSync()
        reply = HttpResponse(502, "")
        coordinator.receive(PushEnvelope.LightningPayout("n1", 1_000))
        coordinator.onAlertButton(state.alert!!.buttons.single())
        assertEquals(listOf(PushStrings.CLOSE, PushStrings.TRY_AGAIN), state.alert!!.buttons.map { it.label })

        reply = HttpResponse(200, """{"success":true,"pre_image":"pre"}""")
        coordinator.onAlertButton(state.alert!!.buttons[1])
        assertEquals(2, requests.size)
        assertNull(state.alert)
    }

    @Test
    fun `a full channel offers on-chain or a swap, and on-chain schedules the payout`() {
        unlockAndSync()
        reply = HttpResponse(
            200,
            """{"success":false,"error":"Channel full.","error_code":"CHANNEL_FULL","suggested_swap_amount":"60000"}""",
        )
        coordinator.receive(PushEnvelope.LightningPayout("n1", 1_000))
        coordinator.onAlertButton(state.alert!!.buttons.single())
        val full = state.alert!!
        assertEquals(PushStrings.INSUFFICIENT_FUNDS, full.title)
        assertTrue(full.message.startsWith("Channel full.\n\nBittr recommends you to swap 60000 satoshis."))
        assertEquals(listOf(PushStrings.RECEIVE_ONCHAIN, PushStrings.SWAP_AND_RECEIVE_INSTANTLY), full.buttons.map { it.label })

        coordinator.onAlertButton(full.buttons[1])
        assertEquals(PushStrings.SWAP_UNAVAILABLE, state.alert?.message)

        reply = HttpResponse(200, """{"success":true}""")
        coordinator.onAlertButton(state.alert!!.buttons.single())
        assertTrue(requests.last().url.contains("/payout/onchain?notification_id=n1&signature=sig%3An1&pubkey=02pub"))
        assertEquals(PushStrings.ONCHAIN_PAYOUT_SCHEDULED, state.alert?.title)
    }

    @Test
    fun `a payout pushed while locked is replayed after the first sync without asking`() {
        reply = HttpResponse(200, """{"success":true,"pre_image":"pre"}""")
        coordinator.receive(PushEnvelope.LightningPayout("n1", 1_000))
        assertTrue(requests.isEmpty())
        unlockAndSync()
        assertEquals(1, requests.size)
        assertEquals(PushUiState(), state)
    }
}
