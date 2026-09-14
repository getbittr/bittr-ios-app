package com.bittr.android.core.swaps

import fr.acinq.bitcoin.Crypto
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** iOS's `SwapDirection`. */
enum class SwapDirection { OnchainToLightning, LightningToOnchain }

/**
 * One swap — iOS's `Swap` (`Swaps/Swap.swift`), as an immutable value.
 *
 * The fields are iOS's, one for one, because the swap file is written from them and that file
 * is the user's rescue artifact for Boltz: the same JSON keys on both platforms means the same
 * instructions work for both.
 */
data class Swap(
    val dateId: String = "",
    val direction: SwapDirection = SwapDirection.OnchainToLightning,
    val isSuggested: Boolean = false,
    val satoshisAmount: Long = 0,
    val createdInvoice: String? = null,
    /** The swap key, hex. Plaintext in the swap file on purpose — see [SwapJson]. */
    val privateKey: String? = null,
    val boltzId: String? = null,
    val boltzExpectedAmount: Long? = null,
    val onchainFees: Long? = null,
    val lightningFees: Long? = null,
    val feeHigh: Double? = null,
    /** Fee for our claim transaction, on lightning-to-onchain swaps. */
    val claimTransactionFee: Long? = null,
    // Onchain to Lightning
    val sentOnchainTransactionId: String? = null,
    val boltzOnchainAddress: String? = null,
    val refundPublicKey: String? = null,
    val claimLeafOutput: String? = null,
    val refundLeafOutput: String? = null,
    val claimPublicKey: String? = null,
    // Lightning to Onchain
    val preimage: String? = null,
    val destinationAddress: String? = null,
    val boltzInvoice: String? = null,
    val lockupTx: String? = null,
) {

    /**
     * Fees known up front. On lightning-to-onchain the claim fee is deliberately absent: it was
     * added to the amount asked of Boltz, so [onchainFees] — the invoice spread — already holds it.
     */
    val definiteFees: Long
        get() = if (direction == SwapDirection.LightningToOnchain) {
            onchainFees ?: 0
        } else {
            (onchainFees ?: 0) + (lightningFees ?: 0) + (claimTransactionFee ?: 0)
        }

    /** The routing fee a lightning-to-onchain payment may cost at most. */
    val maximumRoutingFee: Long
        get() = if (direction == SwapDirection.LightningToOnchain) lightningFees ?: 0 else 0

    /** A route costs at least 1 sat whenever one is needed. */
    val minimumTotalFees: Long get() = definiteFees + if (maximumRoutingFee > 0) 1 else 0

    val maximumTotalFees: Long get() = definiteFees + maximumRoutingFee

    /** Only when the two ends differ — "between X and X" reads as a bug, not a range. */
    val hasVariableFee: Boolean get() = minimumTotalFees < maximumTotalFees

    /** `formattedTotalFees()`: "1 234" or "1 234 - 1 290". */
    fun formattedTotalFees(): String =
        if (hasVariableFee) "${SwapAmounts.group(minimumTotalFees)} - ${SwapAmounts.group(maximumTotalFees)}"
        else SwapAmounts.group(maximumTotalFees)

    companion object {
        /**
         * SHA-256 (lower-case hex) of a Boltz swap id: the value Boltz puts in a `hashSwapId`
         * webhook, and the name the swap file is stored under. iOS's `hashedSwapID`.
         */
        fun hashedId(boltzId: String): String = Crypto.sha256(boltzId.toByteArray(Charsets.UTF_8)).toHex()
    }
}

/**
 * The swap file's JSON — iOS's `Swap.toDictionary()` / `NSDictionary.toSwap()`.
 *
 * Absent values are left out rather than written as null, as `setValue(nil, forKey:)` removes the
 * key. Reading is tolerant: a missing or mistyped key keeps the default.
 */
object SwapJson {

    private val pretty = Json { prettyPrint = true }

    fun encode(swap: Swap): String = pretty.encodeToString(JsonObject.serializer(), toJson(swap))

    fun toJson(swap: Swap): JsonObject = buildJsonObject {
        put("dateID", swap.dateId)
        put("onchainToLightning", swap.direction == SwapDirection.OnchainToLightning)
        put("satoshisAmount", swap.satoshisAmount)
        put("isSuggested", swap.isSuggested)
        swap.createdInvoice?.let { put("createdInvoice", it) }
        swap.privateKey?.let { put("privateKey", it) }
        swap.boltzId?.let { put("boltzID", it) }
        swap.boltzExpectedAmount?.let { put("boltzExpectedAmount", it) }
        swap.onchainFees?.let { put("onchainFees", it) }
        swap.lightningFees?.let { put("lightningFees", it) }
        swap.feeHigh?.let { put("feeHigh", it) }
        swap.claimTransactionFee?.let { put("claimTransactionFee", it) }
        swap.sentOnchainTransactionId?.let { put("sentOnchainTransactionID", it) }
        swap.boltzOnchainAddress?.let { put("boltzOnchainAddress", it) }
        swap.refundPublicKey?.let { put("refundPublicKey", it) }
        swap.claimLeafOutput?.let { put("claimLeafOutput", it) }
        swap.refundLeafOutput?.let { put("refundLeafOutput", it) }
        swap.claimPublicKey?.let { put("claimPublicKey", it) }
        swap.preimage?.let { put("preimage", it) }
        swap.destinationAddress?.let { put("destinationAddress", it) }
        swap.boltzInvoice?.let { put("boltzInvoice", it) }
        swap.lockupTx?.let { put("lockupTx", it) }
    }

    fun decode(text: String): Swap? = runCatching { fromJson(Json.parseToJsonElement(text).jsonObject) }.getOrNull()

    fun fromJson(json: JsonObject): Swap {
        fun string(key: String) = (json[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        fun long(key: String) = (json[key] as? JsonPrimitive)?.takeIf { !it.isString }?.let { it.longOrNull ?: it.doubleOrNull?.toLong() }
        fun bool(key: String) = (json[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        return Swap(
            dateId = string("dateID") ?: "",
            direction = if (bool("onchainToLightning") == false) SwapDirection.LightningToOnchain else SwapDirection.OnchainToLightning,
            isSuggested = bool("isSuggested") ?: false,
            satoshisAmount = long("satoshisAmount") ?: 0,
            createdInvoice = string("createdInvoice"),
            privateKey = string("privateKey"),
            boltzId = string("boltzID"),
            boltzExpectedAmount = long("boltzExpectedAmount"),
            onchainFees = long("onchainFees"),
            lightningFees = long("lightningFees"),
            feeHigh = (json["feeHigh"] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull,
            claimTransactionFee = long("claimTransactionFee"),
            sentOnchainTransactionId = string("sentOnchainTransactionID"),
            boltzOnchainAddress = string("boltzOnchainAddress"),
            refundPublicKey = string("refundPublicKey"),
            claimLeafOutput = string("claimLeafOutput"),
            refundLeafOutput = string("refundLeafOutput"),
            claimPublicKey = string("claimPublicKey"),
            preimage = string("preimage"),
            destinationAddress = string("destinationAddress"),
            boltzInvoice = string("boltzInvoice"),
            lockupTx = string("lockupTx"),
        )
    }

    internal fun JsonObject.stringAt(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    internal fun JsonObject.primitive(key: String): JsonPrimitive? = this[key]?.let { runCatching { it.jsonPrimitive }.getOrNull() }
}
