// Proof of concept: the Buzz watch client. `core` is plain Kotlin/JVM so the
// relay connection can be tested on a workstation without a watch; `app` is
// the Wear OS app around it.
pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "buzz-wear"
include(":core", ":app")
