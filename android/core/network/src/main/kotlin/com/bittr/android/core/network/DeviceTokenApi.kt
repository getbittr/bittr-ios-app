package com.bittr.android.core.network

import com.bittr.android.core.push.PushChannelAction
import com.bittr.android.core.push.PushChannelPolicy
import com.bittr.android.core.push.PushChannelStatus
import com.bittr.android.core.push.SignedRequestMessage

/**
 * A bittr request signed by the lightning node key — the credential every mutating endpoint on
 * this API uses (`api-contract` §2.3, `BuyViewController.swift:337-362`).
 *
 * Three values that must belong to one signing act. Carried as a unit rather than as three
 * parameters because the `timestamp` inside the signed message and the `timestamp` sent in the
 * body have to be the same number — two call sites reading a clock twice is a ±300s skew
 * rejection (§2.3 rule 3) that reproduces once an hour on a slow device and never in a test.
 */
data class SignedRequest(
    val pubkey: String,
    val signature: String,
    /** Unix **seconds**, the unit §2.3 and `BuyViewController.swift:337` both use. */
    val timestampSeconds: Long,
)

/**
 * Produces [SignedRequest]s. Implemented against the wallet seam, which is why it is an
 * interface here: `:core:network` is pure Kotlin and the node key lives behind `:core:wallet`.
 *
 * Ported from `SwapManager.swift:85-95`. The shape mirrors it exactly — read the node id, take a
 * timestamp, build the message, sign it — because the ordering is the part that matters and
 * inverting it (sign, then stamp) is the skew bug above.
 */
interface BittrRequestSigner {

    /**
     * The lightning node id, or **null while the node is not ready**.
     *
     * Null is an ordinary state, not an error: iOS guards on it at every signing call site
     * (`BuyViewController.swift:330`, `SwapManager.swift:86`) because the node syncs
     * asynchronously after launch. A caller that treats it as a failure will spend the §2.3
     * rule 2 budget on the seconds before the wallet came up.
     */
    suspend fun pubkey(): String?

    /** Signs [message] with the node key, or null when signing failed. */
    suspend fun sign(message: String): String?

    /**
     * Builds the whole [SignedRequest] for a message that embeds [pubkey] and a timestamp.
     *
     * @param buildMessage given the pubkey and the timestamp, produces the exact bytes to sign.
     *   Always one of [SignedRequestMessage]'s functions — the parameter exists so the timestamp
     *   is read once, here, and used in both places.
     */
    suspend fun signRequest(
        nowSeconds: Long,
        buildMessage: (pubkey: String, timestamp: Long) -> String,
    ): SignedRequest? {
        val pubkey = pubkey() ?: return null
        val signature = sign(buildMessage(pubkey, nowSeconds)) ?: return null
        return SignedRequest(pubkey, signature, nowSeconds)
    }
}

/** Unix seconds. A seam so the skew and ordering rules above are testable without waiting. */
fun interface UnixClock {
    fun nowSeconds(): Long

    companion object {
        val System: UnixClock = UnixClock { java.lang.System.currentTimeMillis() / 1000 }
    }
}

/**
 * `PATCH /customer/device-token` — `api-contract` §2.3. **The endpoint Android cannot work
 * without**, and the one that does not exist yet on any backend.
 *
 * ## Why `PATCH` and not `POST`
 *
 * BIT-41's own deliverable 5 says `POST`, and it is wrong — rev 2 of the contract changed the
 * verb and rev 4 kept it. It is a `PATCH` because §2.3 copied the shape of the one signed
 * mutation this API already has, `PATCH /customer/payment-mode`, so that Android writes one
 * signer rather than two. That verb is also the sole reason OkHttp is a dependency of this
 * repo: `java.net.HttpURLConnection.setRequestMethod` validates against a hardcoded array of
 * seven verbs that does not contain PATCH.
 *
 * ## Why it is load-bearing at *first* registration
 *
 * The obvious reading is that this endpoint is for rotation — FCM tokens rotate on restore, data
 * clear, reinstall and prolonged inactivity, and `onNewToken` exists because that is routine.
 * §7 row 5 makes the stronger claim, and it is the one that decides where this sits in the app:
 *
 * - §2.1 blesses a `category: "android"` signup arriving with **no token at all**, because FCM
 *   retrieval is async. The token then has to arrive *somehow*, and this is the only route.
 * - §4.2's `unavailable` verdict tells the client to retry rather than downgrade, and §4.3 makes
 *   that retry the thing standing between the customer and a permanent `onchain` account.
 *
 * Without this endpoint both recovery paths dead-end in a downgrade the customer did not choose.
 */
object DeviceTokenPatch {

    private const val PATH = "customer/device-token"

    /**
     * @param deviceToken the raw FCM registration token, **byte-for-byte as FCM produced it**.
     *   Not trimmed, not truncated, not normalised — §2.4 has the client compare the value the
     *   backend echoes against its local copy (`SwapManager.swift:77-80`), so any normalisation
     *   here becomes a permanent false "stale token" warning there. §2.3's column-width note is
     *   the backend half of the same rule.
     * @param signed covers `device_token:<pubkey>:<deposit_code>:<device_token>:<timestamp>`.
     */
    fun request(
        environment: BittrEnvironment,
        depositCode: String,
        deviceToken: String,
        signed: SignedRequest,
    ): HttpRequest = HttpRequest(
        method = HttpMethod.PATCH,
        url = environment.url(PATH),
        jsonBody = BittrEnvelope.body(
            mapOf(
                "deposit_code" to BittrEnvelope.str(depositCode),
                // §2.3's note: §1 rejected `platform` on registration because `category` already
                // carries it. Here there is no `category`, so this is the discriminator rather
                // than a duplicate of one.
                "platform" to BittrEnvelope.str(BITTR_PLATFORM_ANDROID),
                "device_token" to BittrEnvelope.str(deviceToken),
                "pubkey" to BittrEnvelope.str(signed.pubkey),
                "signature" to BittrEnvelope.str(signed.signature),
                // A number, not a string — `BuyViewController.swift:361` sends `Int`.
                "timestamp" to BittrEnvelope.num(signed.timestampSeconds),
            ),
        ),
    )

    /** Builds the message [request]'s signature must cover. */
    fun message(pubkey: String, depositCode: String, deviceToken: String, timestamp: Long): String =
        SignedRequestMessage.deviceToken(pubkey, depositCode, deviceToken, timestamp)

    /**
     * The accepted response. §2.3: the endpoint re-runs the §4 validation, so the body carries
     * the same pair as registration.
     */
    data class Accepted(val pushChannel: PushChannelStatus) {
        val action: PushChannelAction get() = PushChannelPolicy.decide(pushChannel)
    }

    fun parse(response: HttpResponse): ApiResult<Accepted> {
        if (!response.isSuccessful) return ApiResult.Failure(BittrEnvelope.failureFrom(response))
        val root = BittrEnvelope.parse(response.body)
            ?: return ApiResult.Failure(
                ApiFailure.Malformed("device-token: body is not a JSON object"),
            )
        // A 2xx carrying `success: false` still goes through classify(), because §2.3 rules 3
        // and 4 describe rejections without promising they arrive as a 4xx. Routing both
        // through one classifier is what makes a `no_such_customer` slug behave identically
        // whichever status code it rides on — and that behaviour is the whole of rule 4.
        if (BittrEnvelope.isExplicitFailure(root)) {
            return ApiResult.Failure(ApiFailure.classify(response, BittrEnvelope.errorSlug(root)))
        }
        return ApiResult.Success(Accepted(BittrEnvelope.pushChannelStatus(root)))
    }
}

/**
 * `GET /boltz/webhook-token` — `api-contract` §2.4. The signed Boltz webhook URL, bound to the
 * device token that minted it.
 *
 * Ported from `SwapManager.swift:37-83`. Present in BIT-41 because of **deliverable 6**, which
 * is an ordering rule rather than a feature: after a token rotation the new token must reach the
 * backend *before* the URL is re-minted, because the backend mints against the token it holds.
 * Reverse the order and the fresh URL is bound to a dead token — a swap that silently never
 * notifies. [DeviceTokenLifecycle] is where that ordering is enforced and tested.
 *
 * The staleness compare at `SwapManager.swift:77-80` is ported as a value ([tokenMatchesLocal])
 * rather than as a log line. iOS names the response field `hashedDeviceToken` and then compares
 * it to the raw local token, which is the latent contradiction §2.4 pins down: *"the echoed
 * value must stay directly comparable to the client's raw local token... if the backend hashes
 * it, the Android client must be told the hash"*. Returning the flag means a mismatch can be a
 * test assertion and a Sentry breadcrumb, instead of a log nobody reads.
 */
object BoltzWebhook {

    private const val PATH = "boltz/webhook-token"

    /**
     * The mint request.
     *
     * Signature, pubkey and timestamp ride in the **query string**, not a body — it is a GET,
     * and this is what `SwapManager.swift:51` builds.
     */
    fun request(environment: BittrEnvironment, signed: SignedRequest): HttpRequest = HttpRequest(
        method = HttpMethod.GET,
        url = environment.url(PATH) +
            "?pubkey=${signed.pubkey}" +
            "&timestamp=${signed.timestampSeconds}" +
            "&signature=${signed.signature}",
    )

    /** Builds the message [request]'s signature must cover — three parts, see the function. */
    fun message(pubkey: String, timestamp: Long): String =
        SignedRequestMessage.boltzWebhook(pubkey, timestamp)

    /**
     * A minted URL.
     *
     * @property tokenMatchesLocal false when the echoed `device_token` differs from the token
     *   this device holds — i.e. the backend minted against a stale record. iOS logs
     *   *"backend customer record may be stale"* here and carries on; on Android the recovery
     *   exists (§2.3), so this flag is what tells the lifecycle to use it.
     */
    data class Minted(
        val url: String,
        val echoedDeviceToken: String?,
        val tokenMatchesLocal: Boolean,
    )

    /**
     * @param localDeviceToken the token this device currently holds, for the §2.4 compare.
     */
    fun parse(response: HttpResponse, localDeviceToken: String?): ApiResult<Minted> {
        if (!response.isSuccessful) return ApiResult.Failure(BittrEnvelope.failureFrom(response))
        val root = BittrEnvelope.parse(response.body)
            ?: return ApiResult.Failure(ApiFailure.Malformed("webhook-token: body is not a JSON object"))

        // `success == true` is required here, unlike on the other two endpoints, because
        // SwapManager.swift:68-73 requires it: this response's happy path *does* carry the
        // field, and a body without it is not a mint.
        val url = BittrEnvelope.string(root, "url")
        if (BittrEnvelope.boolean(root, "success") != true || url == null) {
            return ApiResult.Failure(
                ApiFailure.classify(response, BittrEnvelope.errorSlug(root)),
            )
        }
        val echoed = BittrEnvelope.string(root, "device_token")
        return ApiResult.Success(
            Minted(
                url = url,
                echoedDeviceToken = echoed,
                // Null local token means there is nothing to compare against, not a mismatch.
                // iOS never reaches the mint in that state at all (`:39-41` returns early).
                tokenMatchesLocal = localDeviceToken == null || echoed == localDeviceToken,
            ),
        )
    }
}
