package com.bittr.android.core.swaps

import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/**
 * Boltz and the chain explorer, per build — `EnvironmentConfig.boltzBaseURL`, `webSocketURL` and
 * `esploraURL`. Development is bittr's regtest Boltz, production is Boltz's own.
 */
enum class BoltzEndpoints(
    val restBaseUrl: String,
    val webSocketUrl: String,
    /**
     * The Esplora host, without its `/api` path. Kept apart because the production host is a
     * `getbittr.com` subdomain: `ApiBaseUrlGuardTest` reserves `…getbittr.com/api` literals for
     * `BittrEnvironment`, and this is the chain explorer, not the bittr API.
     */
    private val esploraHost: String,
    val chain: SwapChain,
) {
    DEVELOPMENT("https://boltz-api.bittr.io/v2", "wss://boltz-api.bittr.io/v2/ws", "https://esplora-regtest.bittr.io", SwapChain.REGTEST),
    PRODUCTION("https://api.boltz.exchange/v2", "wss://api.boltz.exchange/v2/ws", "https://esplora.getbittr.com", SwapChain.MAINNET),
    ;

    /** `EnvironmentConfig.esploraURL`. */
    val esploraBaseUrl: String get() = esploraHost + ESPLORA_API_PATH

    companion object {
        private const val ESPLORA_API_PATH = "/api"

        fun forEnvironment(environment: BittrEnvironment): BoltzEndpoints =
            if (environment == BittrEnvironment.DEVELOPMENT) DEVELOPMENT else PRODUCTION
    }
}

/** What `POST /swap/submarine` answered, once its required fields are present. */
data class SubmarineCreated(
    val id: String,
    val address: String,
    val expectedAmount: Long,
    val claimPublicKey: String,
    val claimLeafOutput: String,
    val refundLeafOutput: String,
)

/** What `POST /swap/reverse` answered, once its required fields are present. */
data class ReverseCreated(
    val id: String,
    val invoice: String,
    val lockupAddress: String,
    val refundPublicKey: String,
    val claimLeafOutput: String,
    val refundLeafOutput: String,
)

/** A status from `GET /swap/{id}` or the websocket, with the lockup hex when Boltz sends one. */
data class SwapStatusUpdate(val status: String, val transactionHex: String?)

/** Boltz's nonce and partial signature for a claim or refund. */
data class BoltzPartialSignature(val pubNonce: String, val partialSignature: String)

/** Boltz answered with an error, or not at all. [message] is Boltz's own words when it gave any. */
class BoltzApiException(message: String) : Exception(message)

/**
 * The Boltz REST API, over the app's one [HttpClient] — `SwapManager`'s calls and `BoltzAPI.swift`.
 */
class BoltzApi(
    private val http: HttpClient,
    val endpoints: BoltzEndpoints,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {

    /** `fetchBoltzFeeQuote(reverse:)`. Null when the schedule is unavailable; validation then uses its fallback. */
    suspend fun feeQuote(reverse: Boolean): BoltzFeeQuote? {
        val body = get("${endpoints.restBaseUrl}/swap/${if (reverse) "reverse" else "submarine"}") ?: return null
        val fees = (body.obj("BTC")?.obj("BTC")?.obj("fees")) ?: return null
        val percentage = fees.num("percentage") ?: return null
        // Submarine quotes one miner fee; reverse breaks it into lockup and claim.
        val minerFee = when (val miner = fees["minerFees"]) {
            is JsonPrimitive -> miner.longOrNull ?: miner.doubleOrNull?.toLong() ?: 0
            is JsonObject -> miner.num("lockup")?.toLong() ?: miner.num("claim")?.toLong() ?: 0
            else -> 0
        }
        return BoltzFeeQuote(percentage, minerFee)
    }

    /** @throws BoltzApiException with Boltz's error, or [SwapCopy.SWAP_ERROR_2] when a field is missing. */
    suspend fun createSubmarine(invoice: String, refundPublicKey: String, webhookUrl: String): SubmarineCreated {
        val request = buildJsonObject {
            put("from", "BTC")
            put("to", "BTC")
            put("invoice", invoice)
            put("refundPublicKey", refundPublicKey)
            put("webhook", buildJsonObject { put("url", webhookUrl); put("hashSwapId", true) })
        }
        val body = post("${endpoints.restBaseUrl}/swap/submarine", request)
        val tree = body.obj("swapTree") ?: missing()
        return SubmarineCreated(
            id = body.str("id") ?: missing(),
            address = body.str("address") ?: missing(),
            expectedAmount = body.num("expectedAmount")?.toLong() ?: missing(),
            claimPublicKey = body.str("claimPublicKey") ?: missing(),
            claimLeafOutput = tree.obj("claimLeaf")?.str("output") ?: missing(),
            refundLeafOutput = tree.obj("refundLeaf")?.str("output") ?: missing(),
        )
    }

    /** @throws BoltzApiException with Boltz's error, or [SwapCopy.SWAP_ERROR_2] when a field is missing. */
    suspend fun createReverse(claimPublicKey: String, preimageHashHex: String, onchainAmountSats: Long, webhookUrl: String): ReverseCreated {
        val request = buildJsonObject {
            put("from", "BTC")
            put("to", "BTC")
            put("claimPublicKey", claimPublicKey)
            put("preimageHash", preimageHashHex)
            put("onchainAmount", onchainAmountSats)
            put(
                "webhook",
                buildJsonObject {
                    put("url", webhookUrl)
                    put("hashSwapId", true)
                    put("status", buildJsonArray { REVERSE_WEBHOOK_STATUSES.forEach { add(JsonPrimitive(it)) } })
                },
            )
        }
        val body = post("${endpoints.restBaseUrl}/swap/reverse", request)
        val tree = body.obj("swapTree") ?: missing()
        return ReverseCreated(
            id = body.str("id") ?: missing(),
            invoice = body.str("invoice") ?: missing(),
            lockupAddress = body.str("lockupAddress") ?: missing(),
            refundPublicKey = body.str("refundPublicKey") ?: missing(),
            claimLeafOutput = tree.obj("claimLeaf")?.str("output") ?: missing(),
            refundLeafOutput = tree.obj("refundLeaf")?.str("output") ?: missing(),
        )
    }

    /** `checkSwapStatus`. Null when Boltz could not be reached or sent no status. */
    suspend fun status(swapId: String): SwapStatusUpdate? = get("${endpoints.restBaseUrl}/swap/$swapId")?.let(::statusFrom)

    /** `POST /swap/reverse/{id}/claim`. */
    suspend fun requestClaim(swapId: String, unsignedTransactionHex: String, preimageHex: String, pubNonceHex: String): BoltzPartialSignature =
        partialSignature(
            post(
                "${endpoints.restBaseUrl}/swap/reverse/$swapId/claim",
                buildJsonObject {
                    put("index", 0)
                    put("transaction", unsignedTransactionHex)
                    put("preimage", preimageHex)
                    put("pubNonce", pubNonceHex)
                },
            ),
        )

    /** `POST /swap/submarine/{id}/refund`. */
    suspend fun requestRefund(swapId: String, unsignedTransactionHex: String, pubNonceHex: String): BoltzPartialSignature =
        partialSignature(
            post(
                "${endpoints.restBaseUrl}/swap/submarine/$swapId/refund",
                buildJsonObject {
                    put("pubNonce", pubNonceHex)
                    put("transaction", unsignedTransactionHex)
                    put("index", 0)
                },
            ),
        )

    /** `POST /chain/BTC/transaction`. The txid from `transactionId`, `txid` or `id`, or a bare string body. */
    suspend fun broadcast(transactionHex: String): String {
        val response = execute(HttpRequest(HttpMethod.POST, "${endpoints.restBaseUrl}/chain/BTC/transaction", buildJsonObject { put("hex", transactionHex) }.toString()))
        if (response.code != 200 && response.code != 201) throw BoltzApiException("HTTP ${response.code}: ${response.body}")
        val json = runCatching { Json.parseToJsonElement(response.body) }.getOrNull()
        return when (json) {
            is JsonObject -> json.str("transactionId") ?: json.str("txid") ?: json.str("id") ?: throw BoltzApiException(json.str("error") ?: "No transaction id")
            is JsonPrimitive -> json.contentOrNull ?: throw BoltzApiException("No transaction id")
            else -> response.body.trim().ifEmpty { throw BoltzApiException("No transaction id") }
        }
    }

    /**
     * `fetchRawTransactionHex`: a broadcast transaction's hex from Esplora, retried while it propagates
     * (6 tries, 1.5 s apart). The refund needs it to rebuild the lockup.
     */
    suspend fun rawTransactionHex(txid: String, retries: Int = 6): String? {
        repeat(retries) {
            val response = runCatching { http.execute(HttpRequest(HttpMethod.GET, "${endpoints.esploraBaseUrl}/tx/$txid/hex")) }.getOrNull()
            val hex = response?.takeIf { it.isSuccessful }?.body?.trim()
            if (!hex.isNullOrEmpty()) return hex
            pause(1_500)
        }
        return null
    }

    private suspend fun get(url: String): JsonObject? {
        val response = runCatching { http.execute(HttpRequest(HttpMethod.GET, url)) }.getOrNull() ?: return null
        return runCatching { Json.parseToJsonElement(response.body) as? JsonObject }.getOrNull()
    }

    /** POST, and throw Boltz's `error` when it sent one. */
    private suspend fun post(url: String, body: JsonObject): JsonObject {
        val response = execute(HttpRequest(HttpMethod.POST, url, body.toString()))
        val json = runCatching { Json.parseToJsonElement(response.body) as? JsonObject }.getOrNull()
        json?.str("error")?.let { throw BoltzApiException(it) }
        return json ?: throw BoltzApiException(if (response.isSuccessful) SwapCopy.SWAP_ERROR_2 else "HTTP ${response.code}")
    }

    private suspend fun execute(request: HttpRequest): HttpResponse =
        runCatching { http.execute(request) }.getOrElse { throw BoltzApiException(it.message ?: "Couldn't reach Boltz") }

    private fun partialSignature(body: JsonObject) = BoltzPartialSignature(
        pubNonce = body.str("pubNonce") ?: throw BoltzApiException("No nonce from Boltz"),
        partialSignature = body.str("partialSignature") ?: throw BoltzApiException("No partial signature from Boltz"),
    )

    private fun missing(): Nothing = throw BoltzApiException(SwapCopy.SWAP_ERROR_2)

    companion object {
        /** The statuses a reverse swap's webhook asks to be told about. */
        val REVERSE_WEBHOOK_STATUSES = listOf("transaction.mempool", "transaction.confirmed", "invoice.settled", "swap.expired", "transaction.failed")

        /** `{"op":"subscribe","channel":"swap.update","args":[id]}`. */
        fun subscribeMessage(swapId: String): String = buildJsonObject {
            put("op", "subscribe")
            put("channel", "swap.update")
            put("args", buildJsonArray { add(JsonPrimitive(swapId)) })
        }.toString()

        /** A websocket message's status, from `args[0]` — `WebSocketManager.handleReceivedMessage`. */
        fun parseSocketMessage(text: String): SwapStatusUpdate? {
            val json = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
            val first = (json["args"] as? JsonArray)?.firstOrNull() as? JsonObject ?: return null
            return statusFrom(first)
        }

        internal fun statusFrom(body: JsonObject): SwapStatusUpdate? {
            val status = body.str("status") ?: return null
            return SwapStatusUpdate(status, body.obj("transaction")?.str("hex"))
        }
    }
}

private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonObject.num(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull

@Suppress("unused")
private fun JsonElement.asObject(): JsonObject? = this as? JsonObject
