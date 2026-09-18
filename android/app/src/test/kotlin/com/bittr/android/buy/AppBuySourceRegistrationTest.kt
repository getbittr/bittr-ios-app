package com.bittr.android.buy

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.IbanEntity
import com.bittr.android.core.network.InMemoryBittrCustomerStore
import com.bittr.android.feature.buy.RegisterResult
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `POST /customer` needs the lightning node's key and its signature, which arrive when the node
 * finishes starting. A signup straight after the wallet was created gets there first: the screen
 * said "your wallet is still syncing" and cleared the code, which is where
 * forgot_pin_remove_wallet.yaml stopped — the code had been accepted (`check2fa -> 200`) and no
 * `POST /customer` followed.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AppBuySourceRegistrationTest {

    private val entity = IbanEntity(
        id = "entity-1",
        yourIbanNumber = "CH93 0076 2011 6238 5295 7",
        yourEmail = "e2ebittr@getbittr.com",
        emailToken = "token-123456789012345678901234567890",
    )

    private val store = InMemoryBittrCustomerStore(listOf(entity))
    private val requests = mutableListOf<HttpRequest>()

    private val http = object : HttpClient {
        override suspend fun execute(request: HttpRequest): HttpResponse {
            requests += request
            return HttpResponse(200, """{"data":{"iban":"CH00","deposit_code":"DC1","swift":"SWIFT"}}""")
        }
    }

    /** A node that answers only once it has started, as one does a few seconds after a wallet is made. */
    private class LateNode(private val readyOnCall: Int) : BittrRequestSigner {
        var pubkeyCalls = 0
        var signCalls = 0
        override suspend fun pubkey(): String? = if (++pubkeyCalls >= readyOnCall) "02pub" else null
        override suspend fun sign(message: String): String? = if (++signCalls >= readyOnCall) "sig" else null
    }

    private fun source(signer: BittrRequestSigner) = AppBuySource(
        store = store,
        environment = BittrEnvironment.DEVELOPMENT,
        http = http,
        signer = signer,
        keys = object : BittrRegistrationKeys {
            override suspend fun bittrAddress(): String = "bcrt1qaddress"
            override fun xpub(): String = "xpub123"
            override fun signBitcoinMessage(message: String): String = "bitcoin-sig"
        },
        tokens = object : DeviceTokenSource {
            override suspend fun current(): String = "device-token"
            override suspend fun invalidate() = Unit
        },
        notifications = NotificationAccess(ApplicationProvider.getApplicationContext()),
    )

    @Test
    fun `registration waits for the node instead of failing on the first look`() = runTest {
        val node = LateNode(readyOnCall = 3)
        val result = source(node).register(
            entityId = entity.id,
            notificationsDenied = false,
            deviceToken = "device-token",
            restoreDepositCode = null,
            restoreMessage = null,
        )
        assertEquals(RegisterResult.Created, result)
        assertTrue("POST /customer was sent", requests.any { it.url.contains("/customer") })
    }

    @Test
    fun `a node that never comes up still reports the wallet as not ready`() = runTest {
        val never = object : BittrRequestSigner {
            override suspend fun pubkey(): String? = null
            override suspend fun sign(message: String): String? = null
        }
        val result = source(never).register(
            entityId = entity.id,
            notificationsDenied = false,
            deviceToken = null,
            restoreDepositCode = null,
            restoreMessage = null,
        )
        assertEquals(RegisterResult.WalletNotReady, result)
        assertTrue("nothing was posted", requests.none { it.url.contains("/customer") })
    }
}
