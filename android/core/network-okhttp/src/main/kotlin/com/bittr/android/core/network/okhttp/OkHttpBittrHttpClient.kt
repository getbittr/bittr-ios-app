package com.bittr.android.core.network.okhttp

import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpMethod
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.HttpTransportException
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/**
 * The only implementation of [HttpClient], and the only place in this repo that
 * opens a connection to the bittr API.
 *
 * Everything that decides *what* to send lives in `:core:network`, which has no HTTP
 * client on its classpath. This class is the other side of that seam and is
 * deliberately thin: it maps [HttpRequest] onto an OkHttp call and maps the outcome
 * back, and takes no decision of its own.
 *
 * ### Cancellation
 *
 * [enqueue][Call.enqueue] with a cancellable continuation, rather than
 * `withContext(Dispatchers.IO) { call.execute() }`. The blocking form cannot be
 * interrupted by coroutine cancellation, so a request started by a composable that
 * leaves the composition would hold a thread and a socket until the read timeout.
 * `api-contract` §2.3 has this client re-posting its token at every app start, which
 * is exactly the short-lived, frequently-abandoned scope where that matters.
 */
class OkHttpBittrHttpClient(
    private val client: OkHttpClient = defaultClient(),
    /**
     * Each call's method, path and outcome — no query, no body, because those carry the
     * customer's email, the deposit code and the payout signature. Off by default; the app
     * wires it to logcat in debug builds, where a flow that fails against the API ("the
     * verification code was refused") otherwise leaves no trace at all.
     */
    private val log: (String) -> Unit = {},
) : HttpClient {

    override suspend fun execute(request: HttpRequest): HttpResponse {
        val call = client.newCall(request.toOkHttpRequest())

        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(
                object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        log("${request.method} ${request.url.substringBefore('?')} failed: ${e.javaClass.simpleName}")
                        // No response at all — DNS, refused, TLS, or timeout. This
                        // is the `unavailable` shape of `api-contract` §4.2: it says
                        // nothing about the token, so it must not reach the caller
                        // looking like a status code. See HttpTransportException.
                        continuation.resumeWithException(
                            HttpTransportException(
                                "${request.method} ${request.url} did not complete: ${e.message}",
                                e,
                            ),
                        )
                    }

                    override fun onResponse(call: Call, response: Response) {
                        // `use` rather than a bare read: an unclosed ResponseBody
                        // leaks the connection out of the pool, and OkHttp only
                        // reports that through a StrictMode-style log nobody reads.
                        val decoded = response.use {
                            HttpResponse(code = it.code, body = it.body.string())
                        }
                        log("${request.method} ${request.url.substringBefore('?')} -> ${decoded.code}")
                        continuation.resume(decoded)
                    }
                },
            )
        }
    }

    private fun HttpRequest.toOkHttpRequest(): Request {
        // A POST or PATCH with everything in the query — the payout calls — still needs a body:
        // OkHttp refuses those verbs without one ("method POST must have a request body"). iOS's
        // `makeApiCall` sends such a request with no body, so this is the empty equivalent.
        val body = jsonBody?.toRequestBody(JSON)
            ?: if (method == HttpMethod.GET) null else ByteArray(0).toRequestBody(JSON)
        return Request.Builder()
            .url(url)
            // The verb is passed through as a string, which is the whole reason this
            // is OkHttp: `HttpURLConnection` validates the verb against a fixed list
            // that has no PATCH, and `api-contract` §2.3 is a PATCH.
            .method(method.name, body)
            .header("Accept", "application/json")
            .build()
    }

    private companion object {

        val JSON = "application/json; charset=utf-8".toMediaType()

        /**
         * Timeouts, deliberately stated rather than left at OkHttp's defaults.
         *
         * OkHttp defaults every timeout to 0 — meaning *no timeout* — on everything
         * except the connect/read/write triple, so a call that stalls mid-body can
         * hang for as long as the socket stays open. [callTimeout] is the one that
         * bounds the whole thing including retries and redirects, and it is what the
         * retry budget in `api-contract` §2.3 rule 2 needs in order to be a budget:
         * "≤3 attempts in one app session" is meaningless if an attempt never ends.
         *
         * 30s matches the value `HttpPriceRepository` already used for the two price
         * calls, so the app has one answer to "how long before we give up".
         */
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .callTimeout(60, TimeUnit.SECONDS)
            .build()
    }
}
