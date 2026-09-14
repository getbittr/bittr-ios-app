plugins {
    alias(libs.plugins.kotlin.jvm)
}

// The one module in this repo allowed to open a socket to the bittr API.
//
// A Kotlin/JVM module rather than an Android library, which is worth stating because
// the instinct is the other way round: OkHttp is a plain JVM library and needs no
// Android SDK, and keeping this off the Android plugin is what lets its tests run
// against a real loopback server under `./gradlew test` instead of on an emulator.
// The thing being asserted — that a PATCH with this body reaches the wire — is a
// property of the bytes, and an emulator adds nothing to it.
kotlin {
    jvmToolchain(17)
}

dependencies {
    // `api`, not `implementation`: this module's public surface is
    // `HttpClient`/`HttpRequest`/`HttpResponse` from :core:network, so anything that
    // constructs OkHttpBittrHttpClient needs those types on its compile classpath.
    api(project(":core:network"))

    implementation(libs.okhttp)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockwebserver3)
}
