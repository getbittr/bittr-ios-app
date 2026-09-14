package com.bittr.android.receive

import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.wallet.ldk.onchain.AddressUsageCheck
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/**
 * `String.checkHasBeenUsed()` (`ReceiveOnchain.swift:358–409`): `GET <esplora>/address/<address>`
 * and `chain_stats.tx_count > 0`, giving up after ten seconds.
 *
 * Null means "could not tell", and the address pool treats that as "keep the cached pool" —
 * never as unused. A timeout, a non-2xx and an unreadable body are all null.
 *
 * @param esploraBaseUrl the Esplora API root. On regtest that is the node's chain source
 *   (`LdkEnvironment.chainSourceUrl`). iOS uses a separate Esplora host on mainnet, where the
 *   node syncs over Electrum, and Android has no such setting yet — an Electrum URL passed
 *   here reads as null, so a mainnet build keeps its pool unverified rather than guessing.
 */
class EsploraAddressUsage(
    private val esploraBaseUrl: String?,
    private val http: HttpClient,
) : AddressUsageCheck {

    override suspend fun hasBeenUsed(address: String): Boolean? {
        val base = esploraBaseUrl?.takeIf { it.startsWith("https://") || it.startsWith("http://") } ?: return null
        return runCatching {
            withTimeout(TIMEOUT_MS) {
                val response = http.execute(HttpRequest(HttpMethod.GET, "${base.trimEnd('/')}/address/$address"))
                if (!response.isSuccessful) return@withTimeout null
                val txCount = JSONObject(response.body).optJSONObject("chain_stats")?.optInt("tx_count", -1) ?: -1
                if (txCount < 0) null else txCount > 0
            }
        }.getOrNull()
    }

    private companion object {
        /** `Task.sleep(nanoseconds: 10 * NSEC_PER_SEC)`. */
        const val TIMEOUT_MS = 10_000L
    }
}
