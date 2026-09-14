package com.bittr.android.push

import android.util.Log
import com.bittr.android.core.common.TestID
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.HtlcReady
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.LightningPayout
import com.bittr.android.core.network.OnchainPayout
import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.wallet.WalletOverview
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A card with a spinner — iOS `showLoading(id:message:)`. [testTag] sits on the card. */
data class PushLoading(val testTag: String?, val message: String)

/** One alert button, in iOS `buttons:` order, which is `alert.button.N` order. */
data class PushAlertButton(val label: String, val dismisses: Boolean, val onClick: () -> Unit = {})

/** An alert — iOS `showAlert(id:title:message:buttons:)`. [testTag] sits on the card. */
data class PushAlert(val testTag: String?, val title: String, val message: String, val buttons: List<PushAlertButton>)

/** The Question card a push opens — iOS `launchQuestion`. [title] is already lowercased, as `addHeader` does. */
data class PushQuestion(val title: String, val answer: String)

data class PushUiState(
    val loading: PushLoading? = null,
    val alert: PushAlert? = null,
    val question: PushQuestion? = null,
)

/**
 * What a bittr push does once it reaches the app — iOS's `handleNotification`,
 * `CoreViewController.newNotification` and the handlers in `Notifications/`.
 *
 * ### Dedup, then a one-second delay
 *
 * A push is accepted only if the last accepted one had a different id (or none) **and**
 * is more than ten seconds old, exactly iOS's `CacheManager.getLastNotification()` test,
 * and is handled a second later. `notification_information.yaml` re-pushes until a card
 * opens, and relies on the window swallowing the early re-pushes.
 *
 * ### Locked, then syncing, then ready
 *
 * Payouts and incoming HTLCs are *pending* while the wallet is locked — no alert, so the
 * user can unlock quickly — and `wasNotified` records that the push, not the user,
 * started it. Unlocking with a push pending shows `loading.syncingWallet`
 * (`lowerPinView`), and the first finished sync re-dispatches it (`finalizeSync`), which
 * then skips the "you're receiving a payment" alert and goes straight to the payout.
 * Information, expired and unknown pushes open their card at once, locked or not.
 */
class PushCoordinator(
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher,
    private val walletState: StateFlow<WalletState>,
    private val overview: StateFlow<WalletOverview>,
    private val signer: BittrRequestSigner,
    private val node: PushNode,
    private val http: HttpClient,
    private val environment: BittrEnvironment,
    private val depositCodes: DepositCodeSource,
    private val swapHandler: SwapPushHandler?,
    private val lnurlHandler: LnurlPushHandler?,
    private val payoutSwap: PayoutSwapLauncher?,
    private val clockMillis: () -> Long = System::currentTimeMillis,
    private val pause: suspend (Long) -> Unit = { delay(it) },
    private val log: (String) -> Unit = { Log.i(TAG, it) },
) {

    private val _uiState = MutableStateFlow(PushUiState())
    val uiState: StateFlow<PushUiState> = _uiState.asStateFlow()

    private var lastAcceptedId: String? = null
    private var lastAcceptedAt: Long? = null

    /** iOS `lightningNotification`. */
    private var pending: PushEnvelope? = null

    /** iOS `wasNotified`: the pending push arrived while the wallet was locked. */
    private var wasNotified = false

    /** iOS `isHandlingIncomingHTLC`. */
    private var handlingHtlc = false

    private val signedIn: Boolean get() = walletState.value == WalletState.Ready
    private val synced: Boolean get() = overview.value.hasSynced

    init {
        scope.launch {
            var wasSignedIn = signedIn
            var wasSynced = synced
            combine(walletState, overview) { state, wallet -> (state == WalletState.Ready) to wallet.hasSynced }
                .distinctUntilChanged()
                .collect { (nowSignedIn, nowSynced) ->
                    val waiting = pending
                    if (waiting != null && nowSignedIn && !wasSignedIn && !nowSynced) {
                        // lowerPinView: a push will be handled once the wallet has synced.
                        showLoading(TestID.Loading.syncingWallet, PushStrings.SYNCING_WALLET_3)
                    }
                    if (waiting != null && nowSignedIn && nowSynced && !(wasSignedIn && wasSynced)) {
                        // finalizeSync: payout, HTLC, swap and LNURL pushes are replayed.
                        dispatch(waiting)
                    }
                    wasSignedIn = nowSignedIn
                    wasSynced = nowSynced
                }
        }
    }

    /** A decoded push, from FCM or the debug receiver. [id] is the message id when there is one. */
    fun receive(envelope: PushEnvelope, id: String? = null) {
        scope.launch {
            val now = clockMillis()
            val lastAt = lastAcceptedAt
            val fresh = lastAt == null ||
                ((lastAcceptedId == null || lastAcceptedId != id) && now - lastAt > DEDUP_WINDOW_MILLIS)
            if (!fresh) {
                log("Push already handled; ignoring ${envelope::class.simpleName}.")
                return@launch
            }
            lastAcceptedId = id
            lastAcceptedAt = now
            pause(HANDLE_DELAY_MILLIS)
            dispatch(envelope)
        }
    }

    fun onAlertButton(button: PushAlertButton) {
        _uiState.update { it.copy(alert = null) }
        button.onClick()
    }

    fun closeQuestion() {
        _uiState.update { it.copy(question = null) }
    }

    private fun dispatch(envelope: PushEnvelope) {
        log("Handling push ${envelope::class.simpleName}.")
        when (envelope) {
            is PushEnvelope.LightningPayout -> handlePayout(envelope)
            PushEnvelope.HtlcIncoming -> handleHtlc(envelope)
            is PushEnvelope.Information ->
                question(envelope.headerText ?: PushStrings.OOPS, envelope.bodyText ?: PushStrings.BITTR_NOTIFICATION_FAIL)
            is PushEnvelope.HtlcExpired -> {
                pending = null
                question(envelope.headerText ?: PushStrings.HTLC_EXPIRED_TITLE, envelope.bodyText ?: PushStrings.HTLC_EXPIRED_BODY)
            }
            is PushEnvelope.Unknown -> question(PushStrings.OOPS, PushStrings.BITTR_NOTIFICATION_FAIL)
            is PushEnvelope.Swap -> delegate(envelope) { swapHandler?.onSwapPush(envelope) ?: log("No swap handler bound; swap push dropped.") }
            is PushEnvelope.LightningAddress ->
                delegate(envelope) { lnurlHandler?.onLightningAddressPush(envelope) ?: log("No LNURL handler bound; push dropped.") }
        }
    }

    private fun delegate(envelope: PushEnvelope, handle: suspend () -> Unit) {
        if (!signedIn || !synced) {
            pending = envelope
            if (!signedIn) wasNotified = true
            return
        }
        if (pending === envelope) pending = null
        scope.launch { handle() }
    }

    // ---- Lightning payout (`HandlePaymentNotification.swift:13-37, 144-303`). ----

    private fun handlePayout(push: PushEnvelope.LightningPayout) {
        pending = push
        when {
            !signedIn -> wasNotified = true
            !synced -> showLoading(TestID.Loading.syncingWallet, PushStrings.SYNCING_WALLET_3)
            !wasNotified -> alert(
                null,
                PushStrings.BITTR_PAYOUT,
                PushStrings.NEW_BITTR_PAYMENT,
                PushAlertButton(PushStrings.OKAY, dismisses = false) { triggerPayout() },
            )
            else -> triggerPayout()
        }
    }

    private fun triggerPayout() {
        wasNotified = false
        showLoading(TestID.Loading.receivingPayment, PushStrings.RECEIVING_PAYMENT)
        scope.launch {
            pause(1_000)
            facilitatePayout()
        }
    }

    private suspend fun facilitatePayout() {
        val push = pending as? PushEnvelope.LightningPayout
        val notificationId = push?.notificationId
        val amountMsat = push?.amountMsats ?: 0L
        if (notificationId == null || amountMsat <= 0L) {
            hideLoading()
            pending = null
            alert(null, PushStrings.BITTR_PAYOUT, PushStrings.BITTR_PAYOUT_FAIL, close())
            return
        }

        val pubkey = withContext(io) { signer.pubkey() }
        if (pubkey == null) {
            hideLoading()
            alert(null, PushStrings.BITTR_PAYOUT, PushStrings.BITTR_PAYOUT_FAIL_2, close(), retryPayout())
            return
        }

        if (!withContext(io) { node.isConnectedToBittr() }) {
            hideLoading()
            alert(
                null,
                PushStrings.BITTR_PAYOUT,
                PushStrings.COULDNT_CONNECT,
                close(),
                PushAlertButton(PushStrings.TRY_AGAIN, dismisses = false) {
                    scope.launch {
                        withContext(io) { node.reconnectToBittr() }
                        facilitatePayout()
                    }
                },
            )
            return
        }

        val invoice = withContext(io) { node.invoice(amountMsat, notificationId, INVOICE_EXPIRY_SECS) }
        val signature = invoice?.let { withContext(io) { signer.sign(notificationId) } }
        if (invoice == null || signature == null) {
            hideLoading()
            pending = null
            alert(null, PushStrings.BITTR_PAYOUT, PushStrings.BITTR_PAYOUT_FAIL, close())
            return
        }

        val outcome = withContext(io) {
            try {
                LightningPayout.parse(
                    http.execute(LightningPayout.request(environment, notificationId, invoice, signature, pubkey)),
                )
            } catch (e: Exception) {
                LightningPayout.Outcome.Error(LightningPayout.COULD_NOT_CONNECT)
            }
        }
        hideLoading()
        when (outcome) {
            // The payment itself arrives through the node; there is nothing left to replay.
            is LightningPayout.Outcome.Paid -> pending = null
            is LightningPayout.Outcome.ChannelFull -> channelFull(outcome, notificationId)
            is LightningPayout.Outcome.Processing -> alert(null, PushStrings.BITTR_PAYOUT, outcome.message, close())
            is LightningPayout.Outcome.TooLarge -> {
                alert(null, PushStrings.BITTR_PAYOUT, outcome.message, close())
                pending = null
            }
            is LightningPayout.Outcome.Error -> if ("try again" in outcome.message && pending != null) {
                alert(null, PushStrings.BITTR_PAYOUT, outcome.message, close(), retryPayout())
            } else {
                alert(null, PushStrings.BITTR_PAYOUT, outcome.message, close())
                pending = null
            }
        }
    }

    private fun retryPayout() = PushAlertButton(PushStrings.TRY_AGAIN, dismisses = false) {
        scope.launch { facilitatePayout() }
    }

    /** `handleChannelFullWithSwapSuggestion`. */
    private fun channelFull(outcome: LightningPayout.Outcome.ChannelFull, notificationId: String) {
        val suggested = outcome.suggestedSwapSats.toLongOrNull() ?: DEFAULT_SUGGESTED_SWAP_SATS
        val recommendation = PushStrings.CHANNEL_FULL_SWAP_RECOMMENDATION.replace("<amount>", outcome.suggestedSwapSats)
        alert(
            null,
            PushStrings.INSUFFICIENT_FUNDS,
            "${outcome.message}\n\n$recommendation",
            PushAlertButton(PushStrings.RECEIVE_ONCHAIN, dismisses = false) { receiveOnchain(notificationId) },
            PushAlertButton(PushStrings.SWAP_AND_RECEIVE_INSTANTLY, dismisses = false) {
                if (payoutSwap?.startSwapForPayout(notificationId, suggested) != true) {
                    alert(
                        null,
                        PushStrings.INSUFFICIENT_FUNDS,
                        PushStrings.SWAP_UNAVAILABLE,
                        PushAlertButton(PushStrings.RECEIVE_ONCHAIN, dismisses = false) { receiveOnchain(notificationId) },
                    )
                }
            },
        )
    }

    /** `receiveOnchainForNotification`. */
    private fun receiveOnchain(notificationId: String) {
        showLoading(TestID.Loading.receivingPayment, PushStrings.RECEIVING_PAYMENT)
        scope.launch {
            val pubkey = withContext(io) { signer.pubkey() }
            val failure: String? = if (pubkey == null) {
                PushStrings.WALLET_NOT_SYNCED
            } else {
                withContext(io) {
                    val signature = signer.sign(notificationId)
                    if (signature == null) {
                        LightningPayout.NO_DATA
                    } else {
                        try {
                            OnchainPayout.parse(http.execute(OnchainPayout.request(environment, notificationId, signature, pubkey)))
                        } catch (e: Exception) {
                            OnchainPayout.COULD_NOT_CONNECT
                        }
                    }
                }
            }
            hideLoading()
            if (failure == null) {
                pending = null
                alert(null, PushStrings.ONCHAIN_PAYOUT_SCHEDULED, PushStrings.ONCHAIN_PAYOUT_SCHEDULED_2, okay())
            } else {
                alert(null, PushStrings.ERROR, PushStrings.ONCHAIN_PAYOUT_FAIL.replace("<message>", failure), okay())
            }
        }
    }

    // ---- Incoming HTLC (`HandlePaymentNotification.swift:40-142`). ----

    private fun handleHtlc(push: PushEnvelope) {
        pending = push
        when {
            !signedIn -> wasNotified = true
            !synced -> showLoading(TestID.Loading.syncingWallet, PushStrings.SYNCING_WALLET_3)
            handlingHtlc -> log("Incoming HTLC already being handled; ignoring duplicate trigger.")
            else -> {
                handlingHtlc = true
                if (!wasNotified) {
                    alert(
                        TestID.Alert.incomingPayment,
                        PushStrings.INCOMING_PAYMENT,
                        PushStrings.NEW_BITTR_PAYMENT,
                        PushAlertButton(PushStrings.OKAY, dismisses = false) { triggerHtlcReady() },
                    )
                } else {
                    triggerHtlcReady()
                }
            }
        }
    }

    private fun triggerHtlcReady() {
        wasNotified = false
        showLoading(TestID.Loading.receivingPayment, PushStrings.RECEIVING_PAYMENT)
        pending = null
        scope.launch {
            pause(500)
            facilitateHtlcReady()
        }
    }

    private suspend fun facilitateHtlcReady() {
        val depositCode = withContext(io) { depositCodes.firstDepositCode() }?.takeIf { it.isNotEmpty() }
        val pubkey = depositCode?.let { withContext(io) { signer.pubkey() } }
        if (depositCode == null || pubkey == null) {
            hideLoading()
            handlingHtlc = false
            incomingPaymentAlert(if (depositCode == null) PushStrings.BITTR_PAYOUT_FAIL else PushStrings.BITTR_PAYOUT_FAIL_2)
            return
        }
        val timestamp = clockMillis() / 1_000
        val outcome = withContext(io) {
            val signature = signer.sign(HtlcReady.message(depositCode, timestamp))
            if (signature == null) {
                HtlcReady.Outcome.Failed(null)
            } else {
                try {
                    HtlcReady.parse(http.execute(HtlcReady.request(environment, depositCode, timestamp, pubkey, signature)))
                } catch (e: Exception) {
                    HtlcReady.Outcome.Failed(null)
                }
            }
        }
        hideLoading()
        handlingHtlc = false
        when (outcome) {
            // The payment completes through the node; no alert.
            HtlcReady.Outcome.Resumed -> Unit
            HtlcReady.Outcome.TimedOut -> incomingPaymentAlert(PushStrings.BITTR_PAYOUT_FAIL)
            is HtlcReady.Outcome.Failed -> incomingPaymentAlert(htlcReadyFriendlyMessage(outcome.code))
        }
    }

    private fun incomingPaymentAlert(message: String) =
        alert(TestID.Alert.incomingPayment, PushStrings.INCOMING_PAYMENT, message, close())

    // ---- Presentation. ----

    private fun question(title: String, answer: String) {
        _uiState.update { it.copy(question = PushQuestion(title = title.lowercase(), answer = answer)) }
    }

    private fun showLoading(testTag: String?, message: String) {
        _uiState.update { it.copy(loading = PushLoading(testTag, message)) }
    }

    private fun hideLoading() {
        _uiState.update { it.copy(loading = null) }
    }

    private fun alert(testTag: String?, title: String, message: String, vararg buttons: PushAlertButton) {
        _uiState.update { it.copy(alert = PushAlert(testTag, title, message, buttons.toList())) }
    }

    private fun close() = PushAlertButton(PushStrings.CLOSE, dismisses = true)

    private fun okay() = PushAlertButton(PushStrings.OKAY, dismisses = true)

    companion object {
        private const val TAG = "PushCoordinator"
        const val DEDUP_WINDOW_MILLIS = 10_000L
        const val HANDLE_DELAY_MILLIS = 1_000L
        private const val INVOICE_EXPIRY_SECS = 3_600
        private const val DEFAULT_SUGGESTED_SWAP_SATS = 50_000L

        /** `htlcReadyFriendlyMessage(forCode:)`: backend codes never reach the alert. */
        fun htlcReadyFriendlyMessage(code: String?): String =
            if (code == "no_held_htlc") PushStrings.HTLC_NO_HELD else PushStrings.BITTR_PAYOUT_FAIL_2
    }
}
