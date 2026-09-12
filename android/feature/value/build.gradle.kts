plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.bittr.android.feature.value"
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

// No Compose and no :core:designsystem yet — this module currently holds only the
// span model and the screen's state, which are deliberately free of Android types so
// the behaviour can be tested on the JVM in seconds. The chart, the price repository
// and the Compose screen land next and bring their dependencies with them.
dependencies {
    testImplementation(libs.junit)
}
