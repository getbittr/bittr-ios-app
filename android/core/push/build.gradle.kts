plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Pure Kotlin, for the same reason :core:lnurl is. Everything here turns a push
// payload into a decision the app acts on — including a money amount — and all of
// it has to be provable on the JVM, because the two things that would otherwise be
// needed to test it (a Firebase project that can send, and a backend that accepts
// Android tokens) are BIT-39 and BIT-9 and neither is available yet.
//
// With no Android SDK and no Firebase on the classpath, the decoder cannot reach
// FirebaseMessaging or a notification channel: the FCM service in :app hands it a
// plain Map<String, String> (RemoteMessage.getData()) and gets a PushEnvelope back.
// That seam is what makes BIT-41 item 4 testable ahead of items 3, 5 and 7.
kotlin {
    jvmToolchain(17)
}

dependencies {
    // The runtime only, with no `kotlin.plugin.serialization` alongside it. The compiler
    // plugin exists to generate serialisers for @Serializable classes, and there are none
    // here — PushEnvelopeDecoder reads a JsonObject field by field, for the per-field
    // tolerance reason documented on it. Applying a compiler plugin nothing uses would add
    // a build-time version constraint against Kotlin for no behaviour. Add it the day a
    // @Serializable DTO lands (the registration bodies in BIT-41 items 2 and 5 will want
    // one; they are Android-typed request payloads, not payloads a third party re-types).
    // `implementation`, not `api`: no kotlinx type appears in this module's public surface.
    // decode() takes a Map<String, String> and returns a PushEnvelope, so :app can call it
    // without kotlinx.serialization on its own compile classpath.
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
}
