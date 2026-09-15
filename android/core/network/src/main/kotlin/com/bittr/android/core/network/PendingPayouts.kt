package com.bittr.android.core.network

import java.math.BigDecimal
import java.math.RoundingMode
import java.net.URLEncoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/**
 * `GET /notifications` — Device details' "Pending payout" check
 * (`DeviceViewController.checkPendingPayout`). The payout notifications bittr still holds for
 * this node, so a customer whose push never arrived can collect the payout by hand.
 *
 * Request builder and parser only, like [LightningPayout]: the app signs, sends and decides
 * what the user sees.
 */
object PendingPayouts {

    private const val PATH = "notifications"

    /** What is signed: `notifications:<pubkey>:<timestamp>`. */
    fun message(pubkey: String, timestamp: Long): String = "notifications:$pubkey:$timestamp"

    fun request(environment: BittrEnvironment, timestamp: Long, signature: String, pubkey: String): HttpRequest =
        HttpRequest(
            method = HttpMethod.GET,
            url = environment.url(PATH) +
                "?timestamp=$timestamp&signature=${encode(signature)}&pubkey=${encode(pubkey)}",
        )

    sealed interface Outcome {
        /** No payout to handle — also every failure, which iOS shows the same `bittrpendingpayout2` for. */
        data object None : Outcome

        /** The newest complete notification: its id, and `transaction.bitcoin_amount` in millisatoshis. */
        data class Available(val notificationId: String, val amountMsats: Long) : Outcome
    }

    /**
     * `NSDictionary.toNotifications()` and the `guard` after it. Items are read in order and
     * reading **stops at the first incomplete one** (iOS's `break`), so a notification missing
     * `sent_at` hides the ones after it. The last complete one is the payout, provided its
     * `bitcoin_amount` is a string.
     */
    fun parse(response: HttpResponse): Outcome {
        val root = runCatching { Json.parseToJsonElement(response.body) }.getOrNull() as? JsonObject
            ?: return Outcome.None
        val data = root["data"] as? JsonArray ?: return Outcome.None
        val complete = data.takeWhile { it is JsonObject && it.isComplete() }.map { it as JsonObject }
        val last = complete.lastOrNull() ?: return Outcome.None
        val id = last.string("id") ?: return Outcome.None
        val bitcoinAmount = (last["transaction"] as JsonObject).string("bitcoin_amount") ?: return Outcome.None
        val msats = bitcoinToMsats(bitcoinAmount) ?: return Outcome.None
        return Outcome.Available(notificationId = id, amountMsats = msats)
    }

    private val REQUIRED_STRINGS = listOf("inserted_at", "sent_at", "status", "notification_type", "id", "last_attempt_at")

    private fun JsonObject.isComplete(): Boolean =
        REQUIRED_STRINGS.all { string(it) != null } &&
            (this["attempts_count"] as? JsonPrimitive)?.intOrNull != null &&
            this["transaction"] is JsonObject

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

    /** `toNumber().inSatoshis() * 1000`: a BTC decimal string to millisatoshis. */
    internal fun bitcoinToMsats(bitcoin: String): Long? = runCatching {
        BigDecimal(bitcoin.trim()).movePointRight(8).setScale(0, RoundingMode.HALF_UP).longValueExact() * 1000
    }.getOrNull()

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
}
