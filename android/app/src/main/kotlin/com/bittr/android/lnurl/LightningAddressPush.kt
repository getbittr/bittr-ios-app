package com.bittr.android.lnurl

import com.bittr.android.core.lnurl.LnurlEndpoint
import com.bittr.android.core.lnurl.LnurlEndpointCheck
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.push.PushEnvelope
import com.bittr.android.core.wallet.ldk.lightning.Bolt11DescriptionView
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Someone paying the user's Lightning address — `HandleLightningAddressNotification.swift`.
 *
 * bittr's server receives the payer's request for the address, and pushes
 * `lightning_address_notification` to the wallet: this answers it with an invoice whose description
 * hash commits to the pushed `metadata`, posted back to the pushed `endpoint`.
 *
 * **Binding for the notifications port:** implement its `LnurlPushHandler` by calling [step] to
 * choose what to show, and [handle] once the wallet is unlocked and synced (behind the
 * `generatinginvoice` loading card). A failure is `alert.paymentRequestFailed`
 * ([LightningAddressPushCopy.FAILED_TITLE] / [LightningAddressPushCopy.FAILED]) with Okay.
 */
class LightningAddressPush(
    private val lightning: LightningNodePort,
    private val http: HttpClient,
) {

    /** A push with every field `handleLightningAddressNotification` requires; iOS drops the rest. */
    data class Request(
        val amountMsats: Long,
        val metadata: String,
        val timeSent: String,
        val username: String,
        val endpoint: String,
    )

    /** What the app does with a push, given where the user is — the iOS branches, in order. */
    enum class Step {
        /** Locked: `alert.paymentRequest`, "Please sign in to accept the payment." [Okay]. Remember it. */
        AskToSignIn,

        /** Signed in, not synced: `loading.syncingWallet`; handle it again after `finalizeSync`. */
        WaitForSync,

        /** Synced, the push arrived while the app was open: `paymentrequest3` [Cancel, Handle now]. */
        AskHandleNow,

        /** Synced, and the user already agreed by signing in after [AskToSignIn]: handle it now. */
        HandleNow,
    }

    fun step(signedIn: Boolean, synced: Boolean, wasNotified: Boolean): Step = when {
        !signedIn -> Step.AskToSignIn
        !synced -> Step.WaitForSync
        wasNotified -> Step.HandleNow
        else -> Step.AskHandleNow
    }

    /** The push, or null when a field is missing — iOS's `guard let` drops it silently. */
    fun request(push: PushEnvelope.LightningAddress): Request? {
        val amount = push.amountMsats?.takeIf { it > 0 } ?: return null
        return Request(
            amountMsats = amount,
            metadata = push.metadata?.takeIf { it.isNotEmpty() } ?: return null,
            timeSent = push.timeSent?.takeIf { it.isNotEmpty() } ?: return null,
            username = push.username?.takeIf { it.isNotEmpty() } ?: return null,
            endpoint = push.endpoint?.takeIf { it.isNotEmpty() } ?: return null,
        )
    }

    /**
     * Create the invoice and post it. Failure for an endpoint that is not public https (iOS posts
     * anywhere; a pushed URL decides where the wallet's invoice goes, so it is checked like any
     * LNURL callback), a node that cannot make the invoice, or a non-2xx answer.
     */
    suspend fun handle(request: Request): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            check(LnurlEndpoint.validate(request.endpoint) is LnurlEndpointCheck.Usable) { "Endpoint is not a public https URL" }
            val descriptionHash = descriptionHash(request.metadata)
            val invoice = lightning.receiveBolt11(
                amountMsat = request.amountMsats.toULong(),
                description = Bolt11DescriptionView.Hash(descriptionHash),
                expirySecs = INVOICE_EXPIRY_SECS,
            )
            val body = buildJsonObject {
                put("invoice", JsonPrimitive(invoice))
                put("amount_msats", JsonPrimitive(request.amountMsats))
                put("description_hash", JsonPrimitive(descriptionHash))
                put("time_sent", JsonPrimitive(request.timeSent))
                put("username", JsonPrimitive(request.username))
            }
            val response = http.execute(HttpRequest(HttpMethod.POST, request.endpoint, body.toString()))
            check(response.isSuccessful) { "HTTP ${response.code}" }
        }
    }

    companion object {
        const val INVOICE_EXPIRY_SECS = 3600u

        /** `SHA256(metadata.utf8)`, hex — LUD-06's commitment to what the payer was shown. */
        fun descriptionHash(metadata: String): String =
            MessageDigest.getInstance("SHA-256").digest(metadata.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}

/** The copy the notifications port shows around [LightningAddressPush], from `Language.swift`. */
object LightningAddressPushCopy {
    const val TITLE = "Payment Request"
    const val SIGN_IN = "Someone wants to pay you <b><amount> satoshis</b>! Please sign in to accept the payment."
    const val HANDLE_NOW_MESSAGE =
        "Someone wants to pay you <b><amount> satoshis</b>! Accept now or try again later in Device Details."
    const val HANDLE_NOW = "Handle now"
    const val GENERATING_INVOICE = "Generating invoice"
    const val FAILED_TITLE = "Payment Request Failed"
    const val FAILED =
        "We couldn't process this payment request. If this keeps happening, please contact support@getbittr.com."

    fun amountSats(amountMsats: Long): String = (amountMsats / 1000).toString().reversed().chunked(3).joinToString(" ").reversed()
}
