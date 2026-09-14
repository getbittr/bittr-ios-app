plugins {
    alias(libs.plugins.android.library)
}

// The one module in this repo allowed to reach Firebase — the same split
// :core:network / :core:network-okhttp makes, for the same reason and with sharper
// stakes.
//
// :core:push is pure Kotlin: it turns a Map<String, String> into a PushEnvelope and a
// push_channel pair into a decision, and 51 JVM tests hold it to `api-contract` §3 and
// §4. None of that can be tested through FirebaseMessagingService, which needs a real
// device, a real Firebase project and a real sender. So the Firebase-shaped code is
// kept as thin as it can be made — receive bytes, hand them to :core:push, hand the
// answer on — and it lives here, where FirebaseMessagingGuardTest in :app can assert
// that nothing else in the app has Firebase on its classpath.
//
// That guard is not tidiness. `com.google.firebase:firebase-messaging` drags in
// play-services-basement and firebase-common; the BOM makes analytics one line away
// from any module that has Firebase in scope, and BIT-91 records what this app
// collects. One module boundary keeps "which code can reach Firebase" answerable from
// one build file.
android {
    namespace = "com.bittr.android.core.push.fcm"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // `api` on both: the service's whole job is to move values between these two
    // modules, and :app has to be able to name the types it binds.
    api(project(":core:push"))
    api(project(":core:network"))

    // The BOM pins the version; see the note in libs.versions.toml about why the
    // artefact below carries none of its own.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
