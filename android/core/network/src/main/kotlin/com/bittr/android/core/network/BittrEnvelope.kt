package com.bittr.android.core.network

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * Either the value an endpoint promised, or a placed [ApiFailure].
 *
 * A deliberately small type rather than `kotlin.Result`: the failure side has to be an
 * [ApiFailure] and not a `Throwable`, because the whole point of `api-contract` §2.3 rules 3-4
 * is that these failures carry a *behaviour*, and a thrown exception at a call site is exactly
 * where that behaviour gets flattened back into "something went wrong".
 */
sealed interface ApiResult<out T> {

    data class Success<T>(val value: T) : ApiResult<T>

    data class Failure(val failure: ApiFailure) : ApiResult<Nothing>

    /** The value, or null on failure. For call sites where the failure is handled elsewhere. */
    fun valueOrNull(): T? = (this as? Success)?.value

    /** The failure, or null on success. */
    fun failureOrNull(): ApiFailure? = (this as? Failure)?.failure
}

/**
 * The two response shapes this API actually uses, and the tolerant reads over them.
 *
 * There are two, not one, and both are observed rather than specified — the contract documents
 * fields, and the shipping iOS client is the only description of the wrapper around them:
 *
 * ```
 * POST /customer            { "data": { "deposit_code": …, "push_channel": … } }
 * POST /verify/email        { "success": false, "message": "…" }   // and a 2xx on the happy path
 * GET  /boltz/webhook-token { "success": true, "url": …, "device_token": … }
 * ```
 *
 * `Transfer2ViewController.swift:410` reads the first, `Transfer1ViewController.swift:422` the
 * second, `SwapManager.swift:68-73` the third.
 *
 * ## Every read here is tolerant, and that is a contract commitment
 *
 * §2.1's entire argument for adding `push_channel` additively is that the shipping iOS build
 * *"reads `data` key by key with optional casts and already tolerates unknown keys"* — it reads
 * `lightning_address_username` as `as? String ?? ""`. An Android client that deserialised into
 * a strict data class would turn the backend's next additive field into an Android outage, and
 * would retroactively make §2.1's promise untrue for one of the two clients it was made to.
 *
 * So: unknown keys are ignored, absent keys are null, and a field of the wrong JSON type reads
 * as null rather than throwing. The same rule [com.bittr.android.core.push.PushEnvelopeDecoder]
 * applies to the push payload, for the same reason.
 */
object BittrEnvelope {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * Parses a response body into a [JsonObject], or null when it is not one.
     *
     * Null covers an empty body, a JSON array, a bare string, and HTML from a captive portal —
     * all of which are "not the answer" rather than "an answer we disagree with".
     */
    fun parse(body: String): JsonObject? = runCatching {
        json.parseToJsonElement(body).jsonObject
    }.getOrNull()

    /**
     * The `data` sub-object, or the root when there is none.
     *
     * Falling back to the root rather than to null is what lets one reader serve both
     * `POST /customer` (which wraps) and `PATCH /customer/device-token` (whose wrapper is
     * unspecified — §2.3 says only that the response *"carries the same `push_channel` /
     * `push_channel_reason` pair"*, without saying at what depth). Reading both depths means
     * this client works against either choice the backend makes, instead of working against one
     * and failing silently — with `push_channel` reading as null, i.e. an unrecognised channel —
     * against the other.
     */
    fun data(root: JsonObject): JsonObject =
        (root["data"] as? JsonObject) ?: root

    /** A string field, or null when absent, null, or not a string. */
    fun string(obj: JsonObject, key: String): String? =
        (obj[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** A boolean field, or null when absent or not a boolean. */
    fun boolean(obj: JsonObject, key: String): Boolean? =
        (obj[key] as? JsonPrimitive)?.booleanOrNull

    /** A 64-bit integer field, or null when absent or not an integer. */
    fun long(obj: JsonObject, key: String): Long? =
        (obj[key] as? JsonPrimitive)?.longOrNull

    /**
     * `success: false` as the iOS client reads it (`Transfer1ViewController.swift:422-424`).
     *
     * Note the polarity: **absent means success.** `POST /customer` does not send the field at
     * all on the happy path, so treating absence as failure would fail every good registration.
     * Only an explicit `false` is a rejection.
     */
    fun isExplicitFailure(root: JsonObject): Boolean = boolean(root, "success") == false

    /**
     * The human-readable rejection message, for the one place iOS shows the server's own words
     * rather than a localised string (`Transfer1ViewController.swift:427` — IBAN validation).
     */
    fun message(root: JsonObject): String? = string(root, "message")

    /**
     * The machine-readable error slug, looked for under every key this API might plausibly use.
     *
     * Four keys rather than one because the error vocabulary is not pinned anywhere — §8 q6
     * records that the backend repo cannot be read from here — and looking in one place would
     * mean a slug the backend *does* send silently failing to classify. The order is
     * most-specific first. `SwapManager.swift:74` reads `error` as a string, which is the only
     * one of the four with any evidence behind it.
     *
     * Deliberately does **not** fall back to [message]: that field holds prose meant for a
     * customer ("This IBAN could not be validated"), and feeding prose to
     * [ApiFailure.classify] would match a slug set by accident one day.
     */
    fun errorSlug(root: JsonObject): String? =
        string(root, "error_code")
            ?: string(root, "code")
            ?: string(root, "error")
            ?: string(root, "reason")

    /**
     * Reads a non-2xx [HttpResponse] into a placed [ApiFailure].
     *
     * The body is parsed for a slug on a best-effort basis; a body that is not JSON at all
     * still classifies, as [ApiFailure.Unclassified] with a null slug.
     */
    fun failureFrom(response: HttpResponse): ApiFailure =
        ApiFailure.classify(response, parse(response.body)?.let(::errorSlug))

    /**
     * Serialises a request body, dropping every null value.
     *
     * Dropping rather than emitting `null` is load-bearing on exactly one field.
     * §2.1 makes `category: "android"` with **no** `android_device_token` an ordinary,
     * accepted registration — FCM token retrieval is async and can legitimately miss the signup
     * call — so the absent case has to be genuinely absent rather than a JSON null the backend
     * has no row for in §4.2's table. (§4.2 pairs "field absent or `""`" under one reason,
     * `missing`; a literal null is neither.)
     */
    fun body(fields: Map<String, JsonElement?>): String =
        json.encodeToString(
            JsonObject.serializer(),
            JsonObject(fields.filterValues { it != null && it !is kotlinx.serialization.json.JsonNull }.mapValues { it.value!! }),
        )

    /** Convenience for [body] — a string field. */
    fun str(value: String?): JsonElement? = value?.let { JsonPrimitive(it) }

    /** Convenience for [body] — a numeric field. */
    fun num(value: Long?): JsonElement? = value?.let { JsonPrimitive(it) }

    /**
     * Reads the `push_channel` / `push_channel_reason` pair out of a response body.
     *
     * Shared by `POST /customer` (§2.1) and `PATCH /customer/device-token` (§2.3), which is the
     * point — §2.3 says the refresh *"re-runs the §4 validation, so the response carries the
     * same pair"*, and two readers would be two chances to diverge on the one field §4.3 keys
     * a customer's payout mode off.
     */
    fun pushChannelStatus(root: JsonObject): com.bittr.android.core.push.PushChannelStatus {
        val data = data(root)
        return com.bittr.android.core.push.PushChannelStatus.from(
            rawChannel = string(data, "push_channel"),
            rawReason = string(data, "push_channel_reason"),
        )
    }

    /** The raw JSON primitive read, exposed for tests that assert on the exact body bytes. */
    internal fun jsonPrimitiveOrNull(obj: JsonObject, key: String): JsonPrimitive? =
        runCatching { obj.getValue(key).jsonPrimitive }.getOrNull()
}
