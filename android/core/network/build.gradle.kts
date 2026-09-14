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

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
