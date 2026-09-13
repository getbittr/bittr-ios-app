package com.bittr.android.core.push

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Turns an FCM data message into a [PushEnvelope].
 *
 * The wire shape is BIT-9 `api-contract` §3.2: an FCM `data` map is `string → string` only,
 * so nested objects and real types cannot survive it. The contract's answer is that `data`
 * carries **exactly one key** — the discriminator — whose value is the JSON-encoded string
 * of the object APNS would have carried natively:
 *
 * ```
 * { "data": { "htlc_notification": "{\"expired\":true,\"header_text\":\"…\"}" } }
 * ```
 *
 * So the input here is `RemoteMessage.getData()` and the decoder is the whole of the
 * translation. Nothing above it needs to know which transport the payload arrived on.
 *
 * ## Why this reads fields rather than deserialising into generated classes
 *
 * BIT-30 §2(c) committed Android to iOS's per-field behaviour: every field read in
 * `NotificationManager.swift:297-388` is individually optional *and* individually typed —
 * `notificationData["header_text"] as? String` yields nil for a field that is missing **and**
 * for a field that arrived as a number. `@Serializable` classes cannot express the second
 * half: a type mismatch on one field throws and takes the whole envelope with it, so a
 * backend that started sending `amount_msats` as `"1000"` would turn every LNURL push on
 * Android into a dropped message while iOS merely ignored the field.
 *
 * Reading the [JsonObject] field by field keeps the promise the sign-off actually made: the
 * backend can add, omit or re-type any field inside the five objects without an Android
 * release. Only the discriminator's value failing to be a JSON object is fatal, and that is
 * the one case §2(c) reserved.
 */
object PushEnvelopeDecoder {

    /**
     * The five discriminators, in the order iOS tests them
     * (`NotificationManager.swift:301-386`) — first one present wins. The order is
     * behaviour, not tidiness: a payload carrying two discriminators must resolve to the
     * same type on both platforms.
     *
     * Checked against FCM's reserved `data` keys (`from`, `message_type`, `notification`,
     * `collapse_key`, and the `google`/`gcm` prefixes) in BIT-30 §2 — all five are clear.
     */
    val DISCRIMINATORS: List<String> = listOf(
        "bittr_specific_data",
        "bittr_notification",
        "swap_notification",
        "htlc_notification",
        "lightning_address_notification",
    )

    private val json = Json {
        // Belt and braces: nothing below is deserialised into a class, so there is no
        // strict-schema path for an unknown key to fail on. Set anyway, because the day
        // someone adds a @Serializable DTO here is the day the default would bite.
        ignoreUnknownKeys = true
    }

    /** Decodes `RemoteMessage.getData()`. Never throws. */
    fun decode(data: Map<String, String>): PushEnvelope {
        val discriminator = DISCRIMINATORS.firstOrNull { data.containsKey(it) }
            ?: return PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NO_DISCRIMINATOR)

        val raw = data[discriminator]
            ?: return PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.MALFORMED_JSON)

        val element = runCatching { json.parseToJsonElement(raw) }.getOrNull()
            ?: return PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.MALFORMED_JSON)

        val obj = element as? JsonObject
            ?: return PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NOT_AN_OBJECT)

        return when (discriminator) {
            "bittr_specific_data" -> PushEnvelope.LightningPayout(
                notificationId = obj.optString("notification_id"),
                amountMsats = BitcoinAmount.btcStringToMsats(obj.optString("bitcoin_amount")),
            )

            "bittr_notification" -> PushEnvelope.Information(
                // Null rather than iOS's "oops" / `bittrnotificationfail` substitutions.
                // Those are copy, and copy on Android lives behind the string catalogue the
                // BIT-12 guard tests police, not inside a decoder in a module with no
                // resources on its classpath. The presentation layer substitutes.
                headerText = obj.optString("header_text"),
                bodyText = obj.optString("body_text"),
            )

            "swap_notification" -> PushEnvelope.Swap(
                swapId = obj.optString("swap_id"),
                status = obj.optString("status"),
            )

            // `expired` absent, false, or present as something that is not a boolean all
            // land on incoming — iOS's `as? Bool == true` is false in each of those cases
            // (`NotificationManager.swift:344-352`), and its fallback branch at :350 sends a
            // non-dictionary `htlc_notification` the same way. BIT-30 §2(c) restated this as
            // "`expired` defaults to `false`".
            "htlc_notification" -> if (obj.optBoolean("expired") == true) {
                PushEnvelope.HtlcExpired(
                    headerText = obj.optString("header_text"),
                    bodyText = obj.optString("body_text"),
                    timeSent = obj.optString("time_sent"),
                )
            } else {
                PushEnvelope.HtlcIncoming
            }

            "lightning_address_notification" -> PushEnvelope.LightningAddress(
                // Long. See PushEnvelope.LightningAddress and BIT-30 §2(a).
                amountMsats = obj.optLong("amount_msats"),
                metadata = obj.optString("metadata"),
                timeSent = obj.optString("time_sent"),
                username = obj.optString("username"),
                endpoint = obj.optString("endpoint"),
            )

            else -> PushEnvelope.Unknown(PushEnvelope.Unknown.Reason.NO_DISCRIMINATOR)
        }
    }

    /**
     * A JSON string, or null if the field is absent, JSON null, or any non-string type.
     *
     * The non-string case is the one that matters and it is iOS's behaviour, not caution:
     * `as? String` on a number is nil there, so a field the backend re-types must read as
     * absent on both clients rather than as a stringified number on one of them.
     */
    private fun JsonObject.optString(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** A JSON number, or null if absent, JSON null, quoted, or any non-number type. */
    private fun JsonObject.optLong(key: String): Long? =
        (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull

    /** A JSON boolean, or null if absent, JSON null, quoted, or any non-boolean type. */
    private fun JsonObject.optBoolean(key: String): Boolean? =
        (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
}
