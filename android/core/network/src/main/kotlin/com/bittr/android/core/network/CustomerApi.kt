package com.bittr.android.core.network

import com.bittr.android.core.push.PushChannelAction
import com.bittr.android.core.push.PushChannelPolicy
import com.bittr.android.core.push.PushChannelStatus

/**
 * The `category` value this client sends — `api-contract` §2.1 and §2.2.
 *
 * A constant rather than a literal at two call sites because it appears on **two different
 * endpoints at two different points in the funnel**, and §2.2 exists entirely because the issue
 * as filed missed the second one. `POST /verify/email` is sent from the email screen, long
 * before `POST /customer`; if `category` is enum-validated there and only `/customer` is widened,
 * Android registration dies at email verification with an error that points nowhere near the
 * cause.
 *
 * §5 then makes this value load-bearing beyond registration: dispatch routes by `category`, not
 * by which token column is populated, precisely so that a customer holding both an iPhone and an
 * Android device (§1 reason 4) is unambiguous. The string that decides which transport a payout
 * push takes should exist once.
 */
const val BITTR_CATEGORY_ANDROID: String = "android"

/**
 * The platform discriminator on `PATCH /customer/device-token` — §2.3.
 *
 * Separate from [BITTR_CATEGORY_ANDROID] despite having the same value today, because they are
 * different fields on different endpoints and the contract argues them differently: §1 *rejected*
 * a `platform` field on registration, where `category` already carries it, and §2.3 admits one on
 * the refresh endpoint only because there is no `category` there to carry it. Collapsing them
 * into one constant would quietly assert they must always agree — which is true, but it is a
 * property of the contract, not of this client, and it is the kind of assumption that survives a
 * contract change it should not have survived.
 */
const val BITTR_PLATFORM_ANDROID: String = "android"

/**
 * `POST /verify/email` — `api-contract` §2.2. The **first** call in the signup funnel.
 *
 * Ported from `Transfer1ViewController.swift:404-436` (`didSendDetailsToBittr`). Three fields,
 * and the only change from iOS is `category`.
 *
 * The response is read exactly the way iOS reads it (`:420-431`): an explicit `success: false`
 * with a `message` is an IBAN-validation rejection whose text is shown to the customer verbatim;
 * **anything else 2xx is success**, including a body with no `success` field at all. That
 * polarity is not a detail — inverting it fails every good registration.
 */
object EmailVerification {

    private const val PATH = "verify/email"

    /** The request. [iban] and [email] are sent as typed, exactly as on iOS. */
    fun request(
        environment: BittrEnvironment,
        email: String,
        iban: String,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "email" to BittrEnvelope.str(email),
                "iban" to BittrEnvelope.str(iban),
                "category" to BittrEnvelope.str(BITTR_CATEGORY_ANDROID),
            ),
        ),
    )

    /** The outcome. [Rejected] carries the backend's own words, which is what iOS displays. */
    sealed interface Outcome {
        data object Accepted : Outcome

        /** `success: false`. [message] is null when the backend sent none. */
        data class Rejected(val message: String?) : Outcome
    }

    fun parse(response: HttpResponse): ApiResult<Outcome> {
        if (!response.isSuccessful) return ApiResult.Failure(BittrEnvelope.failureFrom(response))
        val root = BittrEnvelope.parse(response.body)
            ?: return ApiResult.Failure(ApiFailure.Malformed("verify/email: body is not a JSON object"))
        return ApiResult.Success(
            if (BittrEnvelope.isExplicitFailure(root)) {
                Outcome.Rejected(BittrEnvelope.message(root))
            } else {
                Outcome.Accepted
            },
        )
    }
}

/**
 * `POST /customer` — `api-contract` §2.1. The registration itself.
 *
 * Ported from `Transfer2ViewController.swift:347-376`. Every field iOS sends is modelled, not
 * only the two BIT-41 changes, and that is deliberate: a half-body would compile, and the
 * signup port would then fill in the rest somewhere else, which is how `category` ends up
 * written twice with one of them saying `"ios"`.
 *
 * ## The two changes from iOS, and the one omission
 *
 * 1. `category` is `"android"` rather than the hardcoded `"ios"` at `:353`.
 * 2. `android_device_token` replaces `ios_device_token`.
 * 3. **`ios_device_token` is never sent.** §2.1 says a request carrying the other platform's
 *    token field must not be *rejected* — but §4.2 says a request that carries the other
 *    platform's field and not its own reports `platform_mismatch`, which §9 routes to support as
 *    **our defect**. So "not rejected" is forward compatibility for the backend, not a licence
 *    for this client to send it. [androidDeviceToken] is the only token field on this request,
 *    and `AndroidRegistrationBodyTest` holds that.
 *
 * ## No token is a normal registration
 *
 * [androidDeviceToken] is nullable and, when null, the key is **absent from the body** rather
 * than sent as `""`. §2.1 blesses both spellings and pairs them under one §4.2 reason
 * (`missing`), and blesses the case itself: *"`category: "android"` with no
 * `android_device_token` at all is a normal, accepted registration — not an error"*, because FCM
 * token retrieval is asynchronous and can legitimately miss this call.
 *
 * That is why §2.3 is load-bearing at *first registration* and not only at rotation (§7 row 5),
 * and why [DeviceTokenLifecycle] exists. Note also BIT-46 decision 1: the client should wait a
 * bounded 15s for the token before registering (`Transfer2ViewController.swift:141-145`,
 * `:192-202`) rather than racing straight past it. This type is what a registration looks like
 * after that wait, whichever way it went.
 */
object CustomerRegistration {

    private const val PATH = "customer"

    /**
     * Every field of `Transfer2ViewController.swift:347-376`, with the BIT-41 changes applied.
     *
     * Nullable fields are the ones iOS adds conditionally: `payment_mode` at `:367-369`,
     * `exclusive_initiative_confirmed_at` at `:378-380`, `deposit_code` at `:385-387`.
     */
    data class Fields(
        val email: String,
        val emailToken: String,
        val bitcoinAddress: String,
        val bitcoinMessage: String,
        val bitcoinSignature: String,
        val iban: String,
        val lightningPubkey: String,
        val lightningSignature: String,
        val xpubKey: String,
        /**
         * §4.3's downgrade, sent only when the customer chose it. Null means "do not send the
         * field", which is what leaves the backend's default in place — §2.1 is explicit that
         * the backend *"does not infer or downgrade `payment_mode` on its own"*.
         */
        val paymentMode: String? = null,
        /** Published T&C §2.5, ISO-8601 UTC. Null when the record predates its collection. */
        val exclusiveInitiativeConfirmedAt: String? = null,
        /** Recovery: reuse the existing deposit code so the backend updates rather than creates. */
        val depositCode: String? = null,
    )

    /**
     * @param androidDeviceToken the FCM registration token, or null when none was available in
     *   time. Null omits the field; see the class note.
     */
    fun request(
        environment: BittrEnvironment,
        fields: Fields,
        androidDeviceToken: String?,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.POST,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "email" to BittrEnvelope.str(fields.email),
                "email_token" to BittrEnvelope.str(fields.emailToken),
                "bitcoin_address" to BittrEnvelope.str(fields.bitcoinAddress),
                // The four constants iOS sends verbatim at :351, :360-362. Carried rather than
                // re-derived: they describe the xpub this client will produce, and the day they
                // stop being right is the day the wallet layer changes, not this file.
                "initial_address_type" to BittrEnvelope.str("extended"),
                "category" to BittrEnvelope.str(BITTR_CATEGORY_ANDROID),
                "bitcoin_message" to BittrEnvelope.str(fields.bitcoinMessage),
                "bitcoin_signature" to BittrEnvelope.str(fields.bitcoinSignature),
                "iban" to BittrEnvelope.str(fields.iban),
                "lightning_pubkey" to BittrEnvelope.str(fields.lightningPubkey),
                "lightning_signature" to BittrEnvelope.str(fields.lightningSignature),
                "xpub_key" to BittrEnvelope.str(fields.xpubKey),
                "xpub_addr_type" to BittrEnvelope.str("bech32"),
                "xpub_path" to BittrEnvelope.str("m/0/x"),
                "skip_xpub_usage_check" to BittrEnvelope.str("true"),
                // The one BIT-41 field. Absent when null — never "" and never ios_device_token.
                "android_device_token" to BittrEnvelope.str(androidDeviceToken),
                "payment_mode" to BittrEnvelope.str(fields.paymentMode),
                "exclusive_initiative_confirmed_at" to
                    BittrEnvelope.str(fields.exclusiveInitiativeConfirmedAt),
                "deposit_code" to BittrEnvelope.str(fields.depositCode),
            ),
        ),
    )

    /**
     * A successful registration.
     *
     * [pushChannel] and [action] are the §2.1/§4 half. The registration succeeded either way —
     * §4.1 settled that a token the backend cannot use must **not** fail the request, because
     * that would leave the customer with no account and no deposit code over a problem they
     * cannot fix. So this is a success with a possibly-bad push route attached, and the caller
     * decides what to show.
     */
    data class Registered(
        val depositCode: String?,
        val iban: String?,
        val swift: String?,
        val pushChannel: PushChannelStatus,
    ) {
        /** What to do about [pushChannel], per §4.3. */
        val action: PushChannelAction get() = PushChannelPolicy.decide(pushChannel)

        /**
         * Whether `tokenregistrationfail` (`Language.swift:235`) should be shown — §4.3's
         * **second** wiring point, the one with no iOS equivalent and the one BIT-46 decision 2
         * calls "site 2".
         */
        val showsRegistrationFailureCopy: Boolean
            get() = PushChannelPolicy.showsRegistrationFailureCopy(action)

        /**
         * The token this registration got onto the backend, if any — for priming
         * [DeviceTokenCache] so the next app start does not re-post a token that already landed.
         *
         * Keyed on the *response*, not on what was sent: a `push_channel` of `fcm` is the only
         * proof the token was accepted, and §4.2's `unavailable` is precisely the case where we
         * sent one and have no verdict.
         */
        fun acknowledgedToken(sentToken: String?): String? =
            sentToken?.takeIf { action is PushChannelAction.Registered }
    }

    fun parse(response: HttpResponse): ApiResult<Registered> {
        if (!response.isSuccessful) return ApiResult.Failure(BittrEnvelope.failureFrom(response))
        val root = BittrEnvelope.parse(response.body)
            ?: return ApiResult.Failure(ApiFailure.Malformed("customer: body is not a JSON object"))
        if (BittrEnvelope.isExplicitFailure(root)) {
            return ApiResult.Failure(
                ApiFailure.Unclassified(
                    code = response.code,
                    slug = BittrEnvelope.errorSlug(root),
                    detail = "customer: 2xx with success=false",
                ),
            )
        }
        val data = BittrEnvelope.data(root)
        return ApiResult.Success(
            Registered(
                // Read tolerantly and kept nullable, matching iOS's `as?` casts at :410-413.
                // A registration that succeeded but omitted a field is not this layer's problem
                // to turn into an exception; the screen that needs the deposit code is where
                // its absence means something.
                depositCode = BittrEnvelope.string(data, "deposit_code"),
                iban = BittrEnvelope.string(data, "iban"),
                swift = BittrEnvelope.string(data, "swift"),
                pushChannel = BittrEnvelope.pushChannelStatus(root),
            ),
        )
    }
}
