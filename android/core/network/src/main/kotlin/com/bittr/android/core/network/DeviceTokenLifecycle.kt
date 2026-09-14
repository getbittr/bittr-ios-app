package com.bittr.android.core.network

import com.bittr.android.core.push.DeviceTokenRetryBudget
import com.bittr.android.core.push.PushChannelAction

/**
 * Where this device's FCM token comes from. Implemented in `:app` over `FirebaseMessaging`;
 * an interface here so the whole of BIT-41 items 5 and 6 is provable on the JVM.
 */
interface DeviceTokenSource {

    /**
     * The current registration token, or null when it could not be obtained.
     *
     * Null is the state BIT-46 decision 1 and §2.1 are both about: retrieval is asynchronous and
     * can simply not have finished. It is not an error and must not become one.
     */
    suspend fun current(): String?

    /**
     * Deletes the registration, so that the next [current] mints a fresh token.
     *
     * The recovery for [PushChannelAction.Retry.FRESH_TOKEN] — §4.2's `invalid` and
     * `unregistered`, where the backend has a verdict and the verdict is that this token is
     * dead. Re-posting it is guaranteed to fail and would burn the §2.3 rule 2 budget that the
     * working recovery needs.
     */
    suspend fun invalidate()
}

/**
 * What this device believes the backend holds.
 *
 * ## It caches the *acknowledged* token, not the last token seen
 *
 * This distinction is the whole correctness of the app-start path. BIT-41 deliverable 5 says to
 * post at app start *"when the cached token differs from `getToken()`"*. If the cache recorded
 * every token FCM handed us, then a `PATCH` that failed — a flight-mode launch, a 500, the
 * endpoint not existing yet — would leave the cache agreeing with FCM and the difference check
 * would never fire again. The customer's token would be permanently absent from the backend, on
 * a client whose cache says everything is fine.
 *
 * Recording only what the backend *acknowledged* makes the difference check self-healing: a
 * failed post leaves the cache stale on purpose, and the next app start retries.
 *
 * That is also why this is a narrower contract than §2.3 rule 1's. The backend is required to be
 * idempotent because it assumes the client re-posts at every launch; this client posts only on a
 * real difference, which satisfies that rule by doing strictly less, and costs the backend
 * nothing per quiet launch.
 */
interface DeviceTokenCache {

    /** The last token the backend confirmed, or null if none ever has been. */
    fun acknowledgedToken(): String?

    /** Records a token the backend has confirmed. */
    fun recordAcknowledged(token: String)

    /**
     * Forgets the acknowledged token.
     *
     * Called when the backend's verdict says the token it holds is dead ([PushChannelAction
     * .TokenRejected]), so that a later app start does not read a stale agreement as "nothing to
     * do".
     */
    fun clearAcknowledged()
}

/**
 * The Boltz webhook URL, cached against the token that minted it —
 * `SwapManager.swift:43-48` / `CacheManager.storeBoltzWebhook`.
 *
 * The cache key is the reason BIT-41 deliverable 6 is an ordering rule: iOS reuses the cached URL
 * only while it still matches the current device token, so a rotation is exactly when a re-mint
 * is required, and a re-mint against a backend that has not yet been told the new token binds the
 * fresh URL to a dead one.
 */
interface BoltzWebhookCache {

    /** Stores a minted URL against the token it was minted for. */
    fun store(url: String, deviceToken: String)

    /** Drops the cached URL. */
    fun clear()
}

/**
 * What one synchronisation attempt did.
 *
 * Every case is a reason, not a boolean, because the call sites differ in what they show: an
 * `onNewToken` arriving while the app is backgrounded shows nothing at all, while the same
 * outcome during signup is BIT-46's "site 2" and shows `tokenregistrationfail`.
 */
sealed interface DeviceTokenSyncResult {

    /**
     * The backend accepted the token and reported a live route.
     *
     * [webhookReminted] is BIT-41 deliverable 6's observable: true when the Boltz webhook URL
     * was re-minted after this post, which happens on a rotation and not on a first send.
     */
    data class Synced(val token: String, val webhookReminted: Boolean) : DeviceTokenSyncResult

    /**
     * The backend accepted the request and reported **no usable route** — §4.2.
     *
     * [action] is [com.bittr.android.core.push.PushChannelPolicy]'s verdict and carries the two
     * things the caller needs: whether to retry, and whether §4.3 permits offering the `onchain`
     * downgrade. Not every one of these is a customer-visible failure, which is why the decision
     * is handed over rather than taken here.
     *
     * @property freshTokenAttempted true when this verdict is the *second* one — the first said
     *   the token was dead, a fresh one was minted and posted, and this is what came back. It
     *   matters to the caller because it is the difference between "the automatic recovery has
     *   not run yet" and "it ran and did not help", which is what
     *   [DeviceTokenRetryBudget.isSessionAllowanceSpent] is otherwise used to approximate.
     */
    data class NotRouted(
        val action: PushChannelAction,
        val freshTokenAttempted: Boolean = false,
    ) : DeviceTokenSyncResult

    /** The call failed. [failure] carries the §2.3 rules 3-4 behaviour. */
    data class Failed(val failure: ApiFailure) : DeviceTokenSyncResult

    /** Nothing to do: the backend already acknowledged exactly this token. */
    data object AlreadyCurrent : DeviceTokenSyncResult

    /**
     * Could not even attempt it, and the reason is ordinary rather than exceptional.
     *
     * Split from [Failed] because none of these is a network event and none should spend the
     * §2.3 rule 2 budget — the request was never built, let alone sent.
     */
    data class NotAttempted(val reason: Reason) : DeviceTokenSyncResult {
        enum class Reason {
            /** FCM had no token to give. §2.1's blessed async race. */
            NO_TOKEN,

            /** No deposit code yet — the customer has not completed signup. */
            NOT_REGISTERED,

            /** The lightning node is not up, so nothing can be signed. */
            WALLET_NOT_READY,

            /** §2.3 rule 2's ceiling is reached for this session and foreground. */
            BUDGET_SPENT,
        }
    }
}

/**
 * BIT-41 deliverables **5 and 6**: the device-token lifecycle, and the Boltz re-mint ordering
 * that hangs off it.
 *
 * ## The two entry points, and why both are needed
 *
 * - [onNewToken] — FCM told us the token changed. This is the ordinary rotation signal.
 * - [syncOnAppStart] — reconcile at launch, because **`onNewToken` does not fire for a rotation
 *   that happened while the app was not running.** A restore or a long idle period rotates the
 *   token; FCM delivers that callback at most once, to a process that may not exist. Without the
 *   launch reconciliation, the customer's payout route dies at the first rotation they were not
 *   watching, permanently, with no signal.
 *
 * Both funnel into one private path so the ordering and budget rules cannot diverge between
 * them.
 *
 * ## Deliverable 6, stated as the rule the code enforces
 *
 * > After any rotation: **post the new token first, re-mint the webhook second** — and only if
 * > the post was accepted.
 *
 * The "only if" is the part not written in the brief, and it follows from the same fact the
 * brief gives: `SwapManager.swift:43-48` caches the minted URL keyed by the token that minted
 * it, and the backend mints against the token *it* holds. Re-minting after a failed post binds a
 * fresh URL to the token the backend still has — the dead one — and then caches it under the new
 * token's key, so the client believes it holds a good URL and the swap never notifies. That is
 * strictly worse than not re-minting at all, because the stale-URL path at least recovers on the
 * next launch.
 *
 * So on a failed post the cached URL is **cleared** and not replaced: no URL means the next swap
 * mints one, against a backend that will by then have been told. Absence recovers; a confidently
 * wrong cache entry does not.
 *
 * ## Pure Kotlin, no Android, no socket
 *
 * Every dependency is a seam. The endpoint is not implemented on any backend and there is no
 * Firebase project reachable from a JVM test, so the only way these rules are provable today is
 * as a table over fakes — which is the same argument `:core:push` and `:core:network` were split
 * on. BIT-142 is where it meets a real server.
 */
class DeviceTokenLifecycle(
    private val environment: BittrEnvironment,
    private val httpClient: HttpClient,
    private val signer: BittrRequestSigner,
    private val tokenSource: DeviceTokenSource,
    private val tokenCache: DeviceTokenCache,
    private val webhookCache: BoltzWebhookCache,
    private val budget: DeviceTokenRetryBudget,
    private val clock: UnixClock = UnixClock.System,
    /**
     * The customer's deposit code, or null before signup completes.
     *
     * A supplier rather than a value because this object outlives the moment signup finishes:
     * it is constructed at process start, when there may be no deposit code, and `onNewToken`
     * can arrive on either side of that.
     */
    private val depositCode: () -> String?,
) {

    /**
     * FCM's `onNewToken`. Posts unconditionally — FCM only calls it when the value changed, and
     * second-guessing that against our own cache is how a genuine rotation gets dropped.
     */
    suspend fun onNewToken(token: String): DeviceTokenSyncResult = post(token, force = true)

    /**
     * Launch reconciliation. Reads the current token and posts it **only when it differs from
     * what the backend acknowledged** — BIT-41 deliverable 5, and the half `onNewToken` cannot
     * cover.
     */
    suspend fun syncOnAppStart(): DeviceTokenSyncResult {
        val token = tokenSource.current()
            ?: return DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.NO_TOKEN,
            )
        return post(token, force = false)
    }

    /**
     * Records a token that `POST /customer` already got onto the backend, so the first app start
     * after signup does not re-post it.
     *
     * Takes the parsed registration rather than the raw token on purpose: only a response
     * reporting a live route proves the token was accepted, and §4.2's `unavailable` is exactly
     * the case where one was sent and there is no verdict.
     */
    fun onRegistered(registered: CustomerRegistration.Registered, sentToken: String?) {
        registered.acknowledgedToken(sentToken)?.let(tokenCache::recordAcknowledged)
    }

    /** §2.3 rule 2's per-foreground reset. Wire to `ON_START` on the process lifecycle owner. */
    fun onAppForegrounded() = budget.onAppForegrounded()

    /**
     * @param allowFreshTokenRecovery whether a [PushChannelAction.Retry.FRESH_TOKEN] verdict may
     *   mint a new token and post it. True from both entry points and false on the recursive
     *   call, so the recovery is exactly one level deep and termination is a property of the
     *   signature rather than of the budget happening to run out.
     *
     *   The `SAME_TOKEN` retry (§4.2 `unavailable`) is deliberately **not** driven from here.
     *   BIT-46 decision 3 puts a schedule on it — roughly 2s then 6s, then one per foreground —
     *   and a schedule is a property of the app's process lifecycle, not of a request builder.
     *   [DeviceTokenRetryBudget] bounds *how many*; the caller owns *when*. Minting a fresh token
     *   is different in kind: it mutates the device's FCM registration, and this class is the
     *   only one holding [DeviceTokenSource].
     */
    private suspend fun post(
        token: String,
        force: Boolean,
        allowFreshTokenRecovery: Boolean = true,
    ): DeviceTokenSyncResult {
        if (!force && tokenCache.acknowledgedToken() == token) {
            return DeviceTokenSyncResult.AlreadyCurrent
        }
        val code = depositCode()
            ?: return DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.NOT_REGISTERED,
            )

        // The rotation test is taken here, before the post, against what the backend last
        // acknowledged. A first send — nothing acknowledged yet — is not a rotation: there is no
        // previously-minted webhook URL bound to a token, so there is nothing to re-mint and
        // doing it anyway would put a request on the wire during signup for no reason.
        val isRotation = tokenCache.acknowledgedToken()?.let { it != token } ?: false

        if (!budget.tryConsume()) {
            return DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.BUDGET_SPENT,
            )
        }

        val now = clock.nowSeconds()
        val signed = signer.signRequest(now) { pubkey, timestamp ->
            DeviceTokenPatch.message(pubkey, code, token, timestamp)
        } ?: return DeviceTokenSyncResult.NotAttempted(
            DeviceTokenSyncResult.NotAttempted.Reason.WALLET_NOT_READY,
        )

        val result = execute(DeviceTokenPatch.request(environment, code, token, signed)) {
            DeviceTokenPatch.parse(it)
        }

        return when (result) {
            is ApiResult.Failure -> {
                // The backend did not take the token, so anything it mints now is bound to the
                // old one. Drop the cached URL rather than refresh it — see the class note.
                if (isRotation) webhookCache.clear()
                DeviceTokenSyncResult.Failed(result.failure)
            }

            is ApiResult.Success -> when (val action = result.value.action) {
                is PushChannelAction.Registered -> {
                    tokenCache.recordAcknowledged(token)
                    // Deliverable 6: token first, webhook second, and only now that the post is
                    // known to have been accepted.
                    val reminted = if (isRotation) remintWebhook(token) else false
                    DeviceTokenSyncResult.Synced(token, webhookReminted = reminted)
                }

                else -> {
                    // No live route. The backend's record no longer agrees with this token, so
                    // the cache must not keep claiming it does — otherwise the app-start
                    // difference check reads "nothing to do" on a customer with no push route.
                    tokenCache.clearAcknowledged()
                    if (isRotation) webhookCache.clear()
                    recoverWithFreshToken(action, token, allowFreshTokenRecovery)
                        ?: DeviceTokenSyncResult.NotRouted(action)
                }
            }
        }
    }

    /**
     * §4.2's `invalid` / `unregistered` recovery: delete the registration, mint a fresh token,
     * post that instead.
     *
     * Returns null when no recovery is warranted or possible, leaving the caller to report the
     * original verdict. A non-null return is the *second* attempt's result, tagged so the caller
     * can tell the two apart.
     *
     * The guard on the token actually changing matters: `deleteToken()` followed by `getToken()`
     * is not guaranteed to produce a different string, and re-posting an identical token would
     * spend another unit of budget to learn what we already know.
     */
    private suspend fun recoverWithFreshToken(
        action: PushChannelAction,
        rejectedToken: String,
        allowed: Boolean,
    ): DeviceTokenSyncResult? {
        if (!allowed || action.retry != PushChannelAction.Retry.FRESH_TOKEN) return null
        tokenSource.invalidate()
        val fresh = tokenSource.current()?.takeIf { it != rejectedToken } ?: return null
        return when (val retried = post(fresh, force = true, allowFreshTokenRecovery = false)) {
            is DeviceTokenSyncResult.NotRouted -> retried.copy(freshTokenAttempted = true)
            else -> retried
        }
    }

    /**
     * Re-mints the Boltz webhook URL for [token] and caches it under that token.
     *
     * Best-effort by design: a failed mint is not a failed token sync. The token — the thing
     * payouts depend on — is already on the backend by the time this runs, and `SwapManager`
     * mints on demand anyway, so an empty cache is a fully working state. Returning false rather
     * than throwing keeps that true at the call site.
     */
    private suspend fun remintWebhook(token: String): Boolean {
        val signed = signer.signRequest(clock.nowSeconds()) { pubkey, timestamp ->
            BoltzWebhook.message(pubkey, timestamp)
        } ?: run {
            webhookCache.clear()
            return false
        }
        val result = execute(BoltzWebhook.request(environment, signed)) {
            BoltzWebhook.parse(it, token)
        }
        val minted = result.valueOrNull()
        return when {
            minted == null -> {
                webhookCache.clear()
                false
            }

            // §2.4's staleness compare. The backend minted against a token that is not the one
            // we just sent it, so the URL is bound to something else — caching it would be
            // caching the exact failure deliverable 6 exists to prevent, only later.
            !minted.tokenMatchesLocal -> {
                webhookCache.clear()
                false
            }

            else -> {
                webhookCache.store(minted.url, token)
                true
            }
        }
    }

    /**
     * Runs one request, turning the transport's one exception into an [ApiFailure].
     *
     * [HttpTransportException] is the only throw the seam permits, and it exists so that "we
     * never reached them" arrives as a different thing from "they said no" — §4.2's whole reason
     * for splitting `unavailable` out. Catching it here, once, is what keeps every call site
     * above from having to remember that.
     */
    private suspend fun <T> execute(
        request: HttpRequest,
        parse: (HttpResponse) -> ApiResult<T>,
    ): ApiResult<T> = try {
        parse(httpClient.execute(request))
    } catch (e: HttpTransportException) {
        ApiResult.Failure(ApiFailure.Unreachable(e.message ?: "transport failure"))
    }
}
