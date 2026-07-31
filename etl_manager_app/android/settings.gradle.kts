pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Reads android/app/google-services.json and exposes its values to the
    // Firebase SDKs at build time.
    //
    // NOTE: the Firebase console tells you to put this in the ROOT
    // build.gradle.kts inside a `plugins {}` block. Do NOT do that here — this
    // project uses Flutter's declarative plugin setup, where versions are
    // declared in settings.gradle.kts. Adding a `plugins {}` block to the root
    // build file conflicts with the pluginManagement above and fails the build.
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
