package com.bittr.android.core.network

import java.net.URLEncoder

/**
 * The three calls a bittr push leads to — iOS's `BittrService.htlcReady`,
 * `payoutLightning` and `markTransactionAsOnchain` (`Helpers/BittrService.swift`).
 *
 * Request builders and response parsers only, like [DeviceTokenPatch]: the app sends
 * them through its one [HttpClient] and decides what the user sees.
 */
object HtlcReady {

    private const val PATH = "htlc-interceptor/ready"

    /** What is signed: `htlc_ready:<deposit_code>:<timestamp>` (`HandlePaymentNotification.swift:95`). */
    fun message(depositCode: String, timestamp: Long): String = "htlc_ready:$depositCode:$timestamp"

    fun request(
        environment: BittrEnvironment,
        depositCode: String,
        timestamp: Long,
        pubkey: String,
        signature: String,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "deposit_code" to BittrEnvelope.str(depositCode),
                "timestamp" to BittrEnvelope.num(timestamp),
                "pubkey" to BittrEnvelope.str(pubkey),
                "signature" to BittrEnvelope.str(signature),
            ),
        ),
    )

    /** How the attempt ended, in the three shapes `facilitateHTLCReady` branches on. */
    sealed interface Outcome {
        /** `success && action == "resumed"`: the payment is on its way; no alert. */
        data object Resumed : Outcome

        /** `success && action == "failed_timeout"`. */
        data object TimedOut : Outcome

        /** Anything else. [code] is the backend's `error`, null when there was none to read. */
        data class Failed(val code: String?) : Outcome
    }

    /**
     * iOS decodes the body before looking at the status, so an unreadable body is a
     * failure with no code whatever the status, and a non-2xx carries its `error`.
     */
    fun parse(response: HttpResponse): Outcome {
        val root = BittrEnvelope.parse(response.body) ?: return Outcome.Failed(null)
        val success = BittrEnvelope.boolean(root, "success") ?: return Outcome.Failed(null)
        val error = BittrEnvelope.string(root, "error")
        if (!response.isSuccessful) return Outcome.Failed(error ?: "Unknown error")
        val action = BittrEnvelope.string(root, "action")
        return when {
            success && action == "resumed" -> Outcome.Resumed
            success && action == "failed_timeout" -> Outcome.TimedOut
            else -> Outcome.Failed(error)
        }
    }
}

/** `POST /payout/lightning` — the payout a `bittr_specific_data` push asks for. */
object LightningPayout {

    private const val PATH = "payout/lightning"

    /** `payoutLightning`'s transport-failure copy, which is also its only non-2xx copy. */
    const val COULD_NOT_CONNECT =
        "Couldn't connect to Bittr to complete payout. Please try again or check your connection."

    /** Empty body, everything in the query — iOS's `URLComponents.queryItems`. */
    fun request(
        environment: BittrEnvironment,
        notificationId: String,
        invoice: String,
        signature: String,
        pubkey: String,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH) + query(
            "notification_id" to notificationId,
            "invoice" to invoice,
            "signature" to signature,
            "pubkey" to pubkey,
        ),
    )

    sealed interface Outcome {
        /** Paid. The payment itself arrives through the node. */
        data class Paid(val preimage: String) : Outcome

        /** `CHANNEL_FULL` with a suggestion: offer on-chain or a swap. */
        data class ChannelFull(val message: String, val suggestedSwapSats: String) : Outcome

        /** `PAYMENT_PROCESSING`: committed and ambiguous. Never offer a retry. */
        data class Processing(val message: String) : Outcome

        /** `PAYMENT_TOO_LARGE`: permanent. */
        data class TooLarge(val message: String) : Outcome

        /** `serverError` and friends: [message] is shown as-is; "try again" in it earns a retry. */
        data class Error(val message: String) : Outcome
    }

    fun parse(response: HttpResponse): Outcome {
        if (!response.isSuccessful) return Outcome.Error(COULD_NOT_CONNECT)
        val root = BittrEnvelope.parse(response.body)
        val success = root?.let { BittrEnvelope.boolean(it, "success") }
        if (root == null || success == null) return Outcome.Error(DECODING_FAILED)
        val error = BittrEnvelope.string(root, "error")
        if (success) {
            val preimage = BittrEnvelope.string(root, "pre_image") ?: return Outcome.Error(NO_DATA)
            return Outcome.Paid(preimage)
        }
        return when (BittrEnvelope.string(root, "error_code")) {
            "CHANNEL_FULL" -> BittrEnvelope.string(root, "suggested_swap_amount")
                ?.let { Outcome.ChannelFull(error ?: "Lightning channel capacity insufficient", it) }
                ?: Outcome.Error(error ?: "Unknown error")
            "PAYMENT_PROCESSING" ->
                Outcome.Processing(error ?: "Your payment is being processed and should complete shortly.")
            "PAYMENT_TOO_LARGE" -> Outcome.TooLarge(error ?: "This payment is too large to process.")
            else -> Outcome.Error(error ?: "Unknown error")
        }
    }

    /** `BittrServiceError.decodingError`'s description. */
    const val DECODING_FAILED = "Failed to decode the server response."

    /** `BittrServiceError.noData`'s description. */
    const val NO_DATA = "No data received from the server."
}

/** `POST /payout/onchain` — "Receive on-chain" on the channel-full alert. */
object OnchainPayout {

    private const val PATH = "payout/onchain"

    const val COULD_NOT_CONNECT =
        "Couldn't connect to Bittr to mark transaction as on-chain. Please try again or check your connection."

    fun request(
        environment: BittrEnvironment,
        notificationId: String,
        signature: String,
        pubkey: String,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH) + query(
            "notification_id" to notificationId,
            "signature" to signature,
            "pubkey" to pubkey,
        ),
    )

    /** Null when scheduled, otherwise the message iOS puts into `onchainpayoutfail`. */
    fun parse(response: HttpResponse): String? {
        if (!response.isSuccessful) return COULD_NOT_CONNECT
        val root = BittrEnvelope.parse(response.body) ?: return LightningPayout.DECODING_FAILED
        val success = BittrEnvelope.boolean(root, "success") ?: return LightningPayout.DECODING_FAILED
        return if (success) null else BittrEnvelope.string(root, "error") ?: "Unknown error"
    }
}

private fun query(vararg items: Pair<String, String>): String =
    items.joinToString(separator = "&", prefix = "?") { (key, value) ->
        // `%20` rather than `+`: URLComponents percent-encodes spaces, and a zbase32
        // signature or an invoice never contains one anyway.
        "$key=" + URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
    }
