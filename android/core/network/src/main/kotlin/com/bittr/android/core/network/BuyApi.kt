package com.bittr.android.core.network

import com.bittr.android.core.push.SignedRequestMessage
import java.net.URLEncoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * The Buy and bittr-signup endpoints that `CustomerApi.kt` does not already cover: the 2FA check,
 * the deposit-code refresh, the payout-mode switch and the purchase lookup that feeds Profits.
 *
 * ## Read the way iOS reads them
 *
 * iOS's `CallsManager.makeApiCall` hands back **any JSON object body as a success, whatever the
 * status code**, and each screen then looks for the keys it wants. So a `400` whose body is
 * `{"message": "Invalid 2FA verification token provided"}` reaches `Transfer2ViewController` as
 * a dictionary with a `message`, and it shows `verificationfail`. The parsers here take the same
 * view — a JSON object is read for its keys regardless of status — and only a response that is
 * not a JSON object at all is a failure. Doing it the `CustomerRegistration.parse` way (non-2xx
 * is a failure before the body is read) would turn the backend's own words into a generic error.
 */

private fun objectOf(response: HttpResponse): JsonObject? = BittrEnvelope.parse(response.body)

private fun q(value: String): String = URLEncoder.encode(value, "UTF-8")

/**
 * `POST /verify/email`, read the way `didSendDetailsToBittr` (`Transfer1ViewController.swift:404-436`)
 * reads it: any JSON body is an answer, and only `success: false` *with* a `message` rejects. The
 * request is [EmailVerification.request].
 */
object EmailVerificationAnswer {

    /** Null when the body is not a JSON object — iOS's `bittrsignupfail4`. */
    fun parse(response: HttpResponse): EmailVerification.Outcome? {
        val root = objectOf(response) ?: return null
        val message = BittrEnvelope.message(root)
        return if (BittrEnvelope.isExplicitFailure(root) && message != null) {
            EmailVerification.Outcome.Rejected(message)
        } else {
            EmailVerification.Outcome.Accepted
        }
    }
}

/**
 * `POST /verify/email/check2fa` — `Transfer2ViewController.sendCodeToBittr` (`:216-289`).
 */
object EmailCheck2fa {

    private const val PATH = "verify/email/check2fa"

    /** The one server string iOS matches on, verbatim (`:272`). */
    const val INVALID_TOKEN_MESSAGE = "Invalid 2FA verification token provided"

    /**
     * @param lightningPubkey the node id, sent only when a node is up. The backend returns the
     *   recovery fields only when both the email and this pubkey match an existing customer.
     */
    fun request(
        environment: BittrEnvironment,
        email: String,
        code: String,
        lightningPubkey: String?,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "email_address" to BittrEnvelope.str(email),
                "token_2fa" to BittrEnvelope.str(code.trim()),
                "lightning_pubkey" to BittrEnvelope.str(lightningPubkey),
            ),
        ),
    )

    sealed interface Outcome {
        /**
         * The email is verified. [restoreDepositCode] and [restoreMessage] are the recovery pair a
         * returning customer gets back; when present, registration reuses the code and signs the
         * message verbatim.
         */
        data class Verified(
            val emailToken: String,
            val restoreDepositCode: String?,
            val restoreMessage: String?,
        ) : Outcome

        /** `verificationfail`. */
        data object InvalidCode : Outcome

        /** `transfer15vc2` with `<error>` = [message], or `"unavailable."` when null. */
        data class Error(val message: String?) : Outcome
    }

    fun parse(response: HttpResponse): Outcome? {
        val root = objectOf(response) ?: return null
        val token = BittrEnvelope.string(root, "token")
        val message = BittrEnvelope.string(root, "message")
        return when {
            token != null -> Outcome.Verified(
                emailToken = token,
                restoreDepositCode = BittrEnvelope.string(root, "deposit_code"),
                restoreMessage = message,
            )
            message == INVALID_TOKEN_MESSAGE -> Outcome.InvalidCode
            else -> Outcome.Error(message)
        }
    }
}

/**
 * `POST /customer`, read the way `Transfer2ViewController.createBittrAccount` (`:393-461`) reads
 * it. The request is [CustomerRegistration.request]; this is only the screen's reading of the
 * answer, which needs `lightning_address_username` and the server `message` that
 * `CustomerRegistration.parse` does not surface.
 */
object CustomerSignup {

    /** The message iOS matches for `bittrsignupfail2` (`:451`). */
    const val INVALID_IBAN_MESSAGE = "Unable to create customer account (invalid iban)"

    sealed interface Outcome {
        data class Created(
            val ourIban: String,
            val depositCode: String,
            val ourSwift: String,
            val lightningAddressUsername: String,
        ) : Outcome

        /** `bittrsignupfail2` — back to the IBAN page. */
        data object InvalidIban : Outcome

        /** `bittrsignupfail3 (<message>.)` — back to the IBAN page. */
        data class Message(val message: String) : Outcome

        /** A JSON body with neither the data nor a message. iOS shows nothing; see the screen. */
        data object Unrecognised : Outcome
    }

    fun parse(response: HttpResponse): Outcome? {
        val root = objectOf(response) ?: return null
        val data = root["data"] as? JsonObject
        val iban = data?.let { BittrEnvelope.string(it, "iban") }
        val code = data?.let { BittrEnvelope.string(it, "deposit_code") }
        val swift = data?.let { BittrEnvelope.string(it, "swift") }
        if (iban != null && code != null && swift != null) {
            return Outcome.Created(
                ourIban = iban,
                depositCode = code,
                ourSwift = swift,
                lightningAddressUsername = BittrEnvelope.string(data, "lightning_address_username").orEmpty(),
            )
        }
        val message = BittrEnvelope.string(root, "message") ?: return Outcome.Unrecognised
        return if (message == INVALID_IBAN_MESSAGE) Outcome.InvalidIban else Outcome.Message(message)
    }
}

/**
 * `GET /deposit_code` — `BuyViewController.getDepositCodeData` (`:222-265`), which refreshes the
 * partner details behind a deposit code each time Buy opens.
 */
object DepositCodeFetch {

    private const val PATH = "deposit_code"

    /** The signed string, `deposit_codes:<pubkey>:<timestamp>` (`:229`). */
    fun message(pubkey: String, timestamp: Long): String = SignedRequestMessage.depositCodes(pubkey, timestamp)

    fun request(environment: BittrEnvironment, signed: SignedRequest): HttpRequest = HttpRequest(
        method = HttpMethod.GET,
        url = environment.url(PATH) +
            "?timestamp=${signed.timestampSeconds}" +
            "&signature=${q(signed.signature)}" +
            "&pubkey=${q(signed.pubkey)}",
    )

    data class Details(
        val depositCode: String,
        val ourIban: String,
        val ourSwift: String,
        /** Null when absent; iOS then keeps what it had (`:302`). */
        val lightningAddressUsername: String?,
        val paymentMode: String?,
    )

    /** Null for anything but a `data` object carrying code, iban and swift (`:285-292`). */
    fun parse(response: HttpResponse): Details? {
        val data = objectOf(response)?.get("data") as? JsonObject ?: return null
        return Details(
            depositCode = BittrEnvelope.string(data, "deposit_code") ?: return null,
            ourIban = BittrEnvelope.string(data, "iban") ?: return null,
            ourSwift = BittrEnvelope.string(data, "swift") ?: return null,
            lightningAddressUsername = BittrEnvelope.string(data, "lightning_address_username"),
            paymentMode = BittrEnvelope.string(data, "payment_mode"),
        )
    }
}

/** The two payout modes the backend accepts. iOS's switch: ON is lightning, OFF is onchain. */
object PaymentMode {
    const val LIGHTNING = "lightning"
    const val ONCHAIN = "onchain"
}

/**
 * `PATCH /customer/payment-mode` — `BuyViewController.proceedWithApiCall` (`:328-385`).
 */
object PaymentModePatch {

    private const val PATH = "customer/payment-mode"

    fun message(pubkey: String, depositCode: String, mode: String, timestamp: Long): String =
        SignedRequestMessage.paymentMode(pubkey, depositCode, mode, timestamp)

    fun request(
        environment: BittrEnvironment,
        depositCode: String,
        mode: String,
        signed: SignedRequest,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.PATCH,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "deposit_code" to BittrEnvelope.str(depositCode),
                "payment_mode" to BittrEnvelope.str(mode),
                "pubkey" to BittrEnvelope.str(signed.pubkey),
                "signature" to BittrEnvelope.str(signed.signature),
                "timestamp" to BittrEnvelope.num(signed.timestampSeconds),
            ),
        ),
    )

    sealed interface Outcome {
        data class Confirmed(val mode: String) : Outcome

        /** `error`, else `message`, else "Unknown error" (`:368`). */
        data class ServerError(val message: String) : Outcome {
            /** iOS retries once, with a fresh timestamp, on this (`:374`). */
            val isExpiredTimestamp: Boolean get() = message.lowercase().contains("expired timestamp")
        }
    }

    fun parse(response: HttpResponse): Outcome? {
        val root = objectOf(response) ?: return null
        val confirmed = (root["data"] as? JsonObject)?.let { BittrEnvelope.string(it, "payment_mode") }
        if (confirmed != null) return Outcome.Confirmed(confirmed)
        return Outcome.ServerError(
            BittrEnvelope.string(root, "error") ?: BittrEnvelope.string(root, "message") ?: "Unknown error",
        )
    }
}

/** One row of `GET /transaction_info` — iOS's `BittrTransaction`. */
data class BittrTransactionInfo(
    val txId: String,
    val transferType: String?,
    val historicalExchangeRate: Double?,
    val datetime: String?,
    /** `"EUR"` or `"CHF"`. */
    val currency: String?,
    /** BTC, as a decimal. */
    val bitcoinAmount: Double?,
    val fiatAmountNet: Double?,
    val fiatAmountGross: Double?,
)

/**
 * `GET /transaction_info` — `BittrService.fetchBittrTransactions` (`:79-137`). Asks which of the
 * wallet's received transactions were bittr purchases, and for how much fiat.
 */
object TransactionInfo {

    private const val PATH = "transaction_info"

    /** The signed string: the deposit codes then the tx ids, each comma-joined, concatenated. */
    fun message(txIds: List<String>, depositCodes: List<String>): String =
        depositCodes.joinToString(",") + txIds.joinToString(",")

    fun request(
        environment: BittrEnvironment,
        txIds: List<String>,
        depositCodes: List<String>,
        pubkey: String,
        signature: String,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.GET,
        url = environment.url(PATH) +
            "?tx_ids=${q(txIds.joinToString(","))}" +
            "&deposit_codes=${q(depositCodes.joinToString(","))}" +
            "&signature=${q(signature)}" +
            "&pubkey=${q(pubkey)}",
    )

    /**
     * The purchases, or null when the call did not succeed. iOS requires a 2xx and
     * `success == true` here (it decodes with `JSONDecoder`, not `makeApiCall`).
     */
    fun parse(response: HttpResponse): List<BittrTransactionInfo>? {
        if (!response.isSuccessful) return null
        val root = objectOf(response) ?: return null
        if (BittrEnvelope.boolean(root, "success") != true) return null
        val rows = root["data"] as? JsonArray ?: return null
        return rows.mapNotNull { element ->
            val row = element as? JsonObject ?: return@mapNotNull null
            BittrTransactionInfo(
                txId = BittrEnvelope.string(row, "tx_id") ?: return@mapNotNull null,
                transferType = BittrEnvelope.string(row, "transfer_type"),
                historicalExchangeRate = number(row, "historical_exchange_rate"),
                datetime = BittrEnvelope.string(row, "datetime"),
                currency = BittrEnvelope.string(row, "currency"),
                bitcoinAmount = number(row, "bitcoin_amount"),
                fiatAmountNet = number(row, "fiat_amount_net"),
                fiatAmountGross = number(row, "fiat_amount_gross"),
            )
        }
    }

    /** A number sent either as a JSON number or as a numeric string. */
    private fun number(obj: JsonObject, key: String): Double? {
        val primitive = obj[key] as? JsonPrimitive ?: return null
        return primitive.doubleOrNull ?: primitive.content.toDoubleOrNull()
    }
}
