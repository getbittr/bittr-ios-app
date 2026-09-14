package com.bittr.android.send

import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.feature.send.FeeEstimates
import org.json.JSONObject
import kotlin.math.roundToLong

/**
 * `BitcoinManager.getFeeEstimates()` — mempool.space's recommended rates, which iOS reads on
 * every network, regtest included. Each rate is rounded (ldk-node takes whole sats per
 * vbyte) and never below 1.
 */
class MempoolFeeEstimates(private val http: HttpClient) {

    suspend fun fetch(): FeeEstimates? = runCatching {
        val response = http.execute(HttpRequest(HttpMethod.GET, URL))
        if (!response.isSuccessful) return@runCatching null
        val json = JSONObject(response.body)
        fun rate(key: String): Double? = json.optDouble(key, Double.NaN)
            .takeIf { it.isFinite() }
            ?.let { if (it < 1) 1.0 else it.roundToLong().toDouble() }
        FeeEstimates(
            fastest = rate("fastestFee") ?: return@runCatching null,
            hour = rate("hourFee") ?: return@runCatching null,
            economy = rate("economyFee") ?: return@runCatching null,
        )
    }.getOrNull()

    private companion object {
        const val URL = "https://mempool.space/api/v1/fees/precise"
    }
}
