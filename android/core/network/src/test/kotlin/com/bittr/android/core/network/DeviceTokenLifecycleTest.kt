package com.bittr.android.core.network

import com.bittr.android.core.push.DeviceTokenRetryBudget
import com.bittr.android.core.push.PushChannelAction
import com.bittr.android.core.push.PushChannelReason
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-41 deliverables **5 and 6** — the token lifecycle, and the Boltz re-mint ordering.
 *
 * Everything here is a fake, and that is the point rather than a compromise: the endpoint under
 * test exists on no backend (`api-contract` §7 rows 3-7 are parked with Ruben) and there is no
 * Firebase project a JVM test can reach. The rules are still rules, so they are asserted as a
 * table. BIT-142 is where the same behaviour meets a real server.
 */
class DeviceTokenLifecycleTest {

    // ---------------------------------------------------------------- fakes

    /** Replays queued responses in order, recording every request that was made. */
    private class ScriptedClient(vararg responses: HttpResponse) : HttpClient {
        private val queue = ArrayDeque(responses.toList())
        val requests = mutableListOf<HttpRequest>()
        var throwTransport = false

        override suspend fun execute(request: HttpRequest): HttpResponse {
            requests += request
            if (throwTransport) throw HttpTransportException("no route to host")
            return queue.removeFirstOrNull() ?: HttpResponse(500, "unscripted request")
        }

        /** The order the endpoints were hit in — deliverable 6's whole assertion. */
        fun pathsHit(): List<String> = requests.map { it.url.substringAfter("/api/").substringBefore('?') }
    }

    private class FakeTokenSource(var token: String?) : DeviceTokenSource {
        var invalidations = 0
        var nextTokenAfterInvalidate: String? = null

        override suspend fun current(): String? = token

        override suspend fun invalidate() {
            invalidations++
            token = nextTokenAfterInvalidate
        }
    }

    private class FakeTokenCache(private var acknowledged: String? = null) : DeviceTokenCache {
        override fun acknowledgedToken(): String? = acknowledged
        override fun recordAcknowledged(token: String) { acknowledged = token }
        override fun clearAcknowledged() { acknowledged = null }
    }

    private class FakeWebhookCache : BoltzWebhookCache {
        var url: String? = null
        var boundTo: String? = null
        var clears = 0

        override fun store(url: String, deviceToken: String) {
            this.url = url
            this.boundTo = deviceToken
        }

        override fun clear() {
            clears++
            url = null
            boundTo = null
        }
    }

    private class FakeSigner(private val pubkey: String? = "02aabb") : BittrRequestSigner {
        val signed = mutableListOf<String>()
        override suspend fun pubkey(): String? = pubkey
        override suspend fun sign(message: String): String? {
            signed += message
            return "sig(${message.hashCode()})"
        }
    }

    private fun lifecycle(
        client: HttpClient,
        tokenSource: FakeTokenSource = FakeTokenSource("token-a"),
        tokenCache: FakeTokenCache = FakeTokenCache(),
        webhookCache: FakeWebhookCache = FakeWebhookCache(),
        signer: BittrRequestSigner = FakeSigner(),
        budget: DeviceTokenRetryBudget = DeviceTokenRetryBudget(),
        depositCode: String? = "ABC123",
    ) = DeviceTokenLifecycle(
        environment = BittrEnvironment.DEVELOPMENT,
        httpClient = client,
        signer = signer,
        tokenSource = tokenSource,
        tokenCache = tokenCache,
        webhookCache = webhookCache,
        budget = budget,
        clock = { 1_757_000_000 },
        depositCode = { depositCode },
    )

    private val live = HttpResponse(200, """{"data":{"push_channel":"fcm"}}""")
    private fun mint(token: String) = HttpResponse(
        200,
        """{"success":true,"url":"https://boltz.example/hook","device_token":"$token"}""",
    )

    // ---------------------------------------------------------------- deliverable 5

    /**
     * The half `onNewToken` cannot cover: a rotation that happened while the app was not
     * running fires no callback, because FCM delivers it at most once and to a process that may
     * not exist. Without this, a restore kills the payout route permanently and silently.
     */
    @Test
    fun `app start posts a token that differs from what the backend acknowledged`() = runTest {
        val client = ScriptedClient(live, mint("token-b"))
        val source = FakeTokenSource("token-b")
        val cache = FakeTokenCache(acknowledged = "token-a")

        val result = lifecycle(client, tokenSource = source, tokenCache = cache).syncOnAppStart()

        assertEquals(DeviceTokenSyncResult.Synced("token-b", webhookReminted = true), result)
        assertEquals("token-b", cache.acknowledgedToken())
    }

    /** §2.3 rule 1's quiet launch: nothing changed, so nothing is sent. */
    @Test
    fun `app start sends nothing when the backend already acknowledged this token`() = runTest {
        val client = ScriptedClient()
        val result = lifecycle(
            client,
            tokenSource = FakeTokenSource("token-a"),
            tokenCache = FakeTokenCache(acknowledged = "token-a"),
        ).syncOnAppStart()

        assertEquals(DeviceTokenSyncResult.AlreadyCurrent, result)
        assertTrue(client.requests.isEmpty())
    }

    /**
     * The reason the cache records the *acknowledged* token rather than the last one seen.
     *
     * A failed post must leave the cache stale on purpose. If it recorded what FCM handed us,
     * the difference check would agree with FCM forever and the token would never reach the
     * backend — on a client whose own state says everything is fine.
     */
    @Test
    fun `a failed post leaves the cache stale so the next app start retries`() = runTest {
        val cache = FakeTokenCache(acknowledged = "token-a")
        val source = FakeTokenSource("token-b")
        val failing = ScriptedClient(HttpResponse(503, ""))

        val first = lifecycle(failing, tokenSource = source, tokenCache = cache).syncOnAppStart()
        assertTrue(first is DeviceTokenSyncResult.Failed)
        assertEquals("token-a", cache.acknowledgedToken())

        // Next launch, backend now up: the difference is still there to be found.
        val recovering = ScriptedClient(live, mint("token-b"))
        val second = lifecycle(recovering, tokenSource = source, tokenCache = cache).syncOnAppStart()
        assertEquals(DeviceTokenSyncResult.Synced("token-b", webhookReminted = true), second)
    }

    /** §2.1's blessed async race. FCM had nothing to give; that is not an error. */
    @Test
    fun `no token at app start is an ordinary outcome that sends nothing`() = runTest {
        val client = ScriptedClient()
        val result = lifecycle(client, tokenSource = FakeTokenSource(null)).syncOnAppStart()

        assertEquals(
            DeviceTokenSyncResult.NotAttempted(DeviceTokenSyncResult.NotAttempted.Reason.NO_TOKEN),
            result,
        )
        assertTrue(client.requests.isEmpty())
    }

    /** Nothing to sign against before signup completes — and §2.3 rule 4's race, client-side. */
    @Test
    fun `no deposit code yet means the request is never built`() = runTest {
        val client = ScriptedClient()
        val result = lifecycle(client, depositCode = null).onNewToken("token-b")

        assertEquals(
            DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.NOT_REGISTERED,
            ),
            result,
        )
        assertTrue(client.requests.isEmpty())
    }

    /**
     * `SwapManager.swift:86` and `BuyViewController.swift:330` both guard on the node id for the
     * same reason: the wallet syncs asynchronously after launch. Spending budget on those seconds
     * is spending it on nothing.
     */
    @Test
    fun `a wallet that cannot sign does not spend the retry budget`() = runTest {
        val budget = DeviceTokenRetryBudget()
        val client = ScriptedClient()

        val result = lifecycle(client, signer = FakeSigner(pubkey = null), budget = budget)
            .onNewToken("token-b")

        assertEquals(
            DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.WALLET_NOT_READY,
            ),
            result,
        )
        assertTrue(client.requests.isEmpty())
        // The assertion that matters, and the one the obvious ordering gets wrong: the budget
        // bounds attempts against the endpoint, and this request was never built. Charging it
        // would spend the session's three on the seconds before the wallet came up.
        assertEquals(0, budget.attemptsInSession)
    }

    /** `onNewToken` posts unconditionally — FCM only calls it when the value changed. */
    @Test
    fun `onNewToken posts even when the cache agrees`() = runTest {
        val client = ScriptedClient(live)
        val result = lifecycle(
            client,
            tokenCache = FakeTokenCache(acknowledged = "token-a"),
        ).onNewToken("token-a")

        assertEquals(DeviceTokenSyncResult.Synced("token-a", webhookReminted = false), result)
        assertEquals(1, client.requests.size)
    }

    /** §2.3 rule 2's ceiling, reached. Not "wait and retry" — nothing changes until a foreground. */
    @Test
    fun `the session allowance bounds how often a failing endpoint is called`() = runTest {
        val budget = DeviceTokenRetryBudget()
        val cache = FakeTokenCache(acknowledged = "token-a")
        val client = ScriptedClient(*Array(10) { HttpResponse(404, "") })
        val subject = lifecycle(client, tokenCache = cache, budget = budget)

        repeat(3) { assertTrue(subject.onNewToken("token-b") is DeviceTokenSyncResult.Failed) }
        assertEquals(
            DeviceTokenSyncResult.NotAttempted(
                DeviceTokenSyncResult.NotAttempted.Reason.BUDGET_SPENT,
            ),
            subject.onNewToken("token-b"),
        )
        assertEquals(3, client.requests.size)

        // ...and one more per foreground after that, which is what makes BIT-35's support advice
        // ("ask them to open the app once") a requirement rather than a hope.
        subject.onAppForegrounded()
        assertTrue(subject.onNewToken("token-b") is DeviceTokenSyncResult.Failed)
        assertEquals(4, client.requests.size)
    }

    // ---------------------------------------------------------------- deliverable 6

    /**
     * The ordering rule, stated as the only thing that can prove it: which endpoint was hit
     * first.
     *
     * `SwapManager.swift:43-48` caches the minted URL keyed by the token that minted it, and the
     * backend mints against the token *it* holds. Reverse these two and the fresh URL is bound to
     * a dead token — cached under the new token's key, so the client believes it is fine.
     */
    @Test
    fun `after a rotation the token is posted before the webhook is re-minted`() = runTest {
        val client = ScriptedClient(live, mint("token-b"))
        val webhook = FakeWebhookCache()

        lifecycle(
            client,
            tokenSource = FakeTokenSource("token-b"),
            tokenCache = FakeTokenCache(acknowledged = "token-a"),
            webhookCache = webhook,
        ).syncOnAppStart()

        assertEquals(listOf("customer/device-token", "boltz/webhook-token"), client.pathsHit())
        assertEquals("https://boltz.example/hook", webhook.url)
        assertEquals("token-b", webhook.boundTo)
    }

    /**
     * The "only if accepted" half, which the brief does not say and which follows from the same
     * fact it gives. Minting after a failed post binds a fresh URL to the token the backend still
     * holds — the dead one — and caches it under the new key.
     *
     * So a failed post clears the cache instead. No URL means the next swap mints one, against a
     * backend that will by then have been told; absence recovers, a confidently wrong entry does
     * not.
     */
    @Test
    fun `a rotation whose token post failed clears the webhook cache and mints nothing`() = runTest {
        val client = ScriptedClient(HttpResponse(500, ""))
        val webhook = FakeWebhookCache().also { it.store("https://boltz.example/stale", "token-a") }

        val result = lifecycle(
            client,
            tokenSource = FakeTokenSource("token-b"),
            tokenCache = FakeTokenCache(acknowledged = "token-a"),
            webhookCache = webhook,
        ).syncOnAppStart()

        assertTrue(result is DeviceTokenSyncResult.Failed)
        assertEquals(listOf("customer/device-token"), client.pathsHit())
        assertNull(webhook.url)
        assertEquals(1, webhook.clears)
    }

    /** A first send is not a rotation: nothing was ever minted, so there is nothing to re-mint. */
    @Test
    fun `a first token send does not mint a webhook`() = runTest {
        val client = ScriptedClient(live)
        val webhook = FakeWebhookCache()

        val result = lifecycle(
            client,
            tokenSource = FakeTokenSource("token-a"),
            tokenCache = FakeTokenCache(acknowledged = null),
            webhookCache = webhook,
        ).syncOnAppStart()

        assertEquals(DeviceTokenSyncResult.Synced("token-a", webhookReminted = false), result)
        assertEquals(listOf("customer/device-token"), client.pathsHit())
        assertNull(webhook.url)
    }

    /**
     * §2.4's compare, enforced rather than logged. A mint that came back bound to some other
     * token is the failure this deliverable exists to prevent, arriving one step later.
     */
    @Test
    fun `a webhook minted against a different token is not cached`() = runTest {
        val client = ScriptedClient(live, mint("token-a"))
        val webhook = FakeWebhookCache()

        val result = lifecycle(
            client,
            tokenSource = FakeTokenSource("token-b"),
            tokenCache = FakeTokenCache(acknowledged = "token-a"),
            webhookCache = webhook,
        ).syncOnAppStart()

        assertEquals(DeviceTokenSyncResult.Synced("token-b", webhookReminted = false), result)
        assertNull(webhook.url)
    }

    /** A failed mint is not a failed sync: the token — the thing payouts need — already landed. */
    @Test
    fun `a failed re-mint still reports the token as synced`() = runTest {
        val client = ScriptedClient(live, HttpResponse(500, ""))
        val cache = FakeTokenCache(acknowledged = "token-a")

        val result = lifecycle(
            client,
            tokenSource = FakeTokenSource("token-b"),
            tokenCache = cache,
        ).syncOnAppStart()

        assertEquals(DeviceTokenSyncResult.Synced("token-b", webhookReminted = false), result)
        assertEquals("token-b", cache.acknowledgedToken())
    }

    // ---------------------------------------------------------------- §4.2 / §4.3

    /**
     * `unregistered` is a verdict about *this* token, so the recovery is a new one — and it must
     * be an actually different one, or the second post spends budget to learn what we know.
     */
    @Test
    fun `a dead token is replaced and the fresh one posted`() = runTest {
        val client = ScriptedClient(
            HttpResponse(200, """{"data":{"push_channel":"none","push_channel_reason":"unregistered"}}"""),
            live,
        )
        val source = FakeTokenSource("token-b").also { it.nextTokenAfterInvalidate = "token-c" }
        val cache = FakeTokenCache(acknowledged = "token-a")

        val result = lifecycle(client, tokenSource = source, tokenCache = cache).onNewToken("token-b")

        assertEquals(1, source.invalidations)
        assertEquals(DeviceTokenSyncResult.Synced("token-c", webhookReminted = false), result)
        assertEquals("token-c", cache.acknowledgedToken())
    }

    /** Exactly one level deep, so termination is a property of the signature, not of the budget. */
    @Test
    fun `the fresh-token recovery is attempted once, not in a loop`() = runTest {
        val dead = HttpResponse(
            200,
            """{"data":{"push_channel":"none","push_channel_reason":"invalid"}}""",
        )
        val client = ScriptedClient(dead, dead, dead, dead)
        val source = FakeTokenSource("token-b").also { it.nextTokenAfterInvalidate = "token-c" }

        val result = lifecycle(client, tokenSource = source).onNewToken("token-b")

        assertEquals(1, source.invalidations)
        assertEquals(2, client.requests.size)
        assertTrue(result is DeviceTokenSyncResult.NotRouted)
        assertTrue((result as DeviceTokenSyncResult.NotRouted).freshTokenAttempted)
    }

    /**
     * §4.3's invariant, at the one place a client could quietly break it: `unavailable` means a
     * token *was* sent and FCM never answered. Minting a new one is not the recovery, and the
     * downgrade is never on offer.
     */
    @Test
    fun `an unavailable verdict neither mints a new token nor offers the downgrade`() = runTest {
        val client = ScriptedClient(
            HttpResponse(200, """{"data":{"push_channel":"none","push_channel_reason":"unavailable"}}"""),
        )
        val source = FakeTokenSource("token-b")

        val result = lifecycle(client, tokenSource = source).onNewToken("token-b")

        assertEquals(0, source.invalidations)
        assertEquals(1, client.requests.size)
        val notRouted = result as DeviceTokenSyncResult.NotRouted
        assertEquals(PushChannelAction.Unavailable, notRouted.action)
        assertFalse(notRouted.action.mayOfferOnchainDowngrade)
        assertFalse(notRouted.freshTokenAttempted)
    }

    /**
     * A "none" verdict must not leave the cache claiming the backend is happy — the app-start
     * difference check would then read "nothing to do" for a customer with no push route.
     */
    @Test
    fun `losing the route clears the acknowledgement`() = runTest {
        val client = ScriptedClient(
            HttpResponse(200, """{"data":{"push_channel":"none","push_channel_reason":"unavailable"}}"""),
        )
        val cache = FakeTokenCache(acknowledged = "token-a")

        lifecycle(client, tokenCache = cache).onNewToken("token-a")

        assertNull(cache.acknowledgedToken())
    }

    /**
     * §4.2's split, at the seam: no response at all is not a verdict on the token. It arrives as
     * a different type and lands on the retry path, never on the downgrade path.
     */
    @Test
    fun `a transport failure is a bounded retry and not evidence about the token`() = runTest {
        val client = ScriptedClient().also { it.throwTransport = true }

        val result = lifecycle(client).onNewToken("token-b")

        val failed = result as DeviceTokenSyncResult.Failed
        assertTrue(failed.failure is ApiFailure.Unreachable)
        assertEquals(ApiFailure.Recovery.RETRY_IN_BUDGET, failed.failure.recovery)
    }

    // ---------------------------------------------------------------- registration hand-off

    @Test
    fun `a registration that established a route primes the cache`() = runTest {
        val cache = FakeTokenCache()
        val registered = requireNotNull(
            CustomerRegistration.parse(
                HttpResponse(200, """{"data":{"deposit_code":"ABC123","push_channel":"fcm"}}"""),
            ).valueOrNull(),
        )

        lifecycle(ScriptedClient(), tokenCache = cache).onRegistered(registered, "token-a")

        assertEquals("token-a", cache.acknowledgedToken())
    }

    /**
     * ...and one that did not, does not. `missing` is §2.1's blessed async race: the token never
     * reached the backend, so the next app start has to post it. That is §7 row 5's *"load-bearing
     * at first registration"* in one assertion.
     */
    @Test
    fun `a registration with no route leaves the cache empty so app start posts the token`() = runTest {
        val cache = FakeTokenCache()
        val registered = requireNotNull(
            CustomerRegistration.parse(
                HttpResponse(
                    200,
                    """{"data":{"deposit_code":"ABC123","push_channel":"none",
                       "push_channel_reason":"missing"}}""",
                ),
            ).valueOrNull(),
        )
        assertEquals(
            PushChannelAction.NoTokenSent(PushChannelReason.MISSING),
            registered.action,
        )

        val client = ScriptedClient(live)
        val subject = lifecycle(client, tokenSource = FakeTokenSource("token-a"), tokenCache = cache)
        subject.onRegistered(registered, sentToken = null)

        assertNull(cache.acknowledgedToken())
        assertEquals(DeviceTokenSyncResult.Synced("token-a", webhookReminted = false), subject.syncOnAppStart())
    }
}
