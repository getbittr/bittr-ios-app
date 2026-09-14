plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Pure Kotlin, for the same reason :core:push and :core:lnurl are, and here the
// boundary is load-bearing rather than tidy: everything in this module decides
// something about a request — which backend this build talks to, what the body
// says, what the response means — and none of it should be able to send one.
//
// With no HTTP client on the classpath, nothing here can quietly acquire a socket,
// so the whole of `api-contract` §2 is provable as JVM unit tests against a backend
// that does not answer yet. :core:network-okhttp is the one module that may open a
// connection, and it implements [HttpClient] and nothing else.
kotlin {
    jvmToolchain(17)
}

dependencies {
    // For suspend on the HttpClient seam. The interface is where the dispatcher
    // choice belongs to the implementation rather than to every call site, which is
    // what HttpPriceRepository's `withContext(Dispatchers.IO)` currently hand-rolls.
    implementation(libs.kotlinx.coroutines.core)

    // `api`, not `implementation`, and the direction is deliberate: :core:push knows
    // nothing about HTTP and must keep knowing nothing, while the registration and
    // token-refresh responses defined here carry a `push_channel` pair that is only
    // meaningful as a PushChannelStatus. So the dependency points network -> push,
    // never back. The types appear on this module's public surface — every endpoint
    // in BittrApi returns one — so callers need them on their compile classpath.
    //
    // It also keeps SignedRequestMessage in one place. The bytes a signature covers
    // belong next to the decode rules that are already tested against the contract,
    // not next to the code that opens a socket; a message built one way here and
    // verified another way on the server surfaces as a 401 and sends the
    // investigation to the wallet.
    api(project(":core:push"))

    // Request bodies and response envelopes. JsonObject/JsonPrimitive only — no
    // @Serializable class and so, as in :core:push, no compiler plugin. The reason
    // is the same one PushEnvelopeDecoder gives: every field of every response is
    // read individually and tolerantly, because `api-contract` §2.1's whole
    // additivity argument rests on an unknown key being ignored rather than fatal.
    // A generated strict deserialiser would turn the backend adding a field into an
    // Android outage.
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
