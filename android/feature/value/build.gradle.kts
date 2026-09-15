plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
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

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true

            // Where GraphCardFitTest writes its PNGs. Same arrangement as :app and
            // :feature:scanner — passed in rather than derived in the test, because a
            // unit test's working directory is an AGP implementation detail and the
            // value of these files is being able to tell someone where they are.
            all {
                it.systemProperty(
                    "bittr.screenshot.dir",
                    layout.buildDirectory.dir("screenshots").get().asFile.absolutePath,
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// No charting library. The chart is one stroked path and a card that follows a
// finger; a library would bring its own gesture handling, and the gesture is the
// part `bitcoin_value.yaml` drives.
dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:designsystem"))
    // `api`, not `implementation`: BittrEnvironment and HttpClient are parameters of
    // the public ValueScreen, so :app needs them on its compile classpath. They are
    // parameters because this screen used to hold the production price URL as a
    // constant — see HttpPriceRepository (BIT-32 / BIT-41 item 1).
    api(project(":core:network"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
