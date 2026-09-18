package com.bittr.android.core.swaps

import com.bittr.android.core.common.TestID
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import fr.acinq.bitcoin.Bech32
import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.OutPoint
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.PublicKey
import fr.acinq.bitcoin.Satoshi
import fr.acinq.bitcoin.ScriptFlags
import fr.acinq.bitcoin.Transaction
import fr.acinq.bitcoin.TxId
import fr.acinq.bitcoin.TxIn
import fr.acinq.bitcoin.TxOut
import fr.acinq.bitcoin.crypto.musig2.IndividualNonce
import fr.acinq.bitcoin.crypto.musig2.SecretNonce
import fr.acinq.bitcoin.crypto.musig2.Session
import fr.acinq.bitcoin.utils.Either
import java.nio.file.Files
import java.util.Date
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The swap state machine against a fake Boltz that answers the way the real one does — valid
 * lockups built from the keys the app sends, a real MuSig2 partial signature on the claim — and
 * checks every broadcast against the script interpreter.
 */
class SwapCoordinatorTest {

    private val boltzKey = PrivateKey(Hex.decode("11".repeat(32)))
    private val claimTxId = "c1".repeat(32)

    private class FakeWallet : SwapWallet {
        var ready = true
        val descriptions = mutableMapOf<String, String>()
        var channel: SwapChannel? = SwapChannel(1_000_000, 400_000, 1_000, 1_000, inboundHtlcMaximumMsat = 990_000_000)
        override fun onchainReady() = ready
        override suspend fun awaitOnchainReady() = ready
        override fun activeChannel() = channel
        override fun onchainBalanceSats() = 200_000L
        override fun onchainSpendableSats() = 190_000L
        override suspend fun fastestFeeRate(): Double? = 2.5
        override fun lastKnownFeeRate(): Long? = null
        override suspend fun drainPreview(address: String?, satPerVb: Long) = DrainPreview(199_000, 1_000)
        override suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long) = Result.success(141L)
        override fun isInsufficientFunds(failure: Throwable) = false
        override suspend fun createInvoice(amountMsat: Long, description: String, expirySecs: Int) = "lnbcrt-ours-$amountMsat"
        override suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long) = Result.success("aa".repeat(32))
        override suspend fun sendAllOnchain(address: String, satPerVb: Long) = Result.success("aa".repeat(32))
        override suspend fun startPayment(invoice: String) = Result.success("payment-1")
        override suspend fun payment(paymentId: String) = SwapPayment(SwapPaymentState.Pending, null)
        override suspend fun nextUnusedAddress() = "bcrt1qz2d3feqzlr3ggslt3ugs768utz8kmweah95qgv"
        override suspend fun swapKey(index: Int): SwapKey {
            val key = PrivateKey(Crypto.sha256("swap-key-$index".toByteArray()))
            return SwapKey(key.value.toByteArray().toHex(), key.publicKey().value.toByteArray().toHex())
        }
        override fun recordDescription(key: String, description: String) {
            descriptions[key] = description
        }
        override fun recordPaymentFees(key: String, feesSats: Long) = Unit
        override suspend fun sync() = Unit
        override suspend fun transactionIdForPayment(paymentHash: String): String? = null
    }

    private class Gate(var token: String? = "fcm-token") : SwapPushGate {
        override suspend fun deviceToken() = token
        override suspend fun webhookUrl() = "https://hooks.example/boltz/webhook/signed"
    }

    /** A Boltz that builds real lockups from the keys it is sent and co-signs the claim. */
    private inner class FakeBoltz : HttpClient {
        var preimageHash: String? = null
        var onchainAmount = 0L
        var submarineAddressOverride: String? = null
        lateinit var funding: Transaction
        var broadcast: Transaction? = null

        override suspend fun execute(request: HttpRequest): HttpResponse {
            val path = request.url.substringAfter("/v2")
            val body = request.jsonBody?.let { Json.parseToJsonElement(it).jsonObject }
            return when {
                path == "/swap/reverse" && body == null -> ok("""{"BTC":{"BTC":{"fees":{"percentage":0.25,"minerFees":{"lockup":300,"claim":200}}}}}""")
                path == "/swap/submarine" && body == null -> ok("""{"BTC":{"BTC":{"fees":{"percentage":0.1,"minerFees":226}}}}""")
                path == "/swap/reverse" -> reverse(body!!)
                path == "/swap/submarine" -> submarine(body!!)
                path.startsWith("/swap/reverse/") && path.endsWith("/claim") -> claim(body!!)
                path.startsWith("/swap/") -> ok("""{"status":"transaction.mempool","transaction":{"hex":"${Transaction.write(funding).toHex()}"}}""")
                path == "/chain/BTC/transaction" -> {
                    val tx = Transaction.read(body!!["hex"]!!.jsonPrimitive.content)
                    Transaction.correctlySpends(tx, listOf(funding), ScriptFlags.STANDARD_SCRIPT_VERIFY_FLAGS)
                    broadcast = tx
                    ok("""{"id":"$claimTxId"}""")
                }
                else -> HttpResponse(404, "")
            }
        }

        private fun reverse(body: JsonObject): HttpResponse {
            val ours = PublicKey(Hex.decode(body["claimPublicKey"]!!.jsonPrimitive.content))
            preimageHash = body["preimageHash"]!!.jsonPrimitive.content
            onchainAmount = body["onchainAmount"]!!.jsonPrimitive.long
            val claimLeaf = "82012088a914" + Crypto.ripemd160(Hex.decode(preimageHash!!)).toHex() + "8820" + ours.value.toByteArray().copyOfRange(1, 33).toHex() + "ac"
            val refundLeaf = "20" + boltzKey.publicKey().value.toByteArray().copyOfRange(1, 33).toHex() + "ad024d01b1"
            val lockup = BoltzTaproot.lockup(boltzKey.publicKey(), ours, Hex.decode(claimLeaf), Hex.decode(refundLeaf))
            funding = Transaction(
                2L,
                listOf(TxIn(OutPoint(TxId(ByteVector32(ByteArray(32) { 3 })), 0L), ByteArray(0), 0xffffffffL)),
                listOf(TxOut(Satoshi(onchainAmount), lockup.script)),
                0L,
            )
            return ok(
                """{"id":"rev1","invoice":"lnbcrt-boltz","lockupAddress":"${Bech32.encodeWitnessAddress("bcrt", 1, lockup.outputKey)}",
                |"refundPublicKey":"${boltzKey.publicKey().value.toByteArray().toHex()}",
                |"swapTree":{"claimLeaf":{"version":192,"output":"$claimLeaf"},"refundLeaf":{"version":192,"output":"$refundLeaf"}}}""".trimMargin(),
            )
        }

        private fun submarine(body: JsonObject): HttpResponse {
            val ours = PublicKey(Hex.decode(body["refundPublicKey"]!!.jsonPrimitive.content))
            val claimLeaf = "a914" + "ab".repeat(20) + "8820" + boltzKey.publicKey().value.toByteArray().copyOfRange(1, 33).toHex() + "ac"
            val refundLeaf = "20" + ours.value.toByteArray().copyOfRange(1, 33).toHex() + "ad02df01b1"
            val lockup = BoltzTaproot.lockup(boltzKey.publicKey(), ours, Hex.decode(claimLeaf), Hex.decode(refundLeaf))
            val address = submarineAddressOverride ?: Bech32.encodeWitnessAddress("bcrt", 1, lockup.outputKey)
            return ok(
                """{"id":"sub1","address":"$address","expectedAmount":75100,"claimPublicKey":"${boltzKey.publicKey().value.toByteArray().toHex()}",
                |"swapTree":{"claimLeaf":{"version":192,"output":"$claimLeaf"},"refundLeaf":{"version":192,"output":"$refundLeaf"}}}""".trimMargin(),
            )
        }

        private fun claim(body: JsonObject): HttpResponse {
            val spend = Transaction.read(body["transaction"]!!.jsonPrimitive.content)
            val ourNonce = IndividualNonce(Hex.decode(body["pubNonce"]!!.jsonPrimitive.content))
            val output = funding.txOut.single()
            val swapOutput = BoltzTaproot.SwapOutput(0, output.amount.toLong(), output.publicKeyScript.toByteArray())
            // Boltz rebuilds the key cache from the two keys and the tree; the tweaked cache is the same object here.
            val lockup = lastLockup()
            val message = BoltzTaproot.sighash(spend, swapOutput)
            val (secret, public) = SecretNonce.generate(ByteVector32(ByteArray(32) { 5 }), boltzKey, boltzKey.publicKey(), message, lockup.tweakedCache, null)
            val aggregate = (IndividualNonce.aggregate(listOf(public, ourNonce)) as Either.Right).value
            val partial = (Session.create(aggregate, message, lockup.tweakedCache).sign(secret, boltzKey) as Either.Right).value
            return ok("""{"pubNonce":"${public.toByteArray().toHex()}","partialSignature":"${partial.toByteArray().toHex()}"}""")
        }

        var lastLockup: () -> BoltzTaproot.Lockup = { error("no swap") }

        private fun ok(body: String) = HttpResponse(200, body)
    }

    private fun TestScope.coordinator(boltz: FakeBoltz, wallet: FakeWallet, gate: Gate = Gate()) = SwapCoordinator(
        api = BoltzApi(boltz, BoltzEndpoints.DEVELOPMENT, pause = {}),
        wallet = wallet,
        store = FileSwapStore(Files.createTempDirectory("swaps").toFile()),
        pushGate = gate,
        feed = { emptyFlow() },
        invoices = InvoiceInspector { invoice ->
            when {
                invoice == "lnbcrt-boltz" -> InvoiceFacts((boltz.onchainAmount + 561) * 1000, boltz.preimageHash!!)
                invoice.startsWith("lnbcrt-ours-") -> InvoiceFacts(invoice.substringAfterLast('-').toLong(), "ff".repeat(32))
                else -> null
            }
        },
        // Foreground on the test scheduler, so advanceUntilIdle runs the swap's own coroutines —
        // backgroundScope's tasks are exactly the ones it skips.
        scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob()),
        pause = {},
        now = { Date(0) },
    )

    @Test
    fun `a lightning to onchain swap is created, priced, paid and claimed`() = runTest {
        val boltz = FakeBoltz()
        val wallet = FakeWallet()
        val coordinator = coordinator(boltz, wallet)

        val ready = coordinator.prepare(SwapRequest(SwapDirection.LightningToOnchain, 50_000, maxLightningToOnchain = 60_000))
        assertTrue("$ready", ready is SwapPreparation.Ready)
        val swap = (ready as SwapPreparation.Ready).swap
        // The claim fee (2.5 × 99 = 247) is asked of Boltz on top of the amount.
        assertEquals(50_247L, boltz.onchainAmount)
        assertEquals(50_808L - 50_000L, swap.onchainFees)
        assertTrue(swap.hasVariableFee)
        // The figures keep their `<b>`: the fees alert renders them bold, as iOS does.
        assertTrue(coordinator.feesMessage(swap, "EUR", 60_000.0).startsWith("The expected fee to move <b>50 000 satoshis</b> (EUR 30) is between <b>"))

        boltz.lastLockup = {
            BoltzTaproot.lockup(boltzKey.publicKey(), PublicKey(Hex.decode(swap.claimPublicKey!!)), Hex.decode(swap.claimLeafOutput!!), Hex.decode(swap.refundLeafOutput!!))
        }
        val state = assertNotNull(coordinator.proceed(ready)).let { coordinator.statusOf("rev1")!! }
        advanceUntilIdle()

        assertEquals(SwapCopy.STATUS_COMPLETE, state.value.statusText)
        val claim = assertNotNull(boltz.broadcast).let { boltz.broadcast!! }
        assertEquals(50_247L - 247L, claim.txOut.single().amount.toLong())
        assertEquals(swap.dateId, wallet.descriptions[claimTxId])
    }

    @Test
    fun `without a push token the swap stops at the notifications alert`() = runTest {
        val refused = coordinator(FakeBoltz(), FakeWallet(), Gate(token = null))
            .prepare(SwapRequest(SwapDirection.OnchainToLightning, 75_000, maxOnchainToLightning = 150_000)) as SwapPreparation.Refused
        assertEquals(TestID.Alert.notificationsRequired, refused.alert.testTag)
        assertTrue(refused.alert.requestsNotifications)
    }

    @Test
    fun `an onchain to lightning swap to a substituted address is refused before funds move`() = runTest {
        val boltz = FakeBoltz().apply { submarineAddressOverride = "bcrt1pcz9mae53csyv8d0t4fansh446jdjey2pg2djn5utqver5e42gp5s507k3j" }
        val refused = coordinator(boltz, FakeWallet()).prepare(SwapRequest(SwapDirection.OnchainToLightning, 75_000, maxOnchainToLightning = 150_000))
        assertEquals(TestID.Alert.swapValidationFailed, (refused as SwapPreparation.Refused).alert.testTag)
    }

    @Test
    fun `an onchain to lightning swap is priced from the transaction size`() = runTest {
        val ready = coordinator(FakeBoltz(), FakeWallet())
            .prepare(SwapRequest(SwapDirection.OnchainToLightning, 75_000, maxOnchainToLightning = 150_000)) as SwapPreparation.Ready
        assertEquals(2L * 141L, ready.swap.onchainFees)
        assertEquals(100L, ready.swap.lightningFees)
        assertEquals(false, ready.drain)
    }

    @Test
    fun `at the maximum the swap drains and more than a payment can carry is refused`() = runTest {
        val coordinator = coordinator(FakeBoltz(), FakeWallet())
        val drained = coordinator.prepare(SwapRequest(SwapDirection.OnchainToLightning, 90_000, maxOnchainToLightning = 75_000)) as SwapPreparation.Ready
        assertTrue(drained.drain)
        assertEquals(75_000L, drained.swap.satoshisAmount)

        val tooMuch = coordinator.prepare(SwapRequest(SwapDirection.LightningToOnchain, 1_000_000)) as SwapPreparation.Refused
        assertEquals(SwapCopy.AMOUNT_EXCEEDED.replace("<amount>", "990000"), tooMuch.alert.message)
    }
}
