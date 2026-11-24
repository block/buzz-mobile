plugins {
    kotlin("jvm")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // BIP-340 Schnorr. The JVM artifact carries desktop natives; the Wear app
    // swaps in secp256k1-kmp-jni-android.
    implementation("fr.acinq.secp256k1:secp256k1-kmp-jvm:0.17.3")
    runtimeOnly("fr.acinq.secp256k1:secp256k1-kmp-jni-jvm:0.17.3")
    // Bundled with Android; declared here for the JVM.
    implementation("org.json:json:20240303")

    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
