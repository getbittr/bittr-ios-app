plugins {
    alias(libs.plugins.android.library)
}

// Android library rather than pure Kotlin (unlike :core:common): the whole module
// is Intents into the OS settings app, which needs android.content and
// android.provider.Settings.
android {
    namespace = "com.bittr.android.core.permissions"
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
