plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    api(project(":core:wallet"))
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
