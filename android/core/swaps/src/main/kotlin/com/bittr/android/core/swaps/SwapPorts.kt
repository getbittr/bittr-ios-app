package com.bittr.android.core.swaps

import com.bittr.android.core.network.ApiResult
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.BoltzWebhook
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.UnixClock
import kotlinx.coroutines.flow.Flow

/** The active channel, as the swap screen reads it. */
data class SwapChannel(
    val channelValueSats: Long,
    val outboundSats: Long,
    val reserveSats: Long?,
    val counterpartyReserveSats: Long,
    /** `inboundHtlcMaximumMsat` — the most one payment can move. Null when the node does not say. */
    val inboundHtlcMaximumMsat: Long?,
)

/** A drain of the on-chain wallet: what would arrive and what it would cost. */
data class DrainPreview(val sendableSats: Long, val feeSats: Long)

enum class SwapPaymentState { Pending, Succeeded, Failed }

data class SwapPayment(val state: SwapPaymentState, val amountMsat: Long?)

/** A derived swap key, hex. `m/503'/0'/0'/0/<index>`. */
data class SwapKey(val privateKeyHex: String, val publicKeyHex: String)

/**
 * Everything a swap asks of the wallet. `:app` implements it over ldk-node, BDK and the fee
 * estimates; tests implement it with fixed answers.
 */
interface SwapWallet {

    /** BDK is open and has been scanned — iOS's `bdkWalletHasBeenScanned`. */
    fun onchainReady(): Boolean

    /** Waits for [onchainReady]; false when the scan failed or took too long. */
    suspend fun awaitOnchainReady(): Boolean

    fun activeChannel(): SwapChannel?

    /** `bittrWallet.satoshisOnchain`. */
    fun onchainBalanceSats(): Long

    /** `bittrWallet.satoshisOnchainSpendable`. */
    fun onchainSpendableSats(): Long

    /** The fastest fee estimate, sat/vB; null when estimates are unavailable. */
    suspend fun fastestFeeRate(): Double?

    /** The last rate the fee API returned, whole sat/vB. */
    fun lastKnownFeeRate(): Long?

    suspend fun drainPreview(address: String?, satPerVb: Long): DrainPreview?

    /** The vsize of paying [amountSats] to [address]. The failure's message is shown to the user. */
    suspend fun transactionVsize(address: String, amountSats: Long, satPerVb: Long): Result<Long>

    /** Whether a failure from [transactionVsize] means the wallet cannot cover the amount. */
    fun isInsufficientFunds(failure: Throwable): Boolean

    suspend fun createInvoice(amountMsat: Long, description: String, expirySecs: Int): String?

    suspend fun sendOnchain(address: String, amountSats: Long, satPerVb: Long): Result<String>

    suspend fun sendAllOnchain(address: String, satPerVb: Long): Result<String>

    /** Start paying [invoice] and return its payment id without waiting — a swap invoice is held until we claim. */
    suspend fun startPayment(invoice: String): Result<String>

    suspend fun payment(paymentId: String): SwapPayment?

    /** The next unused receive address — `onchainAddresses.getNextUnusedAddress()`. */
    suspend fun nextUnusedAddress(): String?

    suspend fun swapKey(index: Int): SwapKey

    /** `CacheManager.storeInvoiceDescription` — the label a transaction is shown with. */
    fun recordDescription(key: String, description: String)

    /** `CacheManager.storePaymentFees`. */
    fun recordPaymentFees(key: String, feesSats: Long)

    /** Sync the node and refresh balances. */
    suspend fun sync()

    /** The history id of the payment with [paymentHash], once it has shown up. */
    suspend fun transactionIdForPayment(paymentHash: String): String?
}

/** Where swap status updates come from while a swap is watched — Boltz's websocket in the app. */
fun interface SwapStatusFeed {
    /** Updates for [swapId]; the flow reconnects on its own until it is cancelled. */
    fun updates(swapId: String): Flow<SwapStatusUpdate>
}

/** The notification gate a swap passes before it is created: a push token and a signed webhook URL. */
interface SwapPushGate {
    suspend fun deviceToken(): String?

    /** The signed Boltz webhook URL, minted once per device token. Null when it could not be minted. */
    suspend fun webhookUrl(): String?
}

/**
 * **For the notifications port:** what a `swap_notification` push is handed to.
 *
 * `PushEnvelope.Swap(swapId, status)` goes straight here. [swapId] is Boltz's hashed id (the swap
 * file's stem, with `hashSwapId` on) or a plaintext id for older swaps; both resolve. The swap is
 * loaded, its status fetched, a claim or refund run if the status calls for one, and
 * `SwapCoordinator.events` emits `SwapEvent.ShowSwap` so an open screen can show the status card.
 * An unknown id is ignored. Safe to call before any screen exists.
 */
interface SwapPushHandler {
    suspend fun onSwapPush(swapId: String?, status: String?)
}

/** The cached webhook URL and the device token it was minted for. */
interface WebhookUrlCache {
    fun urlFor(deviceToken: String): String?
    fun store(url: String, deviceToken: String)
}

/**
 * [SwapPushGate] over the push token and the bittr backend — `SwapManager.boltzWebhookURL()`.
 *
 * The cached URL is reused only while it was minted for the current token and is the current URL
 * format (no `?`); otherwise a fresh one is minted with the node key's signature over
 * `boltz_webhook:<pubkey>:<timestamp>`.
 */
class BoltzWebhookMinter(
    private val environment: BittrEnvironment,
    private val http: HttpClient,
    private val signer: BittrRequestSigner,
    private val tokens: DeviceTokenSource,
    private val cache: WebhookUrlCache,
    private val clock: UnixClock = UnixClock.System,
) : SwapPushGate {

    override suspend fun deviceToken(): String? = runCatching { tokens.current() }.getOrNull()?.takeIf { it.isNotEmpty() }

    override suspend fun webhookUrl(): String? {
        val token = deviceToken() ?: return null
        cache.urlFor(token)?.takeIf { '?' !in it }?.let { return it }
        val signed = signer.signRequest(clock.nowSeconds()) { pubkey, timestamp -> BoltzWebhook.message(pubkey, timestamp) } ?: return null
        val response = runCatching { http.execute(BoltzWebhook.request(environment, signed)) }.getOrNull() ?: return null
        return when (val result = BoltzWebhook.parse(response, token)) {
            is ApiResult.Success -> result.value.url.also { cache.store(it, result.value.echoedDeviceToken ?: token) }
            is ApiResult.Failure -> null
        }
    }
}
