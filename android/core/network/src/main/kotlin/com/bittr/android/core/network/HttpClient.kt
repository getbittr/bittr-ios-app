package com.bittr.android.core.network

/**
 * The verbs this client uses. Not the full HTTP set — the three the bittr API is
 * reached with, so that an unsupported one is a compile error rather than a runtime
 * surprise in the binding.
 *
 * [PATCH] is the reason OkHttp is a dependency at all: `api-contract` §2.3 puts the
 * device-token endpoint behind it, and `java.net.HttpURLConnection.setRequestMethod`
 * throws `ProtocolException` for any verb outside its hardcoded array of seven,
 * which does not include PATCH. See the note in `libs.versions.toml`.
 */
enum class HttpMethod { GET, POST, PATCH }

/**
 * One request, fully resolved: [url] is absolute, and [jsonBody] is the serialised
 * body or null for a request that has none.
 *
 * The body is a `String` rather than a typed object because the seam is deliberately
 * dumb — everything that decides *what* the body says lives above this in
 * `:core:network`, where it is unit-testable, and the binding below only has to move
 * bytes. Nothing about the request shape is left to the transport.
 */
data class HttpRequest(
    val method: HttpMethod,
    val url: String,
    val jsonBody: String? = null,
) {
    init {
        require(url.startsWith("https://") || url.startsWith("http://")) {
            "HttpRequest.url must be absolute, was '$url'"
        }
        require(jsonBody == null || method != HttpMethod.GET) {
            "A GET must not carry a body (url '$url')"
        }
    }
}

/**
 * What came back. [code] is the HTTP status and [body] the raw response text, empty
 * when there was none.
 *
 * **A non-2xx is a response, not an exception**, and that is a contract requirement
 * rather than a style choice: `api-contract` §2.3 rules 2-4 turn on the client
 * distinguishing a rate-limit rejection from a bad signature, and a skew rejection
 * from `no_such_customer` — three statuses whose correct client behaviour is retry,
 * stop-forever, and retry-after-signup respectively. Collapsing them into a thrown
 * error is exactly how a client picks the wrong one.
 */
data class HttpResponse(
    val code: Int,
    val body: String,
) {
    val isSuccessful: Boolean get() = code in 200..299
}

/**
 * Raised only when there is no response at all — DNS failure, connection refused,
 * TLS failure, timeout.
 *
 * This is the distinction `api-contract` §4.2 draws with the `unavailable` verdict
 * and §4.3 then makes load-bearing: "we could not tell" is not "the token is bad".
 * A transport failure must never be read as proof of anything about the token, so it
 * arrives as a different type from a status code.
 */
class HttpTransportException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)

/**
 * The one call the app makes to reach the network.
 *
 * Implemented exactly once, by `:core:network-okhttp`. Everything above it takes
 * this interface, which is what lets the request-construction and response-handling
 * rules in `api-contract` §2 be tested without a socket — and what lets the tests
 * that *do* want a socket use a loopback server rather than a real backend.
 *
 * Implementations move to a background dispatcher themselves; callers must not have
 * to know. That is one place the existing `HttpPriceRepository` leaked the detail to
 * its call site via `withContext(Dispatchers.IO)`.
 */
interface HttpClient {

    /** @throws HttpTransportException when no response was received at all. */
    suspend fun execute(request: HttpRequest): HttpResponse
}
