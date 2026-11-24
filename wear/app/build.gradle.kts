plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.compose")
}

android {
    namespace = "xyz.block.buzz.wear"
    compileSdk = 36

    defaultConfig {
        // Must equal the phone app's id for the Wear Data Layer to connect them.
        // A phone debug build from a worktree carries a suffix; pass the same
        // one here with -PidSuffix.
        applicationId = "xyz.block.buzz.mobile" + (providers.gradleProperty("idSuffix").orNull ?: "")
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

dependencies {
    implementation(project(":core")) {
        // Android ships org.json and needs the Android secp256k1 natives.
        exclude(group = "org.json", module = "json")
        exclude(group = "fr.acinq.secp256k1", module = "secp256k1-kmp-jni-jvm")
    }
    implementation("fr.acinq.secp256k1:secp256k1-kmp-jni-android:0.17.3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation(platform("androidx.compose:compose-bom:2025.05.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    // The system input screen: dictation, with a keyboard as fallback.
    implementation("androidx.wear:wear-input:1.1.0")
    // Pairing arrives from the phone over the Wear Data Layer.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
}
