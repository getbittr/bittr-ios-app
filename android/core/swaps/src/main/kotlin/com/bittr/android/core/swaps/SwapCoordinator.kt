package com.bittr.android.core.swaps

import com.bittr.android.core.common.TestID
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.PublicKey
import fr.acinq.bitcoin.Transaction
import java.io.File
import java.security.SecureRandom
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** An alert a swap step raises. [testTag] is the card's id where iOS gives one. */
data class SwapAlert(
    val title: String,
    val message: String,
    val testTag: String? = null,
    /** `alert.notificationsRequired`: Okay asks for the notification permission. */
    val requestsNotifications: Boolean = false,
)

/** What the user asked to swap, with the maxima the screen last computed. */
data class SwapRequest(
    val direction: SwapDirection,
    val amountSats: Long,
    val maxOnchainToLightning: Long? = null,
    val maxLightningToOnchain: Long? = null,
    /** Swap & Pay from Send: pay this invoice with the swap instead of one of our own. */
    val existingInvoice: String? = null,
    /** Swap & Pay from Send: the on-chain address the reverse swap pays out to. */
    val payoutAddress: String? = null,
    val suggested: Boolean = false,
)

sealed interface SwapPreparation {
    /** Created and validated, fees known: ask the user. [drain] sends the whole on-chain balance. */
    data class Ready(val swap: Swap, val drain: Boolean) : SwapPreparation

    data class Refused(val alert: SwapAlert) : SwapPreparation
}

/** "Move up to <amount> sats." — and whether the on-chain wallet still has to sync first. */
data class SwapLimit(val maxSats: Long, val needsOnchainSync: Boolean = false)

/** The status card. */
data class SwapStatusState(
    val swap: Swap,
    val statusText: String,
    val spinning: Boolean,
    val lastStatus: String?,
    val complete: Boolean,
)

sealed interface SwapEvent {
    data class Alert(val boltzId: String?, val alert: SwapAlert) : SwapEvent
    data class OpenTransaction(val transactionId: String) : SwapEvent

    /** A push arrived for a swap: show its status. */
    data class ShowSwap(val boltzId: String) : SwapEvent
}

private class SwapClaimException(message: String) : Exception(message)

/**
 * The swap state machine — `SwapManager` plus the non-UI half of `SwapViewController` and
 * `SwapStatusViewController`.
 *
 * It lives in the app's process scope rather than a screen's, which is the one deliberate
 * difference from iOS: there the websocket, the claim and the refund belong to the view
 * controller and stop when it goes, here they keep running when the user leaves the screen. A
 * reverse swap whose claim never happens is a Lightning payment that times out, so the more of
 * it that survives a closed screen, the better.
 */
class SwapCoordinator(
    private val api: BoltzApi,
    private val wallet: SwapWallet,
    private val store: SwapStore,
    private val pushGate: SwapPushGate,
    private val feed: SwapStatusFeed,
    private val invoices: InvoiceInspector,
    private val scope: CoroutineScope,
    private val random: SecureRandom = SecureRandom(),
    private val pause: suspend (Long) -> Unit = { delay(it) },
    private val now: () -> Date = { Date() },
) : SwapPushHandler {

    private val trackers = ConcurrentHashMap<String, Tracker>()
    private val _events = MutableSharedFlow<SwapEvent>(extraBufferCapacity = 16)
    val events: SharedFlow<SwapEvent> = _events.asSharedFlow()

    private val chain get() = api.endpoints.chain

    // ---- The swap screen. ----

    /** `calculateSendableAmount`. */
    suspend fun limit(direction: SwapDirection): SwapLimit {
        val channel = wallet.activeChannel() ?: return SwapLimit(0)
        if (direction == SwapDirection.LightningToOnchain) {
            val quote = api.feeQuote(reverse = true)
            val claimFee = claimFee()
            return SwapLimit(SwapAmounts.maxLightningToOnchain(channel.outboundSats, quote, claimFee))
        }
        if (!wallet.onchainReady()) return SwapLimit(0, needsOnchainSync = true)
        if (wallet.onchainBalanceSats() == 0L) return SwapLimit(0)
        val space = SwapAmounts.availableChannelSpace(channel.channelValueSats, channel.outboundSats, channel.reserveSats, channel.counterpartyReserveSats)
        val rate = wallet.fastestFeeRate() ?: return SwapLimit(minOf(space, maxOf(wallet.onchainSpendableSats(), 0)))
        val drain = wallet.drainPreview(null, SwapAmounts.wholeSatPerVb(rate)) ?: return SwapLimit(0)
        return SwapLimit(SwapAmounts.maxOnchainToLightning(drain.sendableSats, api.feeQuote(reverse = false), space))
    }

    fun onchainReady(): Boolean = wallet.onchainReady()

    /** `awaitBdkScan`: false when the scan failed or ran out of time. */
    suspend fun awaitOnchainReady(): Boolean = wallet.awaitOnchainReady()

    /**
     * `nextTapped` and everything up to the fees alert: create the swap at Boltz, check it, price it.
     *
     * A [SwapRequest.suggested] swap skips the screen's amount checks, as iOS's
     * `startSuggestedOnchainToLightningSwap` and `handlePendingOnchainPayment` go straight to
     * `SwapManager` without `nextTapped`: Swap & Pay is offered precisely when there may be no
     * channel to measure the amount against.
     */
    suspend fun prepare(request: SwapRequest): SwapPreparation {
        if (request.direction == SwapDirection.OnchainToLightning && !wallet.onchainReady()) {
            return refused(SwapCopy.SYNCING, SwapCopy.AWAITING_BDK_SYNC)
        }
        var amount = request.amountSats
        if (amount <= 0) return refused(SwapCopy.SWAP_FUNDS, SwapCopy.ENTER_AMOUNT_OF_SATOSHIS)

        val maxAmount = (wallet.activeChannel()?.inboundHtlcMaximumMsat ?: 0L) / 1000
        if (!request.suggested && amount > maxAmount) return refused(SwapCopy.SWAP_FUNDS, SwapCopy.AMOUNT_EXCEEDED.replace("<amount>", "$maxAmount"))

        var drain = false
        if (request.suggested) {
            // Straight to Boltz.
        } else if (request.direction == SwapDirection.OnchainToLightning && request.maxOnchainToLightning != null && amount >= request.maxOnchainToLightning) {
            // At or above the maximum: drain the whole on-chain balance to Boltz.
            amount = request.maxOnchainToLightning
            drain = true
        } else if (request.direction == SwapDirection.LightningToOnchain && request.maxLightningToOnchain != null && amount > request.maxLightningToOnchain) {
            return refused(SwapCopy.SWAP_FUNDS, SwapCopy.AMOUNT_EXCEEDED.replace("<amount>", "${request.maxLightningToOnchain}"))
        }

        return runCatching {
            if (request.direction == SwapDirection.OnchainToLightning) {
                onchainToLightning(amount, drain, request)
            } else {
                lightningToOnchain(amount, request)
            }
        }.getOrElse { failure ->
            when (failure) {
                is SwapValidationException -> SwapPreparation.Refused(SwapAlert(SwapCopy.ERROR, SwapCopy.VALIDATION_FAILED, TestID.Alert.swapValidationFailed))
                is RefusedException -> SwapPreparation.Refused(failure.alert)
                else -> refused(SwapCopy.ERROR, failure.message ?: SwapCopy.SWAP_ERROR_2)
            }
        }
    }

    /** `confirmExpectedFees`: the fees alert's message. */
    fun feesMessage(swap: Swap, currencyCode: String, pricePerBitcoin: Double?): String {
        val price = pricePerBitcoin ?: 0.0
        fun fiat(sats: Long) = String.format(Locale.getDefault(), "%.2f", sats / 100_000_000.0 * price)
        val minimum = fiat(swap.minimumTotalFees)
        val maximum = fiat(swap.maximumTotalFees)
        val convertedFees = if (minimum == maximum) maximum else "$minimum - $maximum"
        val convertedAmount = (swap.satoshisAmount / 100_000_000.0 * price).roundToLong()
        val message = (if (swap.hasVariableFee) SwapCopy.FEES_MESSAGE_RANGE else SwapCopy.FEES_MESSAGE)
            .replace("<feesamountmin>", SwapAmounts.group(swap.minimumTotalFees))
            .replace("<feesamount>", SwapAmounts.group(swap.maximumTotalFees))
            .replace("<convertedfees>", "$currencyCode $convertedFees")
            .replace("<amount>", SwapAmounts.group(swap.satoshisAmount))
            .replace("<convertedamount>", "$currencyCode $convertedAmount")
        val caution = if (swap.direction == SwapDirection.OnchainToLightning) SwapCopy.ONCHAIN_TO_LIGHTNING_EXPLANATION else ""
        return SwapCopy.plain(message + caution + " " + SwapCopy.WISH_TO_PROCEED)
    }

    /**
     * `proceedWithSwap`: pay Boltz and watch the swap. The returned state is the status card.
     *
     * Null when a lightning-to-onchain invoice no longer pays our preimage, which raises
     * `alert.swapValidationFailed` through [events] and moves nothing.
     */
    fun proceed(ready: SwapPreparation.Ready): StateFlow<SwapStatusState>? {
        val swap = ready.swap
        if (swap.direction == SwapDirection.LightningToOnchain && !invoicePaysPreimage(swap)) {
            _events.tryEmit(SwapEvent.Alert(swap.boltzId, SwapAlert(SwapCopy.ERROR, SwapCopy.VALIDATION_FAILED, TestID.Alert.swapValidationFailed)))
            return null
        }
        store.saveLatest(swap)
        val tracker = trackerFor(swap)
        scope.launch {
            launch {
                pause(2_000)
                tracker.checkNow(fromRefresh = false)
            }
            if (swap.direction == SwapDirection.OnchainToLightning) sendOnchain(tracker, ready.drain) else payLightning(tracker)
        }
        return tracker.state
    }

    /** The status card for a swap already on the device — the transaction screen's `swapStatusButton`. */
    fun statusOf(boltzId: String): StateFlow<SwapStatusState>? {
        trackers[boltzId]?.let { return it.state }
        val swap = store.load(boltzId) ?: return null
        val tracker = trackerFor(swap)
        scope.launch {
            pause(2_000)
            tracker.checkNow(fromRefresh = false)
        }
        return tracker.state
    }

    /** The refresh button — `confirmStatusButtonTapped`. */
    fun refresh(boltzId: String) {
        val tracker = trackers[boltzId] ?: return
        scope.launch { tracker.checkNow(fromRefresh = true) }
    }

    /** The swap file, for "Download details". */
    fun swapFile(boltzId: String): File? = store.fileFor(boltzId)

    override suspend fun onSwapPush(swapId: String?, status: String?) {
        val id = swapId ?: return
        val swap = store.loadForPushedId(id) ?: store.load(id) ?: return
        val boltzId = swap.boltzId ?: return
        val tracker = trackerFor(swap)
        _events.tryEmit(SwapEvent.ShowSwap(boltzId))
        tracker.checkNow(fromRefresh = false)
        if (!tracker.state.value.complete) tracker.subscribe()
    }

    // ---- Creating a swap. ----

    /** `SwapManager.onchainToLightning`. */
    private suspend fun onchainToLightning(amount: Long, drain: Boolean, request: SwapRequest): SwapPreparation {
        val dateId = "Swap onchain to lightning ${SwapAmounts.createDateId(now())}"
        val invoice = request.existingInvoice
            ?: wallet.createInvoice(amount * 1000, dateId, INVOICE_EXPIRY_SECS)
            ?: return refused(SwapCopy.ERROR, SwapCopy.INVOICE_CREATE_FAIL)
        val facts = invoices.inspect(invoice)
        val invoiceMsat = facts?.amountMsat ?: return refused(SwapCopy.ERROR, SwapCopy.SWAP_ERROR_2)
        if (request.existingInvoice == null) wallet.recordDescription(facts.paymentHashHex, dateId)

        val key = swapKey() ?: return refused(SwapCopy.ERROR, SwapCopy.SWAP_ERROR_2)
        val webhook = webhook()

        val quote = api.feeQuote(reverse = false)
        val created = api.createSubmarine(invoice, key.publicKeyHex, webhook)
        BoltzSwapValidation.validateSubmarineLockup(
            address = created.address,
            claimPublicKeyHex = created.claimPublicKey,
            refundPrivateKeyHex = key.privateKeyHex,
            ourRefundPublicKeyHex = key.publicKeyHex,
            claimLeafOutputHex = created.claimLeafOutput,
            refundLeafOutputHex = created.refundLeafOutput,
            chain = chain,
        )
        BoltzSwapValidation.validateQuotedAmount(invoiceMsat / 1000, created.expectedAmount, quote)

        var swap = Swap(
            dateId = dateId,
            direction = SwapDirection.OnchainToLightning,
            isSuggested = request.existingInvoice != null,
            satoshisAmount = amount,
            createdInvoice = invoice,
            privateKey = key.privateKeyHex,
            boltzId = created.id,
            boltzOnchainAddress = created.address,
            boltzExpectedAmount = created.expectedAmount,
            claimLeafOutput = created.claimLeafOutput,
            refundLeafOutput = created.refundLeafOutput,
            claimPublicKey = created.claimPublicKey,
            refundPublicKey = key.publicKeyHex,
        )
        store.save(swap)

        // `checkOnchainFees`.
        val rate = wallet.fastestFeeRate()
            ?: return refused(SwapCopy.OOPS, "${SwapCopy.CANNOT_PROCEED}. Error: Could not get fee estimates.")
        val wholeRate = SwapAmounts.wholeSatPerVb(rate)
        val onchainFees: Long
        val lightningFees: Long
        if (drain) {
            val preview = wallet.drainPreview(created.address, wholeRate) ?: return refused(SwapCopy.OOPS, "${SwapCopy.CANNOT_PROCEED}.")
            if (preview.sendableSats < created.expectedAmount) return insufficientOnchain()
            onchainFees = preview.feeSats
            lightningFees = maxOf(preview.sendableSats - amount, 0)
        } else {
            val vsize = wallet.transactionVsize(created.address, created.expectedAmount, wholeRate).getOrElse { failure ->
                return if (wallet.isInsufficientFunds(failure)) insufficientOnchain()
                else refused(SwapCopy.OOPS, "${SwapCopy.CANNOT_PROCEED}. Error: ${failure.message}.")
            }
            onchainFees = SwapAmounts.feeSats(rate, vsize)
            lightningFees = created.expectedAmount - amount
        }
        swap = swap.copy(feeHigh = rate, onchainFees = onchainFees, lightningFees = lightningFees)
        return SwapPreparation.Ready(swap, drain)
    }

    /** `SwapManager.lightningToOnchain` and `checkReverseSwapFees`. */
    private suspend fun lightningToOnchain(amount: Long, request: SwapRequest): SwapPreparation {
        // The user's amount is what arrives on-chain, so our claim fee is asked of Boltz on top.
        val claimFee = claimFee()
        val onchainAmount = amount + claimFee

        val preimage = ByteArray(32).also(random::nextBytes)
        val preimageHash = Crypto.sha256(preimage).toHex()
        val key = swapKey() ?: return refused(SwapCopy.ERROR, SwapCopy.SWAP_ERROR_2)
        val destination = request.payoutAddress ?: wallet.nextUnusedAddress() ?: return refused(SwapCopy.ERROR, SwapCopy.SWAP_ERROR_2)
        val dateId = "Swap lightning to onchain ${SwapAmounts.createDateId(now())}"
        val webhook = webhook()

        val quote = api.feeQuote(reverse = true)
        val created = api.createReverse(key.publicKeyHex, preimageHash, onchainAmount, webhook)
        BoltzSwapValidation.validateReverseInvoice(created.invoice, preimageHash, onchainAmount, quote, invoices)
        BoltzSwapValidation.validateReverseLockup(
            address = created.lockupAddress,
            refundPublicKeyHex = created.refundPublicKey,
            claimPrivateKeyHex = key.privateKeyHex,
            ourClaimPublicKeyHex = key.publicKeyHex,
            preimageHex = preimage.toHex(),
            claimLeafOutputHex = created.claimLeafOutput,
            refundLeafOutputHex = created.refundLeafOutput,
            chain = chain,
        )

        val invoiceSats = (invoices.inspect(created.invoice)?.amountMsat ?: return refused(SwapCopy.ERROR, SwapCopy.SWAP_ERROR_2)) / 1000
        val swap = Swap(
            dateId = dateId,
            direction = SwapDirection.LightningToOnchain,
            isSuggested = request.suggested || request.payoutAddress != null,
            satoshisAmount = amount,
            privateKey = key.privateKeyHex,
            boltzId = created.id,
            boltzExpectedAmount = invoiceSats,
            onchainFees = invoiceSats - amount,
            lightningFees = SwapAmounts.maxRoutingFeeSats(invoiceSats),
            claimTransactionFee = claimFee,
            refundPublicKey = created.refundPublicKey,
            claimLeafOutput = created.claimLeafOutput,
            refundLeafOutput = created.refundLeafOutput,
            claimPublicKey = key.publicKeyHex,
            preimage = preimage.toHex(),
            destinationAddress = destination,
            boltzInvoice = created.invoice,
        )
        store.save(swap)
        store.storeSwapId(dateId, created.id)
        wallet.recordDescription(preimageHash, dateId)
        if (swap.isSuggested) store.setSuggestedStatus(dateId, SuggestedSwapStatus.Pending)
        return SwapPreparation.Ready(swap, drain = false)
    }

    /** The gate iOS runs after deriving the key: a push token, then a signed webhook URL. */
    private suspend fun webhook(): String {
        if (pushGate.deviceToken().isNullOrEmpty()) {
            throw RefusedException(
                SwapAlert(SwapCopy.NOTIFICATIONS_REQUIRED, SwapCopy.NOTIFICATIONS_REQUIRED_MESSAGE, TestID.Alert.notificationsRequired, requestsNotifications = true),
            )
        }
        return pushGate.webhookUrl() ?: throw RefusedException(SwapAlert(SwapCopy.ERROR, SwapCopy.COULDNT_CONNECT))
    }

    /** `incrementSwapIndex()` then derive — the index moves on every attempt, used or not. */
    private suspend fun swapKey(): SwapKey? = runCatching { wallet.swapKey(store.nextSwapIndex()) }.getOrNull()

    private suspend fun claimFee(): Long = SwapAmounts.claimOrRefundFee(wallet.fastestFeeRate(), wallet.lastKnownFeeRate())

    private fun insufficientOnchain() = refused(
        SwapCopy.INSUFFICIENT_FUNDS,
        SwapCopy.plain(SwapCopy.ONCHAIN_INSUFFICIENT_FUNDS).replace("<amount>", "${wallet.onchainBalanceSats()}"),
    )

    /** `didVerifyBoltzInvoice`: the invoice we are about to pay still pays for our preimage. */
    private fun invoicePaysPreimage(swap: Swap): Boolean {
        val preimage = swap.preimage?.let { runCatching { Hex.decode(it) }.getOrNull() } ?: return false
        val invoice = swap.boltzInvoice ?: return false
        val hash = invoices.inspect(invoice)?.paymentHashHex ?: return false
        return hash.equals(Crypto.sha256(preimage).toHex(), ignoreCase = true)
    }

    // ---- Paying Boltz. ----

    /** `sendOnchainPayment` and `finalizeOnchainSend`. */
    private suspend fun sendOnchain(tracker: Tracker, drain: Boolean) {
        val swap = tracker.swap
        val address = swap.boltzOnchainAddress ?: return
        val rate = SwapAmounts.wholeSatPerVb(swap.feeHigh ?: 1.0)
        val result = if (drain) wallet.sendAllOnchain(address, rate) else wallet.sendOnchain(address, swap.boltzExpectedAmount ?: return, rate)
        val txId = result.getOrElse {
            tracker.update { it.copy(spinning = false) }
            _events.tryEmit(SwapEvent.Alert(swap.boltzId, SwapAlert(SwapCopy.PAYMENT_FAILED, SwapCopy.PAYMENT_FAILED_3)))
            return
        }
        // The raw lockup, so a refund can rebuild it later.
        val raw = api.rawTransactionHex(txId)
        pause(2_000)
        val updated = swap.copy(sentOnchainTransactionId = txId, lockupTx = raw)
        tracker.setSwap(updated)
        store.save(updated)
        wallet.recordDescription(txId, updated.dateId)
        updated.boltzId?.let { store.storeSwapId(updated.dateId, it) }
        if (updated.isSuggested) store.setSuggestedStatus(updated.dateId, SuggestedSwapStatus.Pending)
        scope.launch { runCatching { wallet.sync() } }

        // `didCompleteOnchainTransaction`. A status that already completed the swap stays.
        tracker.update { if (it.complete) it else it.copy(statusText = SwapCopy.STATUS_AWAITING_CONFIRMATION, spinning = false) }
        store.saveLatest(updated)
        tracker.subscribe()
    }

    /** `performLightningPayment` then `didReceivePaymentHash`. */
    private suspend fun payLightning(tracker: Tracker) {
        val swap = tracker.swap
        val paymentId = wallet.startPayment(swap.boltzInvoice ?: return).getOrNull()
        pause(3_000)
        val payment = paymentId?.let { wallet.payment(it) }
        if (payment == null || payment.state == SwapPaymentState.Failed) {
            tracker.update { it.copy(statusText = SwapCopy.STATUS_FAILED_TO_PAY, spinning = false) }
            _events.tryEmit(SwapEvent.Alert(swap.boltzId, SwapAlert(SwapCopy.PAYMENT_FAILED, SwapCopy.PAYMENT_FAILED_2.replace("<reason>", ""))))
            return
        }
        tracker.update { if (it.complete) it else it.copy(statusText = SwapCopy.STATUS_AWAITING_TRANSACTION) }
        payment.amountMsat?.let { msat ->
            val paid = msat / 1000
            if (paid > swap.satoshisAmount) swap.preimage?.let { wallet.recordPaymentFees(it, paid - swap.satoshisAmount) }
        }
        tracker.subscribe()
    }

    // ---- Claim and refund. ----

    /** `claimLightningToOnchainSwap`. Returns the broadcast txid. */
    private suspend fun claimTransaction(swap: Swap): String {
        val fee = swap.claimTransactionFee ?: claimFee()
        val boltzKey = PublicKey(Hex.decode(swap.refundPublicKey ?: throw SwapClaimException("No Boltz key")))
        val ourKey = PrivateKey(Hex.decode(swap.privateKey ?: throw SwapClaimException("No swap key")))
        val lockup = BoltzTaproot.lockup(boltzKey, ourKey.publicKey(), Hex.decode(swap.claimLeafOutput!!), Hex.decode(swap.refundLeafOutput!!))
        val lockupTransaction = Transaction.read(swap.lockupTx ?: throw SwapClaimException("No lockup"))
        val output = BoltzTaproot.detectSwapOutput(lockupTransaction, lockup) ?: throw SwapClaimException("No swap output found")

        // Never claim an underfunded lockup: claiming reveals the preimage, which settles the held
        // invoice in full. Left unclaimed, the invoice times out and the Lightning payment refunds.
        val expected = swap.satoshisAmount + fee
        val tolerance = maxOf(swap.satoshisAmount / 100, 1000L)
        if (output.valueSats < maxOf(0L, expected - tolerance)) throw SwapClaimException("Underfunded lockup: ${output.valueSats} < $expected")

        val destination = BoltzTaproot.outputScript(swap.destinationAddress ?: "", chain) ?: throw SwapClaimException("Bad destination")
        val spend = BoltzTaproot.unsignedSpend(lockupTransaction, output, destination, fee, refund = false)
        val session = BoltzTaproot.startSigning(ourKey, boltzKey, lockup, BoltzTaproot.sighash(spend, output), random)
        val partial = api.requestClaim(swap.boltzId!!, Transaction.write(spend).toHex(), swap.preimage!!, session.publicNonceHex)
        val signed = BoltzTaproot.signed(spend, session.finish(partial.pubNonce, partial.partialSignature))
        return api.broadcast(Transaction.write(signed).toHex())
    }

    /** `refundOnchainToLightningSwap`. Cooperative only, as on iOS. */
    private suspend fun refundTransaction(swap: Swap): String {
        val boltzKey = PublicKey(Hex.decode(swap.claimPublicKey ?: throw SwapClaimException("No Boltz key")))
        val ourKey = PrivateKey(Hex.decode(swap.privateKey ?: throw SwapClaimException("No swap key")))
        val lockup = BoltzTaproot.lockup(boltzKey, ourKey.publicKey(), Hex.decode(swap.claimLeafOutput!!), Hex.decode(swap.refundLeafOutput!!))
        val lockupHex = swap.lockupTx?.takeIf { it.isNotEmpty() }
            ?: swap.sentOnchainTransactionId?.let { api.rawTransactionHex(it) }
            ?: throw SwapClaimException("No lockup transaction for the refund")
        val lockupTransaction = Transaction.read(lockupHex)
        val output = BoltzTaproot.detectSwapOutput(lockupTransaction, lockup) ?: throw SwapClaimException("No swap output found")
        val address = wallet.nextUnusedAddress() ?: throw SwapClaimException("No refund address")
        val destination = BoltzTaproot.outputScript(address, chain) ?: throw SwapClaimException("Bad refund address")
        val spend = BoltzTaproot.unsignedSpend(lockupTransaction, output, destination, claimFee(), refund = true)
        val session = BoltzTaproot.startSigning(ourKey, boltzKey, lockup, BoltzTaproot.sighash(spend, output), random)
        val partial = api.requestRefund(swap.boltzId!!, Transaction.write(spend).toHex(), session.publicNonceHex)
        val signed = BoltzTaproot.signed(spend, session.finish(partial.pubNonce, partial.partialSignature))
        return api.broadcast(Transaction.write(signed).toHex()).also { wallet.recordDescription(it, swap.dateId) }
    }

    /** `openCompletedSwapTransaction`: up to four looks, five seconds apart, for the swap's Lightning leg. */
    private suspend fun openCompleted(swap: Swap) {
        val invoice = if (swap.direction == SwapDirection.OnchainToLightning) swap.createdInvoice else swap.boltzInvoice
        val hash = invoice?.let { invoices.inspect(it)?.paymentHashHex } ?: return
        repeat(4) { attempt ->
            wallet.transactionIdForPayment(hash)?.let {
                _events.tryEmit(SwapEvent.OpenTransaction(it))
                return
            }
            if (attempt < 3) pause(5_000)
        }
    }

    private fun trackerFor(swap: Swap): Tracker {
        val id = swap.boltzId ?: error("A swap is only tracked once Boltz has created it")
        return trackers.getOrPut(id) { Tracker(swap) }
    }

    private fun refused(title: String, message: String) = SwapPreparation.Refused(SwapAlert(title, message))

    private class RefusedException(val alert: SwapAlert) : Exception(alert.message)

    /** One watched swap: its card, its subscription, and the single-flight guards on claim and refund. */
    private inner class Tracker(initial: Swap) {
        private val _state = MutableStateFlow(SwapStatusState(initial, SwapCopy.CHECKING, spinning = true, lastStatus = null, complete = false))
        val state: StateFlow<SwapStatusState> = _state.asStateFlow()
        val swap: Swap get() = _state.value.swap
        private val id = initial.boltzId!!
        private var subscription: Job? = null
        private val claiming = AtomicBoolean(false)
        private val refunding = AtomicBoolean(false)
        private val completionHandled = AtomicBoolean(false)

        fun update(block: (SwapStatusState) -> SwapStatusState) = _state.update(block)

        fun setSwap(swap: Swap) = update { it.copy(swap = swap) }

        @Synchronized
        fun subscribe() {
            if (subscription?.isActive == true) return
            subscription = scope.launch { feed.updates(id).collect { apply(it, fromRefresh = false) } }
        }

        fun unsubscribe() {
            subscription?.cancel()
        }

        suspend fun checkNow(fromRefresh: Boolean) {
            if (fromRefresh) update { it.copy(spinning = true) }
            val update = api.status(id)
            update { it.copy(spinning = false) }
            if (update != null) apply(update, fromRefresh)
        }

        /** `receivedStatusUpdate`, and the refresh button's branch of it. */
        suspend fun apply(update: SwapStatusUpdate, fromRefresh: Boolean) {
            val current = swap
            BoltzStatus.suggestedMarker(update.status)?.let { marker ->
                if (current.isSuggested && current.dateId.isNotEmpty()) store.setSuggestedStatus(current.dateId, marker)
            }
            showStatus(update.status)

            val lightningToOnchain = current.direction == SwapDirection.LightningToOnchain
            when {
                BoltzStatus.needsRefund(update.status) -> {
                    update { it.copy(spinning = false) }
                    if (current.direction == SwapDirection.OnchainToLightning) refund()
                }
                lightningToOnchain && update.status == "transaction.mempool" && update.transactionHex != null -> claim(update.transactionHex)
                lightningToOnchain && fromRefresh && (update.status == "transaction.confirmed" || update.status == "invoice.settled") ->
                    (update.transactionHex ?: store.load(id)?.lockupTx)?.let { claim(it) }
                update.status == "transaction.claimed" -> {
                    update { it.copy(spinning = false) }
                    unsubscribe()
                }
            }

            if (current.direction == SwapDirection.OnchainToLightning && BoltzStatus.phase(update.status) == SwapPhase.Complete &&
                completionHandled.compareAndSet(false, true)
            ) {
                scope.launch {
                    pause(3_000)
                    runCatching { wallet.sync() }
                    if (!current.isSuggested) openCompleted(current)
                }
            }
        }

        /** `showStatus`: once complete, a late non-complete status does not overwrite it. */
        private fun showStatus(status: String) {
            val text = BoltzStatus.userFriendly(status, swap.direction)
            update { state ->
                if (state.complete && text != SwapCopy.STATUS_COMPLETE) {
                    state.copy(lastStatus = status)
                } else {
                    state.copy(statusText = text, lastStatus = status, complete = state.complete || text == SwapCopy.STATUS_COMPLETE)
                }
            }
        }

        /** `handleTransactionMempool`. */
        private suspend fun claim(lockupHex: String) {
            if (!claiming.compareAndSet(false, true)) return
            val withLockup = swap.copy(lockupTx = lockupHex)
            setSwap(withLockup)
            store.saveLatest(withLockup)
            store.save(withLockup)
            runCatching { claimTransaction(withLockup) }
                .onSuccess { txId ->
                    update { it.copy(statusText = SwapCopy.STATUS_COMPLETE, complete = true, spinning = false) }
                    unsubscribe()
                    // `addOnchainTransactionToUI`.
                    wallet.recordDescription(txId, withLockup.dateId)
                    withLockup.boltzId?.let { store.storeSwapId(withLockup.dateId, it) }
                    if (withLockup.isSuggested) {
                        store.save(withLockup.copy(sentOnchainTransactionId = txId))
                        store.setSuggestedStatus(withLockup.dateId, SuggestedSwapStatus.Succeeded)
                    }
                    scope.launch {
                        pause(3_000)
                        runCatching { wallet.sync() }
                        if (!withLockup.isSuggested) openCompleted(withLockup)
                    }
                }
                .onFailure {
                    update { state -> state.copy(statusText = SwapCopy.STATUS_FAILED, spinning = false) }
                    // A refresh may try again: every refusal above is re-checked from scratch.
                    claiming.set(false)
                }
        }

        private suspend fun refund() {
            if (!refunding.compareAndSet(false, true)) return
            runCatching { refundTransaction(swap) }.onFailure { refunding.set(false) }
        }
    }

    private companion object {
        const val INVOICE_EXPIRY_SECS = 3600
    }
}
